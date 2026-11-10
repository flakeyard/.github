#!/usr/bin/env bash
# The repositories of apply.sh and the audit when no repository is given:
# every non-archived repository of the organization, from every page.
set -uo pipefail
# shellcheck source=tests/lib.sh
source "$(dirname -- "${BASH_SOURCE[0]}")/../lib.sh"

# run_without_repositories NAME EXPECTED SCRIPT: run org/SCRIPT without
# arguments, with what each script requires.
run_without_repositories() {
  local name=$1 expected=$2 script=$3
  run "$script: $name" "$expected" "org/$script" BOT_APP_ID=42 BOT_LOGIN='bot[bot]'
}

for script in apply.sh audit/releases.sh; do
  setup_org
  jq -n '[{name: "atom-x", archived: false}, {name: "old", archived: true}]' \
    | fixture GET orgs/fy/repos
  jq -n '[{name: "atom-y", archived: false}]' | fixture GET orgs/fy/repos.2
  run_without_repositories "every page" ok "$script"
  expect call "--paginate orgs/fy/repos\\?per_page=100"
  expect call repos/fy/atom-x
  expect call repos/fy/atom-y
  expect no-call repos/fy/old
  finish

  setup_org
  jq -n '[{name: "old", archived: true}]' | fixture GET orgs/fy/repos
  run_without_repositories "none" fail "$script"
  expect message 'no repositories in fy'
  finish

  setup_org
  fixture_status GET orgs/fy/repos 500
  run_without_repositories "listing fails" fail "$script"
  expect no-call repos/fy/
  finish
done

conclude
