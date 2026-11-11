#!/usr/bin/env bash
# Report how long the CI of the organization takes: for the runs of the
# workflow test.yaml, or check-self.yaml in workflow-check, created since a
# date, the times of the runs by event, the times of their jobs, and how often
# the head branch of a pull request is tested. It changes nothing.
#
# Usage: ci-times.sh [--since YYYY-MM-DD] [--json] [repo...]
#   --since  the first day of the runs, in UTC; 14 days ago by default.
#   --json   print the numbers as JSON instead of Markdown tables.
#   Without repositories, reports every non-archived repository of $ORG.
#
# Requires gh and jq. The repositories are public, so a read-only token is
# enough. Times are in seconds in the JSON and as minutes:seconds in the
# tables.
# shellcheck source-path=SCRIPTDIR/..
set -euo pipefail

here=$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)
# shellcheck source=lib.sh
source "$here/../lib.sh"

readonly usage='usage: ci-times.sh [--since YYYY-MM-DD] [--json] [repo...]'
readonly day_form='^[0-9]{4}-[0-9]{2}-[0-9]{2}$'
readonly default_days=14
readonly seconds_per_day=86400
# The workflow that runs the check job of workflow-check.
readonly ci_workflow='^\.github/workflows/(test|check-self)\.yaml$'

# The definitions shared by the jq programs below. A run or a job is timed
# when it ran to its end: it succeeded or failed, and was not cancelled or
# skipped. A percentile is the nearest rank, so it is one of the values.
# shellcheck disable=SC2016 # jq variables, not shell ones
readonly jq_definitions='
  def seconds($from; $to): ($to | fromdateiso8601) - ($from | fromdateiso8601);
  def timed: .conclusion == "success" or .conclusion == "failure";
  def percentile($p): sort | if . == [] then null else .[(length * $p | ceil) - 1] end;
  def spread: {median: percentile(0.5), p90: percentile(0.9)};
  def one_decimal: . * 10 | round / 10;
  def mean: if . == [] then null else add / length | one_decimal end;
  def mean_max: {mean: mean, max: max};
  # A system of a matrix, such as x86_64-linux.
  def systems: [scan("(?:x86_64|aarch64)-(?:linux|darwin)")];
  # The name of a job without its matrix values, other than its systems.
  def job_group:
    capture("^(?<base>.*?)(?: \\((?<matrix>.*)\\))?$")
    | (.matrix // "" | systems) as $systems
    | .base + (if $systems == [] then "" else " (\($systems | join(", ")))" end);
  def duration: seconds(.started_at; .completed_at);
'

# A jq program that reads the runs of a repository and, as $jobs, a file with
# the list of the jobs of its timed runs, and prints the numbers of the
# repository $repo. The jobs time of a run is from the start of its first job
# to the end of its last, so it leaves out the wait for the first runner.
# shellcheck disable=SC2016 # jq variables, not shell ones
readonly jq_summary="$jq_definitions"'
  ($jobs[0] | map(select(timed))) as $ran
  | ($ran | group_by(.run_id) | map({key: "\(.[0].run_id)", value: .}) | from_entries) as $by_run
  | def jobs_time: $by_run["\(.id)"] // [] | if . == [] then null
      else seconds(map(.started_at) | min; map(.completed_at) | max) end;
  # A run without jobs failed to start, and its last update can come much
  # later, so it is not timed.
  def times: {wall: seconds(.run_started_at; .updated_at), jobs: jobs_time};
  def event_numbers:
    {event: .[0].event, runs: length}
    + (map(select(timed) | times | select(.jobs != null))
      | {timed: length, wall: (map(.wall) | spread), jobs_time: (map(.jobs) | spread)});
  def branch_numbers: {runs: length, commits: (map(.head_sha) | unique | length)};
  {
    repository: $repo,
    events: (group_by(.event) | map(event_numbers)),
    jobs: ($ran | group_by(.name | job_group)
      | map({job: (.[0].name | job_group), runs: length} + (map(duration) | spread))),
    pull_requests: (map(select(.event == "pull_request")) | group_by(.head_branch)
      | map(branch_numbers)
      | {branches: length, runs: (map(.runs) | mean_max),
         commits: (map(.commits) | mean_max)})
  }
'

# A jq program that prints the report of the JSON of report_json as Markdown.
# shellcheck disable=SC2016 # jq variables, not shell ones
readonly jq_markdown='
  def two_digits: tostring | if length < 2 then "0" + . else . end;
  # Seconds as minutes:seconds.
  def clock: 60 as $minute | if . == null then "-"
    else "\(. / $minute | floor):\(. % $minute | two_digits)" end;
  def cell: if . == null then "-" else tostring end;
  def row: "| " + (map(cell) | join(" | ")) + " |";
  def table($head): ($head | row), ([range($head | length) | "---"] | row);
  "# CI times since \(.since)", "",
  "## Runs", "",
  table(["Repository", "Event", "Runs", "Timed", "Wall p50", "Wall p90", "Jobs p50", "Jobs p90"]),
  (.repositories[] | .repository as $repo | .events[]
    | [$repo, .event, .runs, .timed, (.wall.median, .wall.p90, .jobs_time.median, .jobs_time.p90 | clock)] | row),
  "", "## Jobs", "",
  table(["Repository", "Job", "Runs", "p50", "p90"]),
  (.repositories[] | .repository as $repo | .jobs | sort_by(-.median)[]
    | [$repo, .job, .runs, (.median, .p90 | clock)] | row),
  "", "## Pull request branches", "",
  table(["Repository", "Branches", "Runs mean", "Runs max", "Commits mean", "Commits max"]),
  (.repositories[] | .repository as $repo | .pull_requests
    | [$repo, .branches, .runs.mean, .runs.max, .commits.mean, .commits.max] | row)
'

since=""
format=markdown
targets=()

# days_ago DAYS: print the day DAYS days before today, in UTC.
days_ago() {
  local days=$1 now
  now=$(date -u +%s)
  date -u -d "@$((now - days * seconds_per_day))" +%F
}

# parse_arguments ARG...: set since, format and targets from the command line.
parse_arguments() {
  while (($#)); do
    case $1 in
      --since) since=${2-} && shift ;;
      --json) format=json ;;
      -*) die "$usage" ;;
      *) targets+=("$1") ;;
    esac
    shift
  done
  [[ -n $since ]] || since=$(days_ago "$default_days")
  [[ $since =~ $day_form ]] || die "not a day: $since; $usage"
}

