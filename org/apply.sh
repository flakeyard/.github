#!/usr/bin/env bash
# Apply repository settings, labels, rulesets and security features.
#
# Usage: apply.sh [repo...]
#   Without arguments, applies to every non-archived repository of $ORG.
#
# Requires gh with a token that has the repo scope, and jq. The GitHub App
# that may create and move release tags is read from $BOT_APP_ID or from the
# organization variable BOT_APP_ID.
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

has_commits() {
  # An empty repository answers 409 Conflict.
  gh api "repos/$org/$1/commits?per_page=1" >/dev/null 2>&1
}

render_ruleset() {
  jq --argjson app "$bot_app_id" \
    'walk(if . == "@BOT_APP_ID@" then $app else . end)' "$1"
}

apply_settings() {
  gh api --silent -X PATCH "repos/$org/$1" \
    --input "$here/repository/settings.json"
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

apply_security() {
  local repo=$1
  gh api --silent -X PUT "repos/$org/$repo/vulnerability-alerts"
  gh api --silent -X PUT "repos/$org/$repo/private-vulnerability-reporting"
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
  apply_rulesets "$repo"
  apply_security "$repo"
  printf '%s: done\n' "$repo"
done
