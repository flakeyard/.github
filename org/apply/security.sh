# shellcheck shell=bash disable=SC2154 # globals of apply.sh
# Security features of a repository. Sourced by apply.sh, which sets org.

# Status codes of GitHub API responses.
readonly http_ok=200 http_conflict=409

has_commits() {
  local repo=$1 status
  status=$(http_status "repos/$org/$repo/commits?per_page=1")
  case $status in
    "$http_ok") return 0 ;;
    # An empty repository answers 409 Conflict.
    "$http_conflict") return 1 ;;
    *) die "cannot list commits of $repo: HTTP ${status:-no response}" ;;
  esac
}

# CodeQL default setup conflicts with an own CodeQL workflow, so it is
# enabled only for atoms and actions.
wants_default_code_scanning() {
  local repo=$1
  [[ $repo == atom-* || $repo == action-* ]]
}

apply_security() {
  local repo=$1
  gh api --silent -X PUT "repos/$org/$repo/vulnerability-alerts"
  gh api --silent -X PUT "repos/$org/$repo/private-vulnerability-reporting"
  gh api --silent -X PUT "repos/$org/$repo/immutable-releases"
  # Default setup needs a commit to scan.
  if wants_default_code_scanning "$repo" && has_commits "$repo"; then
    gh api --silent -X PATCH "repos/$org/$repo/code-scanning/default-setup" \
      -f state=configured
  fi
}
