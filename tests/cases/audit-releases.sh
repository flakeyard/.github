#!/usr/bin/env bash
# The release audit: releases by another author, tags that do not point to the
# merge commit of a merged release pull request, pagination and the escaping
# of workflow commands.
set -uo pipefail
# shellcheck source=tests/lib.sh
source "$(dirname -- "${BASH_SOURCE[0]}")/../lib.sh"

readonly bot='bot[bot]'
readonly from_main=release-please--branches--main
readonly tagged='autorelease: tagged'

# audit REPO...: run the audit with the release bot $bot.
audit() { BOT_LOGIN=$bot run_org audit/releases.sh "$@"; }

# releases REPO PAGE TAG=AUTHOR...: answer the page PAGE (1 or more) of the
# releases of REPO.
releases() {
  local repo=$1 page=$2 pair suffix=''
  shift 2
  ((page > 1)) && suffix=.$page
  for pair; do
    jq -n --arg tag "${pair%%=*}" --arg login "${pair#*=}" \
      '{tag_name: $tag, author: {login: $login}}'
  done | jq -s . | fixture GET "repos/fy/$repo/releases$suffix"
}

# tag REPO TAG COMMIT: make the tag TAG of REPO point to COMMIT.
tag() {
  local repo=$1 tag=$2 commit=$3
  jq -n --arg sha "$commit" '{sha: $sha}' \
    | fixture GET "repos/fy/$repo/commits/tags/$tag"
}

# pull NUMBER COMMIT HEAD BASE LABEL [MERGED]: print a pull request merged
# into BASE as COMMIT, unless MERGED is "unmerged".
pull() {
  local number=$1 commit=$2 head=$3 base=$4 label=$5 merged=${6:-merged}
  jq -n --argjson number "$number" --arg commit "$commit" --arg head "$head" \
    --arg base "$base" --arg label "$label" --arg merged "$merged" '{
      number: $number,
      merge_commit_sha: $commit,
      merged_at: (if $merged == "merged" then "2026-11-01T00:00:00Z"
        else null end),
      head: {ref: $head, repo: {full_name: "fy/atom-x"}},
      base: {ref: $base, repo: {full_name: "fy/atom-x"}},
      labels: [{name: $label}]
    }'
}

# pulls REPO PAGE: answer the page PAGE of the pull requests of REPO with the
# pull requests on stdin.
pulls() {
  local repo=$1 page=$2 suffix=''
  ((page > 1)) && suffix=.$page
  jq -s . | fixture GET "repos/fy/$repo/pulls$suffix"
}

# A release made as FY-0007 says.
releases atom-x 1 "v1.0.0=$bot" "nightly=someone"
tag atom-x v1.0.0 c1
pull 1 c1 "$from_main" main "$tagged" | pulls atom-x 1
audit atom-x
check "release: exits 0" exited 0
check "release: reports nothing" not_printed '::error::'
check "release: paginates releases" \
  called "--paginate repos/fy/atom-x/releases\\?per_page=100"
check "release: lists every pull request" \
  called "--paginate repos/fy/atom-x/pulls\\?state=all\\&per_page=100"
check "release: reads the tag, not a branch" \
  called "repos/fy/atom-x/commits/tags/v1.0.0"
check "release: skips other tags" not_called commits/tags/nightly
check "release: summary" \
  printed '1 releases of 1 repositories audited, 0 mismatches'
clear_fixtures

# A tag moved to a commit that no release pull request merged.
releases atom-x 1 "v1.0.0=$bot" "v1.0.1=$bot"
tag atom-x v1.0.0 c2
tag atom-x v1.0.1 c9
pull 2 c2 feat/x main "$tagged" | pulls atom-x 1
audit atom-x
check "forged tag: exits 1" exited 1
check "forged tag: other head" \
  printed "::error::atom-x v1.0.0: pull request #2 is from feat/x, not $from_main"
check "forged tag: no pull request" \
  printed '::error::atom-x v1.0.1: commit c9 is not the merge commit of a pull'
check "forged tag: summary" printed '2 releases of 1 repositories audited, 2'
clear_fixtures

