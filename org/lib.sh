# shellcheck shell=bash
# Helpers of apply.sh, settings.sh and audit/releases.sh, which source this
# file first. Sourcing it checks that gh and jq are installed.

org=${ORG:-flakeyard}

die() {
  printf '%s\n' "$*" >&2
  exit 1
}

for tool in gh jq; do
  command -v "$tool" >/dev/null || die "missing tool: $tool"
done

# api_list PATH FILTER: print the items that FILTER picks from every page of
# the API path PATH as one JSON list. FILTER must pick objects or lists: gh
# prints strings without quotes.
api_list() {
  local path=$1 filter=$2
  gh api --paginate "$path" --jq "$filter" | jq -s .
}

# repositories: print the name of every non-archived repository of $org.
repositories() {
  gh api --paginate "orgs/$org/repos?per_page=100" \
    --jq '.[] | select(.archived | not) | .name'
}

# select_repositories REPO...: set repos to REPO..., or to every non-archived
# repository of $org when no REPO is given.
select_repositories() {
  local all
  repos=("$@")
  ((${#repos[@]} == 0)) || return 0
  # Assigned separately so that a failing gh stops the script.
  all=$(repositories)
  [[ -n $all ]] || die "no repositories in $org"
  mapfile -t repos <<<"$all"
}
