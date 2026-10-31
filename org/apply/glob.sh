# shellcheck shell=bash disable=SC2154 # globals of apply.sh
# Globs of repository names in the JSON files of org/repository. Sourced by
# apply.sh, which sets here.

# A jq function that turns a glob of repository names into a regex; only "*"
# is special.
readonly jq_glob='def glob: "^" + (gsub("\\."; "\\.") | gsub("\\*"; ".*")) + "$";'

# matches_glob FILE REPO: whether REPO matches a glob of the JSON list FILE
# under org/repository.
matches_glob() {
  local file=$1 repo=$2 status=0
  jq -e --arg repo "$repo" "$jq_glob"'
    any(.[]; glob as $re | $repo | test($re))
  ' "$here/repository/$file" >/dev/null || status=$?
  # jq -e exits with 1 for false and above 1 for errors.
  ((status <= 1)) || die "cannot read $file"
  ((status == 0))
}
