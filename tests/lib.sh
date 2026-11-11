# shellcheck shell=bash
# Helpers of the tests, on case.sh, fixtures.sh and checks.sh of
# internal/testing of the shell library in SHELL_LIB: run a script of org/ for
# the organization "fy" with the stub of gh of the library, which logs every
# call to CALLS and answers from the fixtures of the test, then check the calls
# that it made. Sourced by the tests. A case is
#
#   setup_org; fixture ...; run NAME EXPECTED org/SCRIPT [NAME=VALUE...] [-- ARG...]; expect ...; finish

tests=$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)
root=$(dirname -- "$tests")
# shellcheck source=/dev/null
source "${SHELL_LIB:?}/internal/testing/case.sh"
# shellcheck source=/dev/null
source "$SHELL_LIB/internal/testing/fixtures.sh"
# shellcheck source=/dev/null
source "$SHELL_LIB/internal/testing/checks.sh"
# The scripts that run takes paths in.
# shellcheck disable=SC2034 # read by checks.sh
code_root=$root

# setup_org: setup for one case: the organization fy, and a stub of gh that
# logs reads too and answers a read without a fixture with nothing, as an empty
# listing.
setup_org() {
  setup
  apply ORG=fy LOG_GETS=1 MISSING_IS_EMPTY=1
}
