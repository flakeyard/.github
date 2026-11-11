#!/usr/bin/env bash
# The release audit: releases by another author, tags that do not point to the
# merge commit of a merged release pull request of their version, releases that
# share a commit, pagination and the escaping of workflow commands.
set -uo pipefail
# shellcheck source=tests/lib.sh
source "$(dirname -- "${BASH_SOURCE[0]}")/../lib.sh"

readonly bot='bot[bot]'
readonly from_main=release-please--branches--main
readonly tagged='autorelease: tagged'
# The reviewer of the environment release in repository/environments/.
owner=$(jq -r '.[0].login' "$root/org/repository/environments/release-reviewers.json")
readonly owner

# audit NAME EXPECTED REPO...: run the audit of REPO with the release bot
# $bot.
audit() {
  local name=$1 expected=$2
  shift 2
  run "$name" "$expected" org/audit/releases.sh BOT_LOGIN="$bot" -- "$@"
}

# releases REPO PAGE TAG=AUTHOR...: answer the page PAGE of the releases of
# REPO.
releases() {
  local repo=$1 page=$2 pair
  shift 2
  for pair; do
    jq -n --arg tag "${pair%%=*}" --arg login "${pair#*=}" \
      '{tag_name: $tag, author: {login: $login}}'
  done | jq -s . | fixture_page "repos/fy/$repo/releases?per_page=100" "$page"
}

# tag REPO TAG COMMIT: make the tag TAG of REPO point to COMMIT.
tag() {
  local repo=$1 tag=$2 commit=$3
  fixture "repos/fy/$repo/commits/tags/$tag" "$(jq -n --arg sha "$commit" '{sha: $sha}')"
}

# pull NUMBER VERSION COMMIT HEAD BASE LABEL [MERGED]: print the pull request
# of the release VERSION merged into BASE as COMMIT, unless MERGED is
# "unmerged". The title restates the one of release-please as an independent
# oracle.
pull() {
  local number=$1 version=$2 commit=$3 head=$4 base=$5 label=$6 merged=${7:-merged}
  jq -n --argjson number "$number" --arg version "$version" \
    --arg commit "$commit" --arg head "$head" --arg base "$base" \
    --arg label "$label" --arg merged "$merged" '{
      number: $number,
      title: "chore(\($base)): release \($version)",
      merge_commit_sha: $commit,
      merged_at: (if $merged == "merged" then "2026-11-01T00:00:00Z"
        else null end),
      head: {ref: $head, repo: {full_name: "fy/atom-x"}},
      base: {ref: $base, repo: {full_name: "fy/atom-x"}},
      labels: [{name: $label}]
    }'
}

# pulls REPO PAGE: answer the page PAGE of the pull requests of REPO with the
# pull requests on stdin, and each pull request on its own, merged by
# .merged_by.login or else by $owner. Like the API, the list has no merged_by.
pulls() {
  local repo=$1 page=$2 list number
  list=$(jq -s .)
  jq 'map(del(.merged_by))' <<<"$list" \
    | fixture_page "repos/fy/$repo/pulls?state=all&per_page=100" "$page"
  for number in $(jq -r '.[].number' <<<"$list"); do
    fixture "repos/fy/$repo/pulls/$number" "$(jq --argjson n "$number" \
      --arg owner "$owner" '.[] | select(.number == $n)
        | .merged_by //= {login: $owner}' <<<"$list")"
  done
}

# A release made as FY-0007 says.
setup_org
releases atom-x 1 "v1.0.0=$bot" "nightly=someone"
tag atom-x v1.0.0 c1
pull 1 1.0.0 c1 "$from_main" main "$tagged" | pulls atom-x 1
audit "release" ok atom-x
expect no-message '::error::'
expect call "GET repos/fy/atom-x/releases?per_page=100"
# Every pull request is listed; the tag, not a branch, is read, and other tags
# are skipped.
expect call "GET repos/fy/atom-x/pulls?state=all&per_page=100"
expect call "repos/fy/atom-x/commits/tags/v1.0.0"
expect no-call commits/tags/nightly
# Who merged it is read.
expect call repos/fy/atom-x/pulls/1
expect message '1 releases of 1 repositories audited, 0 mismatches'
finish

# A tag moved to a commit that no release pull request merged.
setup_org
releases atom-x 1 "v1.0.0=$bot" "v1.0.1=$bot"
tag atom-x v1.0.0 c2
tag atom-x v1.0.1 c9
pull 2 1.0.0 c2 feat/x main "$tagged" | pulls atom-x 1
audit "forged tag" fail atom-x
expect message "::error::atom-x v1.0.0: pull request #2 is from feat/x, not $from_main"
expect message '::error::atom-x v1.0.1: commit c9 is not the merge commit of a pull'
expect message '2 releases of 1 repositories audited, 2'
finish

# A release pull request merged with the key of the bot, not by its reviewer.
setup_org
releases atom-x 1 "v1.0.0=$bot"
tag atom-x v1.0.0 c1
pull 1 1.0.0 c1 "$from_main" main "$tagged" \
  | jq --arg bot "$bot" '.merged_by = {login: $bot}' | pulls atom-x 1
audit "merged by the bot" fail atom-x
expect message "::error::atom-x v1.0.0: pull request #1 is merged by $bot, not by a reviewer of release"
expect call repos/fy/atom-x/pulls/1
finish