# A release made by someone else than the bot.
releases atom-x 1 "v1.0.0=mallory"
tag atom-x v1.0.0 c1
pull 1 c1 "$from_main" main "$tagged" | pulls atom-x 1
audit atom-x
check "other author: exits 1" exited 1
check "other author: reported" \
  printed "::error::atom-x v1.0.0: released by mallory, not $bot"
check "other author: the commit is fine" not_printed 'pull request'
clear_fixtures

# The test merge commit of an open release pull request.
releases atom-x 1 "v1.0.0=$bot"
tag atom-x v1.0.0 c3
pull 3 c3 "$from_main" main "$tagged" unmerged | pulls atom-x 1
audit atom-x
check "unmerged: exits 1" exited 1
check "unmerged: reported" \
  printed '::error::atom-x v1.0.0: pull request #3 is not merged'
clear_fixtures

# Bases, labels and forks.
releases atom-x 1 "v1.0.0=$bot" "v0.1.0=$bot" "v1.1.0=$bot" "v1.2.0=$bot"
tag atom-x v1.0.0 c4
tag atom-x v0.1.0 c5
tag atom-x v1.1.0 c6
tag atom-x v1.2.0 c7
{
  pull 4 c4 release-please--branches--release/v1 release/v1 "$tagged"
  pull 5 c5 release-please--branches--release/v0 release/v0 "$tagged"
  pull 6 c6 "$from_main" main 'autorelease: pending'
  pull 7 c7 "$from_main" main "$tagged" \
    | jq '.head.repo.full_name = "mallory/atom-x"'
} | pulls atom-x 1
audit atom-x
check "bases: exits 1" exited 1
check "bases: release/v1 is fine" not_printed 'atom-x v1.0.0'
check "bases: release/v0 is not maintained" \
  printed 'pull request #5 is merged into release/v0, not main or release/vN'
check "bases: the label is required" \
  printed 'pull request #6 is not labelled autorelease: tagged'
check "bases: a fork is reported" \
  printed 'pull request #7 is from mallory/atom-x'
clear_fixtures

# Every page of repositories, releases and pull requests.
jq -n '[{name: "atom-x", archived: false}, {name: "old", archived: true}]' \
  | fixture GET orgs/fy/repos
jq -n '[{name: "atom-y", archived: false}]' | fixture GET orgs/fy/repos.2
releases atom-x 1 "v1.0.0=$bot"
releases atom-x 2 "v1.1.0=$bot"
tag atom-x v1.0.0 c1
tag atom-x v1.1.0 c8
pull 1 c1 "$from_main" main "$tagged" | pulls atom-x 1
pull 8 c8 "$from_main" main "$tagged" | pulls atom-x 2
audit
check "pages: exits 0" exited 0
check "pages: paginates repositories" \
  called "--paginate orgs/fy/repos\\?per_page=100"
check "pages: skips archived repositories" not_called repos/fy/old/
check "pages: audits the second page of repositories" \
  called repos/fy/atom-y/releases
check "pages: no releases, no pull requests" not_called repos/fy/atom-y/pulls
check "pages: the release of the second page" called commits/tags/v1.1.0
check "pages: summary" \
  printed '2 releases of 2 repositories audited, 0 mismatches'
clear_fixtures

# Text from the API cannot start another workflow command.
releases atom-x 1 'v1.0.0=evil%0A::warning::x'
tag atom-x v1.0.0 c1
pull 1 c1 "$from_main" main "$tagged" | pulls atom-x 1
audit atom-x
check "escaped: exits 1" exited 1
check "escaped: percent sign" printed 'released by evil%250A::warning::x'
clear_fixtures

# A tag that cannot be read.
releases atom-x 1 "v1.0.0=$bot"
fixture_status GET repos/fy/atom-x/commits/tags/v1.0.0 404
pull 1 c1 "$from_main" main "$tagged" | pulls atom-x 1
audit atom-x
check "no tag: exits 1" exited 1
check "no tag: reported" \
  printed '::error::atom-x v1.0.0: cannot read the commit of the tag'
clear_fixtures

fixture_status GET repos/fy/atom-x/releases 500
audit atom-x
check "listing fails: exits non-zero" not exited 0
check "listing fails: no summary" not_printed 'audited'
clear_fixtures

run_org audit/releases.sh atom-x
check "no bot: exits 1" exited 1
check "no bot: says so" printed 'BOT_LOGIN is not set'

finish
