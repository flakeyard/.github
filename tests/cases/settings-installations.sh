#!/usr/bin/env bash
# The check of GitHub App installations at the end of settings.sh.
set -uo pipefail
# shellcheck source=tests/lib.sh
source "$(dirname -- "${BASH_SOURCE[0]}")/../lib.sh"

readonly listed=$root/org/organization/installations.json
readonly installations=orgs/fy/installations

# installed JQ: answer the listing of installations with the Apps of
# installations.json changed by JQ, and the fields the check ignores.
installed() {
  local change=$1
  jq "{installations: (map(. + {id: 1, app_id: 2}) | $change)}" "$listed" \
    | fixture GET "$installations"
}

# applied: whether the settings were applied before the check.
applied() {
  called '-X PATCH orgs/fy --input settings.json' \
    && called 'orgs/fy/actions/permissions/self-hosted-runners'
}

installed .
run_org settings.sh
check "as listed: exits 0" exited 0
check "as listed: paginates" called "--paginate $installations\\?per_page=100"
check "as listed: reports the check" \
  printed 'installations of GitHub Apps checked'

installed '.[:1]'
jq '{installations: .[1:]}' "$listed" \
  | fixture GET "$installations.2"
run_org settings.sh
check "two pages: exits 0" exited 0
clear_fixtures

installed 'map(select(.app_slug == "flakeyard-bot")
  | .repository_selection = "selected"
  | .permissions += {administration: "write", contents: "admin"}
  | del(.permissions.issues))
  + [{app_slug: "stranger", repository_selection: "all", permissions: {}}]'
run_org settings.sh
check "drift: exits 1" exited 1
check "drift: settings are applied" applied
check "drift: not installed" printed 'renovate: not installed'
check "drift: selected repositories" \
  printed 'flakeyard-bot: installed for selected repositories, not all'
check "drift: unlisted permission" \
  printed 'flakeyard-bot: permission administration is write, allowed none'
check "drift: higher permission" \
  printed 'flakeyard-bot: permission contents is admin, allowed write'
check "drift: a missing permission is fine" \
  not printed 'permission issues'
check "drift: unlisted App" printed 'stranger: installed, but not listed'
check "drift: no success" not printed 'checked'

# The release bot writes workflows: GitHub refuses the tag of a release made by
# an App otherwise, since the commits of the tag carry workflow files.
installed 'map(if .app_slug == "flakeyard-bot"
  then .permissions.workflows = "write" else . end)'
run_org settings.sh
check "bot workflows: exits 0" exited 0
check "bot workflows: not drift" not printed 'permission workflows'

installed 'map(if .app_slug == "renovate"
  then . + {suspended_at: "2026-11-01T00:00:00Z"} else . end)'
run_org settings.sh
check "suspended: exits 1" exited 1
check "suspended: reported" \
  printed 'renovate: suspended since 2026-11-01T00:00:00Z'
check "suspended: no success" not printed 'checked'

installed 'map(. + {suspended_at: null})'
run_org settings.sh
check "not suspended: exits 0" exited 0

fixture_status GET "$installations" 500
run_org settings.sh
check "listing fails: exits non-zero" not exited 0
check "listing fails: no success" not printed 'checked'

finish