# Who merged a release pull request cannot be read.
setup_org
releases atom-x 1 "v1.0.0=$bot"
tag atom-x v1.0.0 c1
pull 1 1.0.0 c1 "$from_main" main "$tagged" | pulls atom-x 1
apply FAIL_ON="GET repos/fy/atom-x/pulls/1 502"
audit "merger unknown" fail atom-x
expect message '::error::atom-x v1.0.0: cannot read who merged pull request #1'
finish

# A release made by someone else than the bot.
setup_org
releases atom-x 1 "v1.0.0=mallory"
tag atom-x v1.0.0 c1
pull 1 1.0.0 c1 "$from_main" main "$tagged" | pulls atom-x 1
audit "other author" fail atom-x
expect message "::error::atom-x v1.0.0: released by mallory, not $bot"
# The commit is fine.
expect no-message 'pull request'
finish

# The test merge commit of an open release pull request.
setup_org
releases atom-x 1 "v1.0.0=$bot"
tag atom-x v1.0.0 c3
pull 3 1.0.0 c3 "$from_main" main "$tagged" unmerged | pulls atom-x 1
audit "unmerged" fail atom-x
expect message '::error::atom-x v1.0.0: pull request #3 is not merged'
finish

# Bases, labels and forks.
setup_org
releases atom-x 1 "v1.0.0=$bot" "v0.1.0=$bot" "v1.1.0=$bot" "v1.2.0=$bot"
tag atom-x v1.0.0 c4
tag atom-x v0.1.0 c5
tag atom-x v1.1.0 c6
tag atom-x v1.2.0 c7
{
  pull 4 1.0.0 c4 release-please--branches--release/v1 release/v1 "$tagged"
  pull 5 0.1.0 c5 release-please--branches--release/v0 release/v0 "$tagged"
  pull 6 1.1.0 c6 "$from_main" main 'autorelease: pending'
  pull 7 1.2.0 c7 "$from_main" main "$tagged" \
    | jq '.head.repo.full_name = "mallory/atom-x"'
} | pulls atom-x 1
audit "bases" fail atom-x
# release/v1 is fine; release/v0 is not maintained; the label is required; a
# fork is reported.
expect no-message 'atom-x v1.0.0'
expect message 'pull request #5 is merged into release/v0, not main or release/vN'
expect message 'pull request #6 is not labelled autorelease: tagged'
expect message 'pull request #7 is from mallory/atom-x'
finish

# A forged release whose tag points to the merge commit of the release pull
# request of another version, and so shares its commit.
setup_org
releases atom-x 1 "v9.9.9=$bot" "v1.0.0=$bot"
tag atom-x v1.0.0 c1
tag atom-x v9.9.9 c1
pull 1 1.0.0 c1 "$from_main" main "$tagged" | pulls atom-x 1
audit "other version" fail atom-x
expect message '::error::atom-x v9.9.9: pull request #1 is titled chore(main): release 1.0.0, not chore(main): release 9.9.9'
expect message '::error::atom-x v1.0.0: commit c1 is the commit of v9.9.9 too'
expect no-message 'atom-x v1.0.0: pull request'
expect message '2 releases of 1 repositories audited, 2 mismatches'
finish

# Two releases on the merge commit of a release pull request of each, as if
# one commit was merged twice.
setup_org
releases atom-x 1 "v1.0.1=$bot" "v1.0.0=$bot"
tag atom-x v1.0.0 c1
tag atom-x v1.0.1 c1
{
  pull 1 1.0.0 c1 "$from_main" main "$tagged"
  pull 2 1.0.1 c1 "$from_main" main "$tagged"
} | pulls atom-x 1
audit "shared commit" fail atom-x
expect message '::error::atom-x v1.0.0: commit c1 is the commit of v1.0.1 too'
expect no-message 'atom-x v1.0.1'
expect message '2 releases of 1 repositories audited, 1 mismatches'
finish

# Every page of releases and pull requests. The repositories are listed by
# lib.sh, tested in repositories.sh.
setup_org
releases atom-x 1 "v1.0.0=$bot"
releases atom-x 2 "v1.1.0=$bot"
tag atom-x v1.0.0 c1
tag atom-x v1.1.0 c8
pull 1 1.0.0 c1 "$from_main" main "$tagged" | pulls atom-x 1
pull 8 1.1.0 c8 "$from_main" main "$tagged" | pulls atom-x 2
audit "pages" ok atom-x atom-y
# atom-y has no releases, so no pull requests are listed.
expect no-call repos/fy/atom-y/pulls
expect call commits/tags/v1.1.0
expect message '2 releases of 2 repositories audited, 0 mismatches'
finish

# Text from the API cannot start another workflow command.
setup_org
releases atom-x 1 'v1.0.0=evil%0A::warning::x'
tag atom-x v1.0.0 c1
pull 1 1.0.0 c1 "$from_main" main "$tagged" | pulls atom-x 1
audit "escaped" fail atom-x
expect message 'released by evil%250A::warning::x'
finish

# A tag that cannot be read.
setup_org
releases atom-x 1 "v1.0.0=$bot"
apply FAIL_ON="GET repos/fy/atom-x/commits/tags/v1.0.0 404"
pull 1 1.0.0 c1 "$from_main" main "$tagged" | pulls atom-x 1
audit "no tag" fail atom-x
expect message '::error::atom-x v1.0.0: cannot read the commit of the tag'
finish

setup_org
apply FAIL_ON="GET repos/fy/atom-x/releases?per_page=100 500"
audit "listing fails" fail atom-x
expect no-message 'audited'
finish

setup_org
run "no bot" fail org/audit/releases.sh -- atom-x
expect message 'BOT_LOGIN is not set'
finish

conclude
