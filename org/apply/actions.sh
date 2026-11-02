# shellcheck shell=bash disable=SC2154 # globals of apply.sh
# Permissions of GITHUB_TOKEN in a repository, from
# repository/actions/workflow.json. Sourced by apply.sh, which sets org and
# here.

# creates_pull_requests REPO: whether workflows of REPO open pull requests
# with GITHUB_TOKEN. The release pull request of a released repository is
# opened that way.
creates_pull_requests() { is_released "$1"; }

# workflow_permissions CAN_APPROVE: print workflow.json with the flag that lets
# GITHUB_TOKEN create and approve pull requests set to CAN_APPROVE.
workflow_permissions() {
  local can_approve=$1
  jq --argjson can_approve "$can_approve" \
    '. + {can_approve_pull_request_reviews: $can_approve}' \
    "$here/repository/actions/workflow.json"
}

# The flag lets every workflow of the repository, and so anyone who can push a
# branch, make github-actions[bot] open and approve pull requests. It is
# therefore set only where a workflow needs it, and cleared everywhere else.
apply_actions() {
  local repo=$1 can_approve=false
  if creates_pull_requests "$repo"; then
    can_approve=true
  fi
  workflow_permissions "$can_approve" \
    | gh api --silent -X PUT "repos/$org/$repo/actions/permissions/workflow" \
      --input -
}
