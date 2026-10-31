# shellcheck shell=bash disable=SC2154 # globals of apply.sh
# Rulesets of a repository, from repository/rulesets/. Sourced by apply.sh,
# which sets org, here and bot_app_id.

render_ruleset() {
  local file=$1
  jq --argjson app "$bot_app_id" \
    'walk(if . == "@BOT_APP_ID@" then $app else . end)' "$file"
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
