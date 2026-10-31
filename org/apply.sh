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

render_ruleset() {
  jq --argjson app "$bot_app_id" \
    'walk(if . == "@BOT_APP_ID@" then $app else . end)' "$1"
}

apply_settings() {
  gh api --silent -X PATCH "repos/$org/$1" \
    --input "$here/repository/settings.json"
  # Discussions of the .github repository are the discussions of the whole
  # organization.
  if [[ $1 == .github ]]; then
    gh api --silent -X PATCH "repos/$org/$1" -F has_discussions=true
  fi
}

apply_labels() {
  local repo=$1 name color description
  jq -r '.[] | [.name, .color, .description] | @tsv' \
    "$here/repository/labels.json" \
    | while IFS=$'\t' read -r name color description; do
      gh label create "$name" --repo "$org/$repo" --color "$color" \
        --description "$description" --force >/dev/null
    done
}

apply_topics() {
  local repo=$1 current
  current=$(gh api "repos/$org/$repo/topics" --jq '.names')
  # Keys of topics.json are globs; only "*" is special. Existing topics stay.
  jq --arg repo "$repo" --argjson current "$current" '
    def glob: "^" + (gsub("\\."; "\\.") | gsub("\\*"; ".*")) + "$";
    {names: ($current + [to_entries[]
      | select(.key as $k | $repo | test($k | glob)) | .value[]] | unique)}
  ' "$here/repository/topics.json" \
    | gh api --silent -X PUT "repos/$org/$repo/topics" --input -
}

apply_rulesets() {
  local repo=$1 existing file name id
  existing=$(gh api "repos/$org/$repo/rulesets" \
    --jq '.[] | "\(.name)\t\(.id)"')
  for file in "$here"/repository/rulesets/*.json; do
    name=$(jq -r .name "$file")
    id=$(awk -F '\t' -v n="$name" '$1 == n { print $2 }' <<<"$existing")
    if [[ -n $id ]]; then
      render_ruleset "$file" \
        | gh api --silent -X PUT "repos/$org/$repo/rulesets/$id" --input -
    else
      render_ruleset "$file" \
        | gh api --silent -X POST "repos/$org/$repo/rulesets" --input -
    fi
  done
}

is_released() {
  [[ $1 != .github && $1 != decisions ]]
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

apply_environments() {
  local repo=$1 env
  is_released "$repo" || return 0
  env="repos/$org/$repo/environments/release"
  # The bot key is available only to jobs on main and release branches.
  gh api --silent -X PUT "$env" \
    -F 'deployment_branch_policy[protected_branches]=false' \
    -F 'deployment_branch_policy[custom_branch_policies]=true'
  allow_deployment_branches "$env"
  if [[ -n $bot_key_file ]]; then
    # The name must match the secret declared by the release workflow: an
    # environment secret reaches a reusable workflow only under the name the
    # caller passes.
    gh secret set APP_PRIVATE_KEY --repo "$org/$repo" --env release \
      <"$bot_key_file"
  fi
}

apply_security() {
  local repo=$1
  gh api --silent -X PUT "repos/$org/$repo/vulnerability-alerts"
  gh api --silent -X PUT "repos/$org/$repo/private-vulnerability-reporting"
  gh api --silent -X PUT "repos/$org/$repo/immutable-releases"
  # CodeQL default setup conflicts with an own CodeQL workflow, so it is
  # enabled only for atoms and actions, and only once there is a commit.
  if [[ $repo == atom-* || $repo == action-* ]] && has_commits "$repo"; then
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
