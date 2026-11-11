#!/usr/bin/env bash
# The permissions of GITHUB_TOKEN set by apply.sh: only released repositories
# let it create and approve pull requests.
set -uo pipefail
# shellcheck source=tests/lib.sh
source "$(dirname -- "${BASH_SOURCE[0]}")/../lib.sh"

readonly organization=$root/org/organization/actions/workflow.json
readonly http_conflict=409

# put REPO: the request that sets the workflow permissions of REPO.
put() {
  local repo=$1
  printf 'PUT repos/fy/%s/actions/permissions/workflow' "$repo"
}

# permissions CAN_APPROVE: the body that sets the workflow permissions.
permissions() {
  local can_approve=$1
  printf '{"default_workflow_permissions":"read","can_approve_pull_request_reviews":%s}' \
    "$can_approve"
}

# allows_pull_requests FILE: whether the settings FILE let GITHUB_TOKEN create
# pull requests and keep its default permissions read-only.
allows_pull_requests() {
  local file=$1
  jq -e '.can_approve_pull_request_reviews == true
    and .default_workflow_permissions == "read"' "$file" >/dev/null
}

setup
run_lib "the organization lets repositories allow it" ok "" \
  allows_pull_requests "$organization"
finish

for repo in atom-x action-y workflow-z image-w template-v renovate-config; do
  setup_org
  run "$repo creates pull requests" ok org/apply.sh BOT_APP_ID=42 -- "$repo"
  expect call "$(put "$repo") --input=$(permissions true)"
  finish
done

for repo in .github decisions probe-renovate; do
  setup_org
  run "$repo creates no pull requests" ok org/apply.sh BOT_APP_ID=42 -- "$repo"
  expect call "$(put "$repo") --input=$(permissions false)"
  finish
done

# The organization forbids the flag: GitHub answers 409 Conflict.
setup_org
apply FAIL_ON="$(put atom-x) $http_conflict"
run "forbidden" fail org/apply.sh BOT_APP_ID=42 -- atom-x
expect no-message 'atom-x: done'
finish

conclude
