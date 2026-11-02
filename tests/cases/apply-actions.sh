#!/usr/bin/env bash
# The permissions of GITHUB_TOKEN set by apply.sh: only released repositories
# let it create and approve pull requests.
set -uo pipefail
# shellcheck source=tests/lib.sh
source "$(dirname -- "${BASH_SOURCE[0]}")/../lib.sh"

readonly organization=$root/org/organization/actions/workflow.json
readonly http_conflict=409

# put REPO: the call that sets the workflow permissions of REPO.
put() {
  local repo=$1
  printf 'api --silent -X PUT repos/fy/%s/actions/permissions/workflow --input -' \
    "$repo"
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

check "the organization lets repositories allow it" \
  allows_pull_requests "$organization"

for repo in atom-x action-y workflow-z image-w template-v renovate-config; do
  BOT_APP_ID=42 run_org apply.sh "$repo"
  check "$repo exits 0" exited 0
  check "$repo creates pull requests" sent "$(put "$repo")" "$(permissions true)"
done

for repo in .github decisions probe-renovate; do
  BOT_APP_ID=42 run_org apply.sh "$repo"
  check "$repo exits 0" exited 0
  check "$repo creates no pull requests" \
    sent "$(put "$repo")" "$(permissions false)"
done

# The organization forbids the flag: GitHub answers 409 Conflict.
fixture_status PUT repos/fy/atom-x/actions/permissions/workflow "$http_conflict"
BOT_APP_ID=42 run_org apply.sh atom-x
check "forbidden: exits non-zero" not exited 0
check "forbidden: atom-x is not done" not_printed 'atom-x: done'

finish
