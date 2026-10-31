# shellcheck shell=bash
# Status codes of GitHub API responses. Sourced by apply.sh.

# http_status PATH: print the HTTP status code of a GET request to PATH.
http_status() {
  local path=$1 response
  # gh fails on any status but 2xx; the status line is printed anyway.
  response=$(gh api -i "$path" 2>/dev/null) || true
  awk 'NR == 1 { print $2 }' <<<"$response"
}
