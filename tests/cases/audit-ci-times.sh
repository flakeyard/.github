#!/usr/bin/env bash
# The report of CI times: the CI workflow, the window of runs, pagination,
# the numbers by event, by job and by pull request branch, and failures.
set -uo pipefail
# shellcheck source=tests/lib.sh
source "$(dirname -- "${BASH_SOURCE[0]}")/../lib.sh"

# The time the tests take as now, and the day 14 days before it.
readonly now=2026-11-12T12:00:00Z
readonly default_since=2026-10-29
readonly workflows='repos/fy/atom-x/actions/workflows?per_page=100'
readonly ci_id=7

# times NAME EXPECTED [ARG...]: run the report with ARG.
times() {
  local name=$1 expected=$2
  shift 2
  run "$name" "$expected" org/audit/ci-times.sh -- "$@"
}

# workflows PATH...: answer the workflows of atom-x; the first has the ID
# $ci_id.
workflows() {
  local path id=$ci_id
  for path; do
    jq -n --argjson id "$id" --arg path ".github/workflows/$path" '{id: $id, path: $path}'
    id=$((id + 1))
  done | jq -s '{workflows: .}' | fixture_page "$workflows" 1
}

# run_of ID EVENT BRANCH SHA START END CONCLUSION: print a run of 2026-11-10
# from START to END, as hh:mm:ss.
run_of() {
  local id=$1 event=$2 branch=$3 sha=$4 start=$5 end=$6 conclusion=$7
  jq -n --argjson id "$id" --arg event "$event" --arg branch "$branch" \
    --arg sha "$sha" --arg start "2026-11-10T${start}Z" --arg end "2026-11-10T${end}Z" \
    --arg conclusion "$conclusion" '{id: $id, event: $event, head_branch: $branch,
      head_sha: $sha, run_started_at: $start, updated_at: $end, conclusion: $conclusion}'
}

# runs SINCE PAGE: answer the page PAGE of the runs created since SINCE with
# the runs on stdin.
runs() {
  local since=$1 page=$2
  jq -s '{workflow_runs: .}' \
    | fixture_page "repos/fy/atom-x/actions/workflows/$ci_id/runs?created=>=$since&per_page=100" "$page"
}

# job_of RUN NAME START END [CONCLUSION]: print a job of the run RUN of
# 2026-11-10 from START to END, as hh:mm:ss, which succeeds unless CONCLUSION
# is given.
job_of() {
  local run=$1 name=$2 start=$3 end=$4 conclusion=${5:-success}
  jq -n --argjson run "$run" --arg name "$name" --arg start "2026-11-10T${start}Z" \
    --arg end "2026-11-10T${end}Z" --arg conclusion "$conclusion" \
    '{run_id: $run, name: $name, started_at: $start, completed_at: $end,
      conclusion: $conclusion}'
}

# jobs_of RUN: answer the jobs of the run RUN with the jobs on stdin.
jobs_of() {
  local run=$1
  jq -s '{jobs: .}' | fixture_page "repos/fy/atom-x/actions/runs/$run/jobs?per_page=100" 1
}

# expect_order TEXT...: stdout has a line with each TEXT, in the order given.
# shellcheck disable=SC2154 # work comes from case.sh of the harness
expect_order() {
  local text line last=0
  for text; do
    line=$(grep -nF -- "$text" "$work/stdout" | head -n 1 | cut -d: -f1)
    ((${line:-0} > last)) || {
      report "no '$text' after line $last"
      return
    }
    last=$line
  done
}

# Two branches of pull requests, a cancelled run, a run that failed to start
# and has no jobs, a push on a second page, matrix jobs and a skipped job.
setup_org
fixed_time "$now"
workflows test.yaml scorecard.yaml
{
  run_of 1 pull_request a a1 10:00:00 10:05:00 success
  run_of 2 pull_request a a2 11:00:00 11:10:00 failure
  run_of 3 pull_request a a2 12:00:00 12:01:00 cancelled
  run_of 4 pull_request b b1 13:00:00 13:02:00 success
  run_of 6 pull_request b b1 15:00:00 15:50:00 failure
} | runs "$default_since" 1
run_of 5 push main m1 14:00:00 14:04:00 success | runs "$default_since" 2
{
  job_of 1 unit 10:00:30 10:02:00
  job_of 1 'check / meta' 10:02:10 10:04:00
} | jobs_of 1
{
  job_of 2 unit 11:01:00 11:03:00
  job_of 2 'check / meta' 11:03:00 11:09:00 failure
} | jobs_of 2
{
  job_of 4 'unit (shard 1)' 13:00:10 13:01:10
  job_of 4 'check / pending' 13:00:00 13:00:00 skipped
} | jobs_of 4
job_of 5 'unit (x86_64-linux, ubuntu-24.04)' 14:00:00 14:03:00 | jobs_of 5
times "numbers" ok atom-x
expect call "GET $workflows"
expect message "# CI times since $default_since"
# Every run counts; the cancelled one is not timed and its jobs are not read,
# and the one without jobs is not timed.
# The values are nearest ranks of the sorted times, worked out by hand.
expect message '| atom-x | pull_request | 5 | 3 | 5:00 | 10:00 | 3:30 | 8:00 |'
expect message '| atom-x | push | 1 | 1 | 4:00 | 4:00 | 3:00 | 3:00 |'
expect no-call runs/3/jobs
# Matrix values other than systems are dropped; slowest jobs first.
expect_order '| atom-x | unit (x86_64-linux) | 1 | 3:00 | 3:00 |' \
  '| atom-x | check / meta | 2 | 1:50 | 6:00 |' \
  '| atom-x | unit | 3 | 1:30 | 2:00 |'
expect no-message 'check / pending'
# Branch a has 3 runs of 2 commits, branch b 2 runs of 1.
expect message '| atom-x | 2 | 2.5 | 3 | 1.5 | 2 |'
finish

# The CI workflow of workflow-check, a day given, and JSON.
setup_org
workflows check-self.yaml check.yaml
run_of 1 push main m1 10:00:00 10:01:00 success | runs 2026-11-01 1
job_of 1 unit 10:00:00 10:00:30 | jobs_of 1
times "since" ok --since 2026-11-01 --json atom-x
expect message '"since": "2026-11-01"'
expect message '"median": 60'
finish

# A repository without the CI workflow has no rows.
setup_org
fixed_time "$now"
workflows scorecard.yaml
times "no CI" ok atom-x
expect no-call /runs
expect no-message '| atom-x |'
finish

setup_org
fixed_time "$now"
workflows test.yaml
run_of 1 push main m1 10:00:00 10:01:00 success | runs "$default_since" 1
apply FAIL_ON="GET repos/fy/atom-x/actions/runs/1/jobs?per_page=100 500"
times "jobs fail" fail atom-x
expect no-message '# CI times'
finish

setup_org
times "not a day" fail --since 1.11.2026 atom-x
expect message 'not a day: 1.11.2026'
expect no-calls
finish

setup_org
times "unknown option" fail --until 2026-11-01 atom-x
expect message 'usage: ci-times.sh'
finish

conclude
