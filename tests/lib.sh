# shellcheck shell=bash
# Helpers of the tests: run a script of org/ for the organization "fy" with the
# stub of gh, then check the calls that it made. Sourced by the tests.

tests=$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)
root=$(dirname -- "$tests")
work=$(mktemp -d)
trap 'rm -rf -- "$work"' EXIT
export GH_LOG=$work/gh.log GH_FIXTURES=$work/fixtures
mkdir -p "$GH_FIXTURES"
output=$work/output
failures=0

# fixture METHOD PATH: store stdin as the answer of the stub to METHOD PATH.
fixture() {
  local method=$1 path=$2 key
  key="$method $path"
  cat >"$GH_FIXTURES/${key//\//_}.json"
}

# fixture_status METHOD PATH STATUS: make the stub answer METHOD PATH with the
# HTTP status STATUS.
fixture_status() {
  local method=$1 path=$2 status=$3 key
  key="$method $path"
  printf '%s\n' "$status" >"$GH_FIXTURES/${key//\//_}.status"
}

clear_fixtures() { rm -f -- "$GH_FIXTURES"/*; }

# run_org SCRIPT ARG...: run org/SCRIPT with the stub. Its output is in
# $output and its exit status in $status.
run_org() {
  local script=$1
  shift
  : >"$GH_LOG"
  status=0
  PATH="$tests/bin:$PATH" ORG=fy bash "$root/org/$script" "$@" >"$output" 2>&1 \
    || status=$?
}

# check DESCRIPTION COMMAND...: report whether COMMAND succeeds.
check() {
  local description=$1
  shift
  if "$@"; then
    printf 'ok   %s\n' "$description"
  else
    printf 'FAIL %s\n' "$description"
    failures=$((failures + 1))
  fi
}

# called CALL: whether a logged call contains CALL.
called() { grep -qF -- "$1" "$GH_LOG"; }

not_called() { ! called "$1"; }

# sent CALL BODY: whether the call "gh CALL" was made with the JSON BODY.
sent() {
  local call=$1 body=$2
  awk -v call="gh $call" -v body="  body: $body" '
    previous == call && $0 == body { found = 1 }
    { previous = $0 }
    END { exit !found }
  ' "$GH_LOG"
}

# exited STATUS: whether the last run exited with STATUS.
exited() { ((status == $1)); }

# printed TEXT: whether the output of the last run contains TEXT.
printed() { grep -qF -- "$1" "$output"; }

not_printed() { ! printed "$1"; }

# not COMMAND...: whether COMMAND fails.
not() { ! "$@"; }

# finish: print the number of failures and succeed only without any.
finish() {
  printf '%d failures\n' "$failures"
  ((failures == 0))
}