# ci_workflow_id REPO: print the ID of the CI workflow of REPO, or nothing
# when REPO has none.
ci_workflow_id() {
  local repo=$1
  api_list "repos/$org/$repo/actions/workflows?per_page=100" '.workflows[]' \
    | jq -r --arg form "$ci_workflow" 'first(.[] | select(.path | test($form))) | .id'
}

# ci_runs REPO WORKFLOW FILE: store the runs of WORKFLOW of REPO created since
# $since as one JSON list in FILE. The API finds at most 1000 runs for one
# filter; split the window when a repository has more.
ci_runs() {
  local repo=$1 workflow=$2 file=$3
  api_list "repos/$org/$repo/actions/workflows/$workflow/runs?created=>=$since&per_page=100" \
    '.workflow_runs[]' >"$file"
}

# run_jobs REPO RUNS FILE: store the jobs of the latest attempt of every timed run
# of the list RUNS as one JSON list in FILE.
run_jobs() {
  local repo=$1 runs=$2 file=$3 id
  for id in $(jq -r "$jq_definitions"' .[] | select(timed) | .id' "$runs"); do
    gh api --paginate "repos/$org/$repo/actions/runs/$id/jobs?per_page=100" --jq '.jobs[]'
  done | jq -s . >"$file"
}

# summarize REPO DIR: print the numbers of REPO as JSON, with DIR for
# temporary files; nothing when REPO has no CI workflow.
summarize() {
  local repo=$1 dir=$2 workflow
  workflow=$(ci_workflow_id "$repo")
  [[ -n $workflow ]] || return 0
  ci_runs "$repo" "$workflow" "$dir/runs.json"
  run_jobs "$repo" "$dir/runs.json" "$dir/jobs.json"
  jq --arg repo "$repo" --slurpfile jobs "$dir/jobs.json" "$jq_summary" \
    "$dir/runs.json"
}

# report_json DIR: print the numbers of every repository of repos as one JSON
# object, with DIR for temporary files.
report_json() {
  local dir=$1 repo
  for repo in "${repos[@]}"; do
    summarize "$repo" "$dir"
  done | jq -s --arg since "$since" '{since: $since, repositories: .}'
}

parse_arguments "$@"
select_repositories "${targets[@]}"

work=$(mktemp -d)
trap 'rm -rf -- "$work"' EXIT

# A file, not a variable, so that a failing request stops the script.
report_json "$work" >"$work/report.json"
if [[ $format == json ]]; then
  cat -- "$work/report.json"
else
  jq -r "$jq_markdown" "$work/report.json"
fi
