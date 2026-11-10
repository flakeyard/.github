#!/usr/bin/env bash
# The repositories of apply.sh and the audit when no repository is given:
# every non-archived repository of the organization, from every page.
set -uo pipefail
# shellcheck source=tests/lib.sh
source "$(dirname -- "${BASH_SOURCE[0]}")/../lib.sh"

# run SCRIPT: run SCRIPT without arguments, with what each script requires.
run() { BOT_APP_ID=42 BOT_LOGIN='bot[bot]' run_org "$1"; }

for script in apply.sh audit/releases.sh; do
  jq -n '[{name: "atom-x", archived: false}, {name: "old", archived: true}]' \
    | fixture GET orgs/fy/repos
  jq -n '[{name: "atom-y", archived: false}]' | fixture GET orgs/fy/repos.2
  run "$script"
  check "$script: exits 0" exited 0
  check "$script: paginates repositories" \
    called "--paginate orgs/fy/repos\\?per_page=100"
  check "$script: the first page" called repos/fy/atom-x
  check "$script: the second page" called repos/fy/atom-y
  check "$script: skips archived repositories" not called repos/fy/old
  clear_fixtures

  jq -n '[{name: "old", archived: true}]' | fixture GET orgs/fy/repos
  run "$script"
  check "$script: none: exits 1" exited 1
  check "$script: none: says so" printed 'no repositories in fy'
  clear_fixtures

  fixture_status GET orgs/fy/repos 500
  run "$script"
  check "$script: listing fails: exits non-zero" not exited 0
  check "$script: listing fails: nothing else is called" \
    not called repos/fy/
  clear_fixtures
done

finish
