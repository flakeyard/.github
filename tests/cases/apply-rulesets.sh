#!/usr/bin/env bash
# The rulesets of apply.sh: created when missing, replaced by id when present,
# and drift reported, but kept.
set -uo pipefail
# shellcheck source=tests/lib.sh
source "$(dirname -- "${BASH_SOURCE[0]}")/../lib.sh"

readonly rulesets=repos/fy/atom-x/rulesets
# The request that lists the rulesets.
readonly listing="$rulesets?includes_parents=false&per_page=100"

# page RULESET...: print a page of the listing of rulesets with "NAME=ID"
# pairs.
page() {
  local pair
  for pair; do
    jq -n --arg name "${pair%=*}" --argjson id "${pair#*=}" \
      '{id: $id, name: $name, source_type: "Repository"}'
  done | jq -s .
}

# listed RULESET...: answer the listing of rulesets with "NAME=ID" pairs.
listed() {
  fixture "$listing" "$(page "$@")"
}

# release_tags: the body of the ruleset release-tags with the bot app 42.
release_tags() {
  jq -c '.bypass_actors[0].actor_id = 42' \
    "$root/org/repository/rulesets/release-tags.json"
}

# apply_rulesets NAME EXPECTED: run apply.sh on atom-x with the bot app 42.
apply_rulesets() {
  local name=$1 expected=$2
  run "$name" "$expected" org/apply.sh BOT_APP_ID=42 -- atom-x
}

setup_org
listed
apply_rulesets "none" ok
expect call "GET $listing"
expect call "POST $rulesets --input=$(jq -c . "$root/org/repository/rulesets/main.json")"
expect call "POST $rulesets --input=$(release_tags)"
expect no-call "PUT $rulesets/"
expect no-message 'warning:'
finish

setup_org
listed main=1 release-branches=2 release-tags=3 version-branches=4
apply_rulesets "all" ok
expect call "PUT $rulesets/1 --input="
expect call "PUT $rulesets/3 --input=$(release_tags)"
expect no-call "POST $rulesets"
finish

setup_org
listed main=1
next_page "$listing" 2 "$(page release-tags=3)"
apply_rulesets "two pages: replaces release-tags of page 2" ok
expect call "PUT $rulesets/3 --input="
finish

setup_org
listed main=1 hotfix=7
apply_rulesets "unmanaged" ok
expect message 'warning: atom-x: rulesets not in repository/rulesets/:'
expect message hotfix
expect no-call "$rulesets/7"
expect message 'atom-x: done'
finish

setup_org
listed main=1 main=2
apply_rulesets "duplicate" fail
expect message 'several rulesets are named main'
expect no-call "PUT $rulesets/"
expect no-message 'atom-x: done'
finish

conclude
