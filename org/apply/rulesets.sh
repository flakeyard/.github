# shellcheck shell=bash disable=SC2154 # globals of apply.sh
# Rulesets of a repository, from repository/rulesets/. Sourced by apply.sh,
# which sets org, here and bot_app_id.

render_ruleset() {
  local file=$1
  jq --argjson app "$bot_app_id" \
    'walk(if . == "@BOT_APP_ID@" then $app else . end)' "$file"
}

# list_rulesets RULESETS: print the rulesets of the API path RULESETS as one
# JSON list. Rulesets inherited from the organization are left out: their ids
# are not the repository's to replace.
list_rulesets() {
  local rulesets=$1
  api_list "$rulesets?includes_parents=false&per_page=100" '.[]'
}

# ruleset_id NAME: print the id of the ruleset NAME from the listing of
# rulesets on stdin, or nothing. Fails when several rulesets have that name.
ruleset_id() {
  local name=$1 ids
  ids=$(jq -r --arg name "$name" '.[] | select(.name == $name) | .id')
  [[ $ids != *$'\n'* ]] || die "several rulesets are named $name"
  printf '%s\n' "$ids"
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

# unmanaged_rulesets: print the name of every ruleset of the listing on stdin
# that no file of repository/rulesets/ defines.
unmanaged_rulesets() {
  local managed
  managed=$(jq -s 'map(.name)' "$here"/repository/rulesets/*.json)
  jq -r --argjson managed "$managed" \
    '.[].name | select(IN($managed[]) | not)'
}

# warn_unmanaged_rulesets REPO EXISTING: warn about every ruleset of the
# listing EXISTING that the files do not define. It is drift, but it is left
# in place: a ruleset only adds rules, so it cannot weaken the managed ones.
warn_unmanaged_rulesets() {
  local repo=$1 existing=$2 unmanaged
  unmanaged=$(unmanaged_rulesets <<<"$existing")
  [[ -n $unmanaged ]] || return 0
  printf 'warning: %s: rulesets not in repository/rulesets/:\n%s\n' \
    "$repo" "$unmanaged" >&2
}

apply_rulesets() {
  local repo=$1 rulesets existing file id
  rulesets="repos/$org/$repo/rulesets"
  existing=$(list_rulesets "$rulesets")
  for file in "$here"/repository/rulesets/*.json; do
    id=$(ruleset_id "$(jq -r .name "$file")" <<<"$existing")
    upsert_ruleset "$rulesets" "$file" "$id"
  done
  warn_unmanaged_rulesets "$repo" "$existing"
}
