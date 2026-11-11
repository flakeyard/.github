#!/usr/bin/env bash
# The check of GitHub App installations at the end of settings.sh.
set -uo pipefail
# shellcheck source=tests/lib.sh
source "$(dirname -- "${BASH_SOURCE[0]}")/../lib.sh"

readonly listed=$root/org/organization/installations.json
# The request that lists the installations.
readonly listing='orgs/fy/installations?per_page=100'

# installed JQ: answer the listing of installations with the Apps of
# installations.json changed by JQ, and the fields the check ignores.
installed() {
  local change=$1
  fixture "$listing" \
    "$(jq "{installations: (map(. + {id: 1, app_id: 2}) | $change)}" "$listed")"
}

# run_settings NAME EXPECTED: run settings.sh.
run_settings() {
  local name=$1 expected=$2
  run "$name" "$expected" org/settings.sh
}

setup_org
installed .
run_settings "as listed" ok
expect call "GET $listing"
expect message 'installations of GitHub Apps checked'
finish

setup_org
installed '.[:1]'
next_page "$listing" 2 "$(jq '{installations: .[1:]}' "$listed")"
run_settings "two pages" ok
finish

setup_org
installed 'map(select(.app_slug == "flakeyard-bot")
  | .repository_selection = "selected"
  | .permissions += {administration: "write", contents: "admin"}
  | del(.permissions.issues))
  + [{app_slug: "stranger", repository_selection: "all", permissions: {}}]'
run_settings "drift" fail
# The settings are applied before the check.
expect call "PATCH orgs/fy --input=$(jq -c . "$root/org/organization/settings.json")"
expect call 'orgs/fy/actions/permissions/self-hosted-runners'
expect message 'renovate: not installed'
expect message 'flakeyard-bot: installed for selected repositories, not all'
expect message 'flakeyard-bot: permission administration is write, allowed none'
expect message 'flakeyard-bot: permission contents is admin, allowed write'
# A missing permission is fine.
expect no-message 'permission issues'
expect message 'stranger: installed, but not listed'
expect no-message 'checked'
finish

# The release bot writes workflows: GitHub refuses the tag of a release made by
# an App otherwise, since the commits of the tag carry workflow files.
setup_org
installed 'map(if .app_slug == "flakeyard-bot"
  then .permissions.workflows = "write" else . end)'
run_settings "bot workflows" ok
expect no-message 'permission workflows'
finish

setup_org
installed 'map(if .app_slug == "renovate"
  then . + {suspended_at: "2026-11-01T00:00:00Z"} else . end)'
run_settings "suspended" fail
expect message 'renovate: suspended since 2026-11-01T00:00:00Z'
expect no-message 'checked'
finish

setup_org
installed 'map(. + {suspended_at: null})'
run_settings "not suspended" ok
finish

setup_org
apply FAIL_ON="GET $listing 500"
run_settings "listing fails" fail
expect no-message 'checked'
finish

conclude
