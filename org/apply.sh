#!/usr/bin/env bash
# Apply repository settings, labels, topics, rulesets and security features.
#
# Usage: apply.sh [repo...]
#   Without arguments, applies to every non-archived repository of $ORG.
#
# Requires gh with a token that has the repo scope, and jq. The GitHub App
# that may create and move release tags is read from $BOT_APP_ID or from the
# organization variable BOT_APP_ID. When $BOT_PRIVATE_KEY_FILE names its private
# key, the key is stored in the environment "release" of released repositories.
set -euo pipefail

org=${ORG:-flakeyard}
here=$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)

die() {
  printf '%s\n' "$*" >&2
  exit 1
}

for tool in gh jq; do
  command -v "$tool" >/dev/null || die "missing tool: $tool"
done

bot_app_id=${BOT_APP_ID:-}
if [[ -z $bot_app_id ]]; then
  bot_app_id=$(gh variable get BOT_APP_ID --org "$org" 2>/dev/null) || true
fi
[[ $bot_app_id =~ ^[0-9]+$ ]] \
  || die "BOT_APP_ID is not set (environment or organization variable)"

bot_key_file=${BOT_PRIVATE_KEY_FILE:-}
[[ -z $bot_key_file || -r $bot_key_file ]] \
  || die "cannot read BOT_PRIVATE_KEY_FILE: $bot_key_file"

# Status codes of GitHub API responses.
readonly http_ok=200 http_conflict=409

# Branches that may deploy to the environment "release".
readonly release_branches=(main 'release/v*')

# http_status PATH: print the HTTP status code of a GET request to PATH.
http_status() {
  local path=$1 response
  # gh fails on any status but 2xx; the status line is printed anyway.
  response=$(gh api -i "$path" 2>/dev/null) || true
  awk 'NR == 1 { print $2 }' <<<"$response"
}

has_commits() {
  local repo=$1 status
  status=$(http_status "repos/$org/$repo/commits?per_page=1")
  case $status in
    "$http_ok") return 0 ;;
    # An empty repository answers 409 Conflict.
    "$http_conflict") return 1 ;;
    *) die "cannot list commits of $repo: HTTP ${status:-no response}" ;;
  esac
}

# A jq function that turns a glob of repository names into a regex; only "*"
# is special.
readonly jq_glob='def glob: "^" + (gsub("\\."; "\\.") | gsub("\\*"; ".*")) + "$";'

render_ruleset() {
  local file=$1
  jq --argjson app "$bot_app_id" \
    'walk(if . == "@BOT_APP_ID@" then $app else . end)' "$file"
}

apply_settings() {
  local repo=$1
  gh api --silent -X PATCH "repos/$org/$repo" \
    --input "$here/repository/settings.json"
  # Discussions of the .github repository are the discussions of the whole
  # organization.
  if [[ $repo == .github ]]; then
    gh api --silent -X PATCH "repos/$org/$repo" -F has_discussions=true
  fi
}

# Labels are compared as "name<TAB>color<TAB>description" lines.

# current_labels REPO: print every label of REPO.
current_labels() {
  local repo=$1
  gh api --paginate "repos/$org/$repo/labels?per_page=100" \
    --jq '.[] | [.name, .color, .description // ""] | @tsv'
}

# wanted_labels: print every label of labels.json.
wanted_labels() {
  jq -r '.[] | [.name, .color, .description] | @tsv' \
    "$here/repository/labels.json"
}

# create_label REPO LABEL: create the label described by the line LABEL.
create_label() {
  local repo=$1 label=$2 name color description
  IFS=$'\t' read -r name color description <<<"$label"
  gh api --silent -X POST "repos/$org/$repo/labels" \
    -f name="$name" -f color="$color" -f description="$description"
}

# update_label REPO OLD LABEL: make the label named OLD match the line LABEL.
update_label() {
  local repo=$1 old=$2 label=$3 path name color description
  IFS=$'\t' read -r name color description <<<"$label"
  path=$(jq -rn --arg name "$old" '$name | @uri')
  gh api --silent -X PATCH "repos/$org/$repo/labels/$path" \
    -f new_name="$name" -f color="$color" -f description="$description"
}

apply_labels() {
  local repo=$1 current wanted label name existing
  local -A by_name=()
  current=$(current_labels "$repo")
  wanted=$(wanted_labels)
  # GitHub compares label names ignoring case.
  while IFS= read -r label; do
    name=${label%%$'\t'*}
    [[ -n $name ]] && by_name[${name,,}]=$label
  done <<<"$current"
  while IFS= read -r label; do
    name=${label%%$'\t'*}
    existing=${by_name[${name,,}]-}
    if [[ -z $existing ]]; then
      create_label "$repo" "$label"
    elif [[ $existing != "$label" ]]; then
      update_label "$repo" "${existing%%$'\t'*}" "$label"
    fi
  done <<<"$wanted"
}

apply_topics() {
  local repo=$1
  # Keys of topics.json are globs. Topics that are not listed there are drift
  # and are removed.
  jq --arg repo "$repo" "$jq_glob"'
    {names: ([to_entries[]
      | select(.key as $k | $repo | test($k | glob)) | .value[]] | unique)}
  ' "$here/repository/topics.json" \
    | gh api --silent -X PUT "repos/$org/$repo/topics" --input -
}

