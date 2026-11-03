#!/usr/bin/env bash
# The environments "release" and "cache" of apply.sh: which repositories get
# them, their reviewers, their deployment branch policies and the warning about
# other environments.
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
check "decisions: no warning" not_printed 'warning:'

# environments REPO NAME...: answer the listing of environments of REPO with
# the environments NAME.
environments() {
  local repo=$1 name
  shift
  for name; do
    jq -n --arg name "$name" '{id: 1, name: $name}'
  done | jq -s '{total_count: length, environments: .}' \
    | fixture GET "repos/fy/$repo/environments"
}

environments image-w release cache
BOT_APP_ID=42 run_org apply.sh image-w
check "leftover cache: exits 0" exited 0
check "leftover cache: warns" \
  printed 'warning: image-w: environments not in repository/environments/:'
check "leftover cache: names it" printed cache
check "leftover cache: keeps it" not_called "-X DELETE repos/fy/image-w"
check "leftover cache: release is managed" not_printed release
check "leftover cache: is applied" printed 'image-w: done'

environments decisions release
BOT_APP_ID=42 run_org apply.sh decisions
check "unreleased: warns about release" printed release
check "unreleased: paginates" \
  called "--paginate repos/fy/decisions/environments\\?per_page=100"
check "unreleased: creates none" \
  not_called "-X PUT repos/fy/decisions/environments/"

finish
