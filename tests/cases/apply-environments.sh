#!/usr/bin/env bash
# The environments "release", "publish" and "cache" of apply.sh: which
# repositories get them, their reviewers, their deployment branch policies,
# their secrets and the warning about other environments.
set -uo pipefail
# shellcheck source=tests/lib.sh
source "$(dirname -- "${BASH_SOURCE[0]}")/../lib.sh"

readonly owner='{"type":"User","id":264014534}'
readonly environments=repos/fy/atom-x/environments
readonly policies=$environments/release/deployment-branch-policies
readonly image_environments=repos/fy/image-w/environments
readonly publish_policies=$image_environments/publish/deployment-branch-policies

# put NAME [REPO]: the call that creates the environment NAME of REPO, atom-x
# by default.
put() {
  local name=$1 repo=${2:-atom-x}
  printf 'api --silent -X PUT repos/fy/%s/environments/%s --input -' \
    "$repo" "$name"
}

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

# apply_to NAME EXPECTED REPO [NAME=VALUE...]: run apply.sh on REPO with the
# bot app 42 and the variables given.
apply_to() {
  local name=$1 expected=$2 repo=$3
  shift 3
  run "$name" "$expected" org/apply.sh BOT_APP_ID=42 "$@" -- "$repo"
}

setup_org
fixture GET "$policies" <<'EOF_JSON'
{"branch_policies": [
  {"id": 1, "name": "main", "type": "branch"},
  {"id": 2, "name": "*", "type": "branch"},
  {"id": 3, "name": "release/v*", "type": "tag"}
]}
EOF_JSON
apply_to "atom-x" ok atom-x
expect message 'atom-x: done'
# release requires the owner, cache no reviewer.
expect_sent "$(put release)" "$(environment "[$owner]")"
expect_sent "$(put cache)" "$(environment '[]')"
# The policy main is kept, the policy * and the tag policy release/v* are
# deleted, and the branch policy release/v* is added.
expect no-call "$policies/1"
expect call "-X DELETE $policies/2"
expect call "-X DELETE $policies/3"
expect call "-X POST $policies -f name=release/v\\* -f type=branch"
finish

setup_org
apply_to "action-y gets only release" ok action-y
expect call repos/fy/action-y/environments/release
expect no-call repos/fy/action-y/environments/cache
expect no-call repos/fy/action-y/environments/publish
finish

# The checks of an image build the image, whose paths are not pushed.
setup_org
apply_to "image-w gets release and publish" ok image-w
expect call repos/fy/image-w/environments/release
expect no-call repos/fy/image-w/environments/cache
# publish requires the owner of release, and allows main and release/v*.
expect_sent "$(put publish image-w)" "$(environment "[$owner]")"
expect call "-X POST $publish_policies -f name=main -f type=branch"
expect call "-X POST $publish_policies -f name=release/v\\* -f type=branch"
finish

# Publication uses GITHUB_TOKEN, so the bot key stays in "release" only.
setup_org
printf 'key\n' >"$work/key.pem"
apply_to "image-w with the key" ok image-w BOT_PRIVATE_KEY_FILE="$work/key.pem"
expect call 'secret set APP_PRIVATE_KEY --repo fy/image-w --env release'
expect no-call '--env publish'
finish

setup_org
apply_to "template-v gets cache" ok template-v
expect call repos/fy/template-v/environments/cache
expect no-call repos/fy/template-v/environments/publish
finish

setup_org
apply_to "decisions gets no environment" ok decisions
expect no-call repos/fy/decisions/environments/
expect no-message 'warning:'
finish

setup_org
environments image-w release publish cache
apply_to "leftover cache" ok image-w
expect message 'warning: image-w: environments not in repository/environments/:'
expect message cache
expect no-call "-X DELETE repos/fy/image-w"
# release and publish are managed.
expect no-message release
expect no-message publish
expect message 'image-w: done'
finish

setup_org
environments decisions release
apply_to "unreleased" ok decisions
expect message release
expect call "--paginate repos/fy/decisions/environments\\?per_page=100"
expect no-call "-X PUT repos/fy/decisions/environments/"
finish

conclude
