#!/usr/bin/env bash
# The repositories of apply.sh and the audit when no repository is given:
# every non-archived repository of the organization, from every page.
set -uo pipefail
# shellcheck source=tests/lib.sh
source "$(dirname -- "${BASH_SOURCE[0]}")/../lib.sh"

# The request that lists the repositories of the organization.
readonly listing='orgs/fy/repos?per_page=100'

# run_without_repositories NAME EXPECTED SCRIPT: run org/SCRIPT without
# arguments, with what each script requires.
run_without_repositories() {
  local name=$1 expected=$2 script=$3
  run "$script: $name" "$expected" "org/$script" BOT_APP_ID=42 BOT_LOGIN='bot[bot]'
}

for script in apply.sh audit/releases.sh; do
  setup_org
  fixture "$listing" \
    '[{"name": "atom-x", "archived": false}, {"name": "old", "archived": true}]'
  next_page "$listing" 2 '[{"name": "atom-y", "archived": false}]'
  run_without_repositories "every page" ok "$script"
  expect call "GET $listing"
  expect call repos/fy/atom-x
  expect call repos/fy/atom-y
  expect no-call repos/fy/old
  finish

  setup_org
  fixture "$listing" '[{"name": "old", "archived": true}]'
  run_without_repositories "none" fail "$script"
  expect message 'no repositories in fy'
  finish

  setup_org
  apply FAIL_ON="GET $listing 500"
  run_without_repositories "listing fails" fail "$script"
  expect no-call repos/fy/
  finish
done

conclude
