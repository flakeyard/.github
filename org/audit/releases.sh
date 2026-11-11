#!/usr/bin/env bash
# Audit the releases of the organization. Every release vX.Y.Z must be made by
# the release bot, and its tag must point to the merge commit of a release pull
# request: one from the branch release-please--branches--BASE, merged into BASE,
# which is main or release/vN, titled "chore(BASE): release X.Y.Z" for its own
# version, labelled "autorelease: tagged" and merged by a reviewer of the
# environment release (FY-0007, FY-0030, FY-0033). No two releases may share a
# commit. A release that is not is reported, and the script then fails.
#
# Usage: releases.sh [repo...]
#   Without arguments, audits every non-archived repository of $ORG.
#
# Requires gh and jq. The repositories are public, so a read-only token is
# enough. $BOT_LOGIN is the login of the release bot, such as
# "flakeyard-bot[bot]". Mismatches are printed as workflow commands, so that
# GitHub Actions shows them as errors.
# shellcheck source-path=SCRIPTDIR/..
set -euo pipefail

here=$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)
# shellcheck source=lib.sh
source "$here/../lib.sh"

bot_login=${BOT_LOGIN:-}
readonly reviewers_file=$here/../repository/environments/release-reviewers.json

readonly version_tag='^v[0-9]+\.[0-9]+\.[0-9]+$'

# The definitions of a release pull request of the release $tag, shared by the
# jq programs below.
# shellcheck disable=SC2016 # jq variables, not shell ones
readonly jq_release_definitions='
  def release_branch: "release-please--branches--" + .base.ref;
  def maintained_base: .base.ref | test("^(main|release/v[1-9][0-9]*)$");
  def tagged: any(.labels[]; .name == "autorelease: tagged");
  def head_repository: .head.repo.full_name // "a deleted repository";
  # The title that release-please gives the release pull request of $tag.
  def release_title: "chore(\(.base.ref)): release \($tag | ltrimstr("v"))";

  def problems:
    "pull request #\(.number)" as $pr
    | (select(.merged_at == null) | "\($pr) is not merged"),
      (select(.head.ref != release_branch)
        | "\($pr) is from \(.head.ref), not \(release_branch)"),
      (select(head_repository != .base.repo.full_name)
        | "\($pr) is from \(head_repository)"),
      (select(maintained_base | not)
        | "\($pr) is merged into \(.base.ref), not main or release/vN"),
      (select(tagged | not) | "\($pr) is not labelled autorelease: tagged"),
      (select(.title != release_title)
        | "\($pr) is titled \(.title), not \(release_title)");

  def has_merge_commit($commit): .merge_commit_sha == $commit;
  # A release pull request is one without problems.
  def release_pull_request: [problems] == [];
'

# A jq program that reads every pull request of a repository and prints one
# line for every reason why the commit $commit is not the merge commit of a
# release pull request. It prints nothing when one of the pull requests whose
# merge commit is $commit is a release pull request. An unmerged pull request
# has a merge commit too: the test merge of its head into its base.
# shellcheck disable=SC2016 # jq variables, not shell ones
readonly jq_release_problems="$jq_release_definitions"'
  map(select(has_merge_commit($commit))) as $merged
  | if $merged == [] then
      "commit \($commit) is not the merge commit of a pull request"
    elif any($merged[]; release_pull_request) then empty
    else $merged[] | problems end
'

# A jq program that prints the number of the release pull request, from the
# same list, whose merge commit is $commit.
# shellcheck disable=SC2016 # jq variables, not shell ones
readonly jq_release_number="$jq_release_definitions"'
  first(.[] | select(has_merge_commit($commit) and release_pull_request))
  | .number
'

mismatches=0
releases_audited=0
# The release of each commit audited in the current repository.
declare -A release_of_commit=()

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
  api_list "repos/$org/$repo/pulls?state=all&per_page=100" '.[]' >"$file"
}

# tag_commit REPO TAG: print the commit that the tag TAG of REPO points to.
tag_commit() {
  local repo=$1 tag=$2
  gh api "repos/$org/$repo/commits/tags/$tag" --jq .sha
}

# release_problems TAG COMMIT FILE: print why COMMIT is not the merge commit of
# a release pull request of TAG in the list FILE.
release_problems() {
  local tag=$1 commit=$2 file=$3
  jq -r --arg tag "$tag" --arg commit "$commit" "$jq_release_problems" "$file"
}

