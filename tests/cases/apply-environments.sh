#!/usr/bin/env bash
# The environments "release" and "cache" of apply.sh: which repositories get
# them, their reviewers and their deployment branch policies.
set -uo pipefail
# shellcheck source=tests/lib.sh
source "$(dirname -- "${BASH_SOURCE[0]}")/../lib.sh"

readonly owner='{"type":"User","id":264014534}'
readonly environments=repos/fy/atom-x/environments
readonly policies=$environments/release/deployment-branch-policies

# put NAME: the call that creates the environment NAME of atom-x.
put() { printf 'api --silent -X PUT %s/%s --input -' "$environments" "$1"; }

# environment REVIEWERS: the body that creates a deploy environment.
environment() {
  local reviewers=$1
  jq -cn --argjson reviewers "$reviewers" '{
    reviewers: $reviewers,
    prevent_self_review: false,
    can_admins_bypass: false,
    deployment_branch_policy:
      {protected_branches: false, custom_branch_policies: true}
  }'
}

fixture GET "$policies" <<'EOF_JSON'
{"branch_policies": [
  {"id": 1, "name": "main", "type": "branch"},
  {"id": 2, "name": "*", "type": "branch"},
  {"id": 3, "name": "release/v*", "type": "tag"}
]}
EOF_JSON

BOT_APP_ID=42 run_org apply.sh atom-x
check "atom-x exits 0" exited 0
check "atom-x is applied" printed 'atom-x: done'
check "release requires the owner" \
  sent "$(put release)" "$(environment "[$owner]")"
check "cache requires no reviewer" sent "$(put cache)" "$(environment '[]')"
check "keeps the policy main" not_called "$policies/1"
check "deletes the policy *" called "-X DELETE $policies/2"
check "deletes the tag policy release/v*" called "-X DELETE $policies/3"
check "adds the branch policy release/v*" \
  called "-X POST $policies -f name=release/v\\* -f type=branch"

BOT_APP_ID=42 run_org apply.sh action-y
check "action-y gets release" called repos/fy/action-y/environments/release
check "action-y gets no cache" not_called repos/fy/action-y/environments/cache

# The checks of an image build the image, whose paths are not pushed.
BOT_APP_ID=42 run_org apply.sh image-w
check "image-w gets release" called repos/fy/image-w/environments/release
check "image-w gets no cache" not_called repos/fy/image-w/environments/cache

BOT_APP_ID=42 run_org apply.sh template-v
check "template-v gets cache" called repos/fy/template-v/environments/cache

BOT_APP_ID=42 run_org apply.sh decisions
check "decisions gets no environment" \
  not_called repos/fy/decisions/environments/

finish
