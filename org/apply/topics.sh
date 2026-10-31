# shellcheck shell=bash disable=SC2154 # globals of apply.sh
# Topics of a repository, from repository/topics.json, matched with glob.sh.
# Sourced by apply.sh, which sets org and here.

apply_topics() {
  local repo=$1
  # Keys of topics.json are globs. Topics that are not listed there are drift
  # and are removed.
  jq --arg repo "$repo" "$jq_glob"'
    {names: ([to_entries[]
      | select(.key as $k | $repo | test($k | glob)) | .value[]] | unique)}
  ' "$here/repository/topics.json" \
    | gh api --silent -X PUT "repos/$org/$repo/topics" --input -
}
