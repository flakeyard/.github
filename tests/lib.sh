# shellcheck shell=bash
# Helpers of the tests, on case.sh and checks.sh of internal/testing of the
# shell library in SHELL_LIB: run a script of org/ for the organization "fy"
# with the stub of gh in tests/bin, which logs every call to CALLS and answers
# from the fixtures of the test, then check the calls that it made. Sourced by
# the tests. A case is
#
#   setup_org; fixture ...; run NAME EXPECTED org/SCRIPT [NAME=VALUE...] [-- ARG...]; expect ...; finish
# shellcheck disable=SC2154 # work and env_vars come from setup of the harness.

tests=$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)
root=$(dirname -- "$tests")
# shellcheck source=/dev/null
source "${SHELL_LIB:?}/internal/testing/case.sh"
# shellcheck source=/dev/null
source "$SHELL_LIB/internal/testing/checks.sh"
# The scripts that run takes paths in.
# shellcheck disable=SC2034 # read by checks.sh
code_root=$root

# setup_org: setup for one case: the stub of gh first on PATH and the
# organization fy.
setup_org() {
  setup
  apply PATH="$tests/bin:$TESTING_BIN:$HOST_PATH" ORG=fy
}

# fixture_base METHOD PATH: print the path of the fixtures of METHOD PATH
# without their extension, named as tests/bin/gh reads them.
fixture_base() {
  local method=$1 path=$2 key
  key="$method $path"
  printf '%s\n' "$work/fixtures/${key//\//_}"
}

# fixture METHOD PATH: store stdin as the answer of the stub to METHOD PATH.
fixture() {
  local method=$1 path=$2
  cat >"$(fixture_base "$method" "$path").json"
}

# fixture_status METHOD PATH STATUS: make the stub answer METHOD PATH with the
# HTTP status STATUS.
fixture_status() {
  local method=$1 path=$2 status=$3
  printf '%s\n' "$status" >"$(fixture_base "$method" "$path").status"
}

# expect_sent CALL BODY: the last run made the call "gh CALL" with the JSON
# BODY.
expect_sent() {
  local call=$1 body=$2
  [[ -n $current ]] || return 0
  awk -v call="gh $call" -v body="  body: $body" '
    previous == call && $0 == body { found = 1 }
    { previous = $0 }
    END { exit !found }
  ' "$work/calls" || report "no call 'gh $call' with the body $body"
}
