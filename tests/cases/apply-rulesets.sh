#!/usr/bin/env bash
# The rulesets of apply.sh: created when missing, replaced by id when present,
# and drift reported, but kept.
set -uo pipefail
# shellcheck source=tests/lib.sh
source "$(dirname -- "${BASH_SOURCE[0]}")/../lib.sh"

readonly rulesets=repos/fy/atom-x/rulesets

# listed RULESET...: answer the listing of rulesets with "NAME=ID" pairs.
listed() {
  local pair
  for pair; do
    jq -n --arg name "${pair%=*}" --argjson id "${pair#*=}" \
      '{id: $id, name: $name, source_type: "Repository"}'
  done | jq -s . | fixture GET "$rulesets"
}

# release_tags: the body of the ruleset release-tags with the bot app 42.
release_tags() {
  jq -c '.bypass_actors[0].actor_id = 42' \
    "$root/org/repository/rulesets/release-tags.json"
}

listed
BOT_APP_ID=42 run_org apply.sh atom-x
check "none: exits 0" exited 0
check "none: lists only the repository's own" \
  called "--paginate $rulesets\\?includes_parents=false\\&per_page=100"
check "none: creates main" \
  sent "api --silent -X POST $rulesets --input -" \
  "$(jq -c . "$root/org/repository/rulesets/main.json")"
check "none: puts the bot app id" \
  sent "api --silent -X POST $rulesets --input -" "$(release_tags)"
check "none: replaces nothing" not called "-X PUT $rulesets/"
check "none: no warning" not printed 'warning:'

listed main=1 release-branches=2 release-tags=3 version-branches=4
BOT_APP_ID=42 run_org apply.sh atom-x
check "all: exits 0" exited 0
check "all: replaces main by id" called "-X PUT $rulesets/1 --input -"
check "all: replaces release-tags by id" \
  sent "api --silent -X PUT $rulesets/3 --input -" "$(release_tags)"
check "all: creates none" not called "-X POST $rulesets"

listed main=1
jq -n '[{id: 3, name: "release-tags", source_type: "Repository"}]' \
  | fixture GET "$rulesets.2"
BOT_APP_ID=42 run_org apply.sh atom-x
check "two pages: replaces release-tags of page 2" \
  called "-X PUT $rulesets/3 --input -"
clear_fixtures

listed main=1 hotfix=7
BOT_APP_ID=42 run_org apply.sh atom-x
check "unmanaged: exits 0" exited 0
check "unmanaged: warns" \
  printed 'warning: atom-x: rulesets not in repository/rulesets/:'
check "unmanaged: names it" printed hotfix
check "unmanaged: keeps it" not called "$rulesets/7"
check "unmanaged: is applied" printed 'atom-x: done'

listed main=1 main=2
BOT_APP_ID=42 run_org apply.sh atom-x
check "duplicate: exits non-zero" not exited 0
check "duplicate: names it" printed 'several rulesets are named main'
check "duplicate: replaces nothing" not called "-X PUT $rulesets/"
check "duplicate: is not done" not printed 'atom-x: done'

finish