# release_number TAG COMMIT FILE: print the number of the release pull request
# of TAG in the list FILE whose merge commit is COMMIT.
release_number() {
  local tag=$1 commit=$2 file=$3
  jq -r --arg tag "$tag" --arg commit "$commit" "$jq_release_number" "$file"
}

# merger REPO NUMBER: print the login of whoever merged the pull request NUMBER
# of REPO. The list of pull requests does not carry it.
merger() {
  local repo=$1 number=$2
  gh api "repos/$org/$repo/pulls/$number" --jq '.merged_by.login // "nobody"'
}

# is_release_reviewer LOGIN: whether LOGIN reviews the environment release.
is_release_reviewer() {
  local login=$1
  jq -e --arg login "$login" \
    'any(.[]; .type == "User" and .login == $login)' "$reviewers_file" >/dev/null
}

# audit_merger REPO TAG COMMIT FILE: report the release pull request of COMMIT
# unless a reviewer of the environment release merged it.
audit_merger() {
  local repo=$1 tag=$2 commit=$3 file=$4 number login
  number=$(release_number "$tag" "$commit" "$file")
  if ! login=$(merger "$repo" "$number"); then
    report "$repo" "$tag" "cannot read who merged pull request #$number"
    return
  fi
  is_release_reviewer "$login" \
    || report "$repo" "$tag" "pull request #$number is merged by $login, not by a reviewer of release"
}

# report_each REPO TAG PROBLEMS: report every line of PROBLEMS.
report_each() {
  local repo=$1 tag=$2 problems=$3 problem
  while IFS= read -r problem; do
    [[ -n $problem ]] || continue
    report "$repo" "$tag" "$problem"
  done <<<"$problems"
}

# audit_shared_commit REPO TAG COMMIT: report the release TAG of REPO when an
# earlier release of REPO has its commit COMMIT, or else remember it.
audit_shared_commit() {
  local repo=$1 tag=$2 commit=$3 other
  other=${release_of_commit[$commit]-}
  if [[ -n $other ]]; then
    report "$repo" "$tag" "commit $commit is the commit of $other too"
  else
    release_of_commit[$commit]=$tag
  fi
}

# audit_commit REPO TAG COMMIT FILE: check that COMMIT, of the release TAG of
# REPO, is the merge commit of a release pull request of TAG in FILE.
audit_commit() {
  local repo=$1 tag=$2 commit=$3 file=$4 problems
  problems=$(release_problems "$tag" "$commit" "$file")
  if [[ -n $problems ]]; then
    report_each "$repo" "$tag" "$problems"
  else
    audit_merger "$repo" "$tag" "$commit" "$file"
  fi
}

# audit_release REPO TAG AUTHOR FILE: check the release TAG of REPO made by
# AUTHOR against the pull requests of FILE.
audit_release() {
  local repo=$1 tag=$2 author=$3 file=$4 commit
  releases_audited=$((releases_audited + 1))
  [[ $author == "$bot_login" ]] \
    || report "$repo" "$tag" "released by $author, not $bot_login"
  if ! commit=$(tag_commit "$repo" "$tag"); then
    report "$repo" "$tag" "cannot read the commit of the tag"
    return
  fi
  audit_shared_commit "$repo" "$tag" "$commit"
  audit_commit "$repo" "$tag" "$commit" "$file"
}

# audit_repository REPO DIR: check every release vX.Y.Z of REPO, with DIR for
# temporary files.
audit_repository() {
  local repo=$1 dir=$2 list tag author file
  file=$dir/pulls.json
  release_of_commit=()
  list=$(releases "$repo")
  [[ -n $list ]] || return 0
  pull_requests "$repo" "$file"
  while IFS=$'\t' read -r tag author; do
    [[ $tag =~ $version_tag ]] || continue
    audit_release "$repo" "$tag" "$author" "$file"
  done <<<"$list"
}

[[ -n $bot_login ]] || die "BOT_LOGIN is not set"
[[ -r $reviewers_file ]] || die "cannot read $reviewers_file"

work=$(mktemp -d)
trap 'rm -rf -- "$work"' EXIT

select_repositories "$@"

for repo in "${repos[@]}"; do
  audit_repository "$repo" "$work"
done

printf '%d releases of %d repositories audited, %d mismatches\n' \
  "$releases_audited" "${#repos[@]}" "$mismatches"
((mismatches == 0))
