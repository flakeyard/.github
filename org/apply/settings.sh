# shellcheck shell=bash disable=SC2154 # globals of apply.sh
# Settings of a repository, from repository/settings.json. Sourced by apply.sh,
# which sets org and here.

apply_settings() {
  local repo=$1
  gh api --silent -X PATCH "repos/$org/$repo" \
    --input "$here/repository/settings.json"
  # Discussions of the .github repository are the discussions of the whole
  # organization.
  if [[ $repo == .github ]]; then
    gh api --silent -X PATCH "repos/$org/$repo" -F has_discussions=true
  fi
}