# ruleset_id NAME: print the id of the ruleset NAME from the listing of
# rulesets on stdin, or nothing.
ruleset_id() {
  local name=$1
  jq -r --arg name "$name" '.[] | select(.name == $name) | .id'
}

# upsert_ruleset RULESETS FILE ID: replace the ruleset ID of the API path
# RULESETS with FILE, or create it when ID is empty.
upsert_ruleset() {
  local rulesets=$1 file=$2 id=$3
  if [[ -n $id ]]; then
    render_ruleset "$file" | gh api --silent -X PUT "$rulesets/$id" --input -
  else
    render_ruleset "$file" | gh api --silent -X POST "$rulesets" --input -
  fi
}

apply_rulesets() {
  local repo=$1 rulesets existing file id
  rulesets="repos/$org/$repo/rulesets"
  existing=$(gh api "$rulesets")
  for file in "$here"/repository/rulesets/*.json; do
    id=$(ruleset_id "$(jq -r .name "$file")" <<<"$existing")
    upsert_ruleset "$rulesets" "$file" "$id"
  done
}

# is_released REPO: whether REPO matches a glob of released.json.
is_released() {
  local repo=$1 status=0
  jq -e --arg repo "$repo" "$jq_glob"'
    any(.[]; glob as $re | $repo | test($re))
  ' "$here/repository/released.json" >/dev/null || status=$?
  # jq -e exits with 1 for false and above 1 for errors.
  ((status <= 1)) || die "cannot read released.json"
  ((status == 0))
}

# contains WORD LIST...: whether WORD is one of LIST.
contains() {
  local word=$1 item
  shift
  for item; do
    [[ $item == "$word" ]] && return 0
  done
  return 1
}

# branch_policies ENV: print "id<TAB>type<TAB>name" of every deployment policy.
branch_policies() {
  local env=$1
  gh api --paginate "$env/deployment-branch-policies?per_page=100" \
    --jq '.branch_policies[] | [.id, .type // "branch", .name] | @tsv'
}

# allow_deployment_branches ENV: make the release branches the only policies.
allow_deployment_branches() {
  local env=$1 policies id type name kept=() branch
  policies=$(branch_policies "$env")
  while IFS=$'\t' read -r id type name; do
    [[ -n $id ]] || continue
    if [[ $type == branch ]] && contains "$name" "${release_branches[@]}"; then
      kept+=("$name")
    else
      gh api --silent -X DELETE "$env/deployment-branch-policies/$id"
    fi
  done <<<"$policies"
  for branch in "${release_branches[@]}"; do
    contains "$branch" "${kept[@]}" && continue
    gh api --silent -X POST "$env/deployment-branch-policies" \
      -f name="$branch" -f type=branch
  done
}

# create_release_environment ENV: create ENV with custom branch policies.
create_release_environment() {
  local env=$1
  gh api --silent -X PUT "$env" \
    -F 'deployment_branch_policy[protected_branches]=false' \
    -F 'deployment_branch_policy[custom_branch_policies]=true'
}

# store_bot_key REPO: store the bot key in the environment "release" of REPO
# when $BOT_PRIVATE_KEY_FILE is given.
store_bot_key() {
  local repo=$1
  [[ -n $bot_key_file ]] || return 0
  # The name must match the secret declared by the release workflow: an
  # environment secret reaches a reusable workflow only under the name the
  # caller passes.
  gh secret set APP_PRIVATE_KEY --repo "$org/$repo" --env release \
    <"$bot_key_file"
}

apply_environments() {
  local repo=$1 env
  is_released "$repo" || return 0
  env="repos/$org/$repo/environments/release"
  # The bot key is available only to jobs on main and release branches.
  create_release_environment "$env"
  allow_deployment_branches "$env"
  store_bot_key "$repo"
}

# CodeQL default setup conflicts with an own CodeQL workflow, so it is
# enabled only for atoms and actions.
wants_default_code_scanning() {
  local repo=$1
  [[ $repo == atom-* || $repo == action-* ]]
}

apply_security() {
  local repo=$1
  gh api --silent -X PUT "repos/$org/$repo/vulnerability-alerts"
  gh api --silent -X PUT "repos/$org/$repo/private-vulnerability-reporting"
  gh api --silent -X PUT "repos/$org/$repo/immutable-releases"
  # Default setup needs a commit to scan.
  if wants_default_code_scanning "$repo" && has_commits "$repo"; then
    gh api --silent -X PATCH "repos/$org/$repo/code-scanning/default-setup" \
      -f state=configured
  fi
}

repos=("$@")
if ((${#repos[@]} == 0)); then
  # Assigned separately so that a failing gh stops the script.
  all=$(gh repo list "$org" --limit 1000 --no-archived \
    --json name --jq '.[].name')
  [[ -n $all ]] || die "no repositories in $org"
  mapfile -t repos <<<"$all"
fi

for repo in "${repos[@]}"; do
  apply_settings "$repo"
  apply_labels "$repo"
  apply_topics "$repo"
  apply_rulesets "$repo"
  apply_environments "$repo"
  apply_security "$repo"
  printf '%s: done\n' "$repo"
done
