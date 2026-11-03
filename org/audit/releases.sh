#!/usr/bin/env bash
# Audit the releases of the organization. Every release vX.Y.Z must be made by
# the release bot, and its tag must point to the merge commit of a release pull
# request: one from the branch release-please--branches--BASE, merged into BASE,
# which is main or release/vN, and labelled "autorelease: tagged" (FY-0007,
# FY-0030). A release that is not is reported, and the script then fails.
#
# Usage: releases.sh [repo...]
#   Without arguments, audits every non-archived repository of $ORG.
#
# Requires gh and jq. The repositories are public, so a read-only token is
# enough. $BOT_LOGIN is the login of the release bot, such as
# "flakeyard-bot[bot]". Mismatches are printed as workflow commands, so that
# GitHub Actions shows them as errors.
set -euo pipefail

org=${ORG:-flakeyard}
bot_login=${BOT_LOGIN:-}

readonly version_tag='^v[0-9]+\.[0-9]+\.[0-9]+$'

# A jq program that reads every pull request of a repository and prints one
# line for every reason why the commit $commit is not the merge commit of a
# release pull request. It prints nothing when one of the pull requests whose
# merge commit is $commit is a release pull request. An unmerged pull request
# has a merge commit too: the test merge of its head into its base.
# shellcheck disable=SC2016 # jq variables, not shell ones
readonly jq_release_problems='
  def release_branch: "release-please--branches--" + .base.ref;
  def maintained_base: .base.ref | test("^(main|release/v[1-9][0-9]*)$");
  def tagged: any(.labels[]; .name == "autorelease: tagged");
  def head_repository: .head.repo.full_name // "a deleted repository";

  def problems:
    "pull request #\(.number)" as $pr
    | (select(.merged_at == null) | "\($pr) is not merged"),
      (select(.head.ref != release_branch)
        | "\($pr) is from \(.head.ref), not \(release_branch)"),
      (select(head_repository != .base.repo.full_name)
        | "\($pr) is from \(head_repository)"),
      (select(maintained_base | not)
        | "\($pr) is merged into \(.base.ref), not main or release/vN"),
      (select(tagged | not) | "\($pr) is not labelled autorelease: tagged");

  map(select(.merge_commit_sha == $commit)) as $merged
  | if $merged == [] then
      "commit \($commit) is not the merge commit of a pull request"
    elif any($merged[]; [problems] == []) then empty
    else $merged[] | problems end
'

mismatches=0
releases_audited=0

die() {
  printf '%s\n' "$*" >&2
  exit 1
}

# escape_data TEXT: print TEXT escaped as the data of a workflow command, so
# that it cannot end the command or start another one.
escape_data() {
  local text=$1
  text=${text//'%'/%25}
  text=${text//$'\r'/%0D}
  text=${text//$'\n'/%0A}
  printf '%s' "$text"
}

# report REPO TAG PROBLEM: print PROBLEM of the release TAG of REPO as an error.
report() {
  local repo=$1 tag=$2 problem=$3
  printf '::error::%s\n' "$(escape_data "$repo $tag: $problem")"
  mismatches=$((mismatches + 1))
}

# repositories: print the name of every non-archived repository of $org.
repositories() {
  gh api --paginate "orgs/$org/repos?per_page=100" \
    --jq '.[] | select(.archived | not) | .name'
}

# releases REPO: print "tag<TAB>author" of every release of REPO.
releases() {
  local repo=$1
  gh api --paginate "repos/$org/$repo/releases?per_page=100" \
    --jq '.[] | [.tag_name, .author.login // "a deleted account"] | @tsv'
}

# pull_requests REPO FILE: store every pull request of REPO as one JSON list in
# FILE. A file, since the list can exceed the size of a command argument.
pull_requests() {
  local repo=$1 file=$2
  gh api --paginate "repos/$org/$repo/pulls?state=all&per_page=100" \
    | jq -s 'add // []' >"$file"
}

# tag_commit REPO TAG: print the commit that the tag TAG of REPO points to.
tag_commit() {
  local repo=$1 tag=$2
  gh api "repos/$org/$repo/commits/tags/$tag" --jq .sha
}

# release_problems COMMIT FILE: print why COMMIT is not the merge commit of a
# release pull request of the list FILE.
release_problems() {
  local commit=$1 file=$2
  jq -r --arg commit "$commit" "$jq_release_problems" "$file"
}

# report_each REPO TAG PROBLEMS: report every line of PROBLEMS.
report_each() {
  local repo=$1 tag=$2 problems=$3 problem
  while IFS= read -r problem; do
    [[ -n $problem ]] || continue
    report "$repo" "$tag" "$problem"
  done <<<"$problems"
}

# audit_release REPO TAG AUTHOR FILE: check the release TAG of REPO made by
# AUTHOR against the pull requests of FILE.
audit_release() {
  local repo=$1 tag=$2 author=$3 file=$4 commit problems
  releases_audited=$((releases_audited + 1))
  [[ $author == "$bot_login" ]] \
    || report "$repo" "$tag" "released by $author, not $bot_login"
  if ! commit=$(tag_commit "$repo" "$tag"); then
    report "$repo" "$tag" "cannot read the commit of the tag"
    return
  fi
  problems=$(release_problems "$commit" "$file")
  report_each "$repo" "$tag" "$problems"
}

# audit_repository REPO DIR: check every release vX.Y.Z of REPO, with DIR for
# temporary files.
audit_repository() {
  local repo=$1 dir=$2 list tag author file
  file=$dir/pulls.json
  list=$(releases "$repo")
  [[ -n $list ]] || return 0
  pull_requests "$repo" "$file"
  while IFS=$'\t' read -r tag author; do
    [[ $tag =~ $version_tag ]] || continue
    audit_release "$repo" "$tag" "$author" "$file"
  done <<<"$list"
}

for tool in gh jq; do
  command -v "$tool" >/dev/null || die "missing tool: $tool"
done
[[ -n $bot_login ]] || die "BOT_LOGIN is not set"

work=$(mktemp -d)
trap 'rm -rf -- "$work"' EXIT

repos=("$@")
if ((${#repos[@]} == 0)); then
  # Assigned separately so that a failing gh stops the script.
  all=$(repositories)
  [[ -n $all ]] || die "no repositories in $org"
  mapfile -t repos <<<"$all"
fi

for repo in "${repos[@]}"; do
  audit_repository "$repo" "$work"
done

printf '%d releases of %d repositories audited, %d mismatches\n' \
  "$releases_audited" "${#repos[@]}" "$mismatches"
((mismatches == 0))
