#!/usr/bin/env bash
# A repository that apply.sh fails on: the others are still applied, and the
# script names the repositories to apply again, then fails.
set -uo pipefail
# shellcheck source=tests/lib.sh
source "$(dirname -- "${BASH_SOURCE[0]}")/../lib.sh"

# The request of a step that fails for a repository: GitHub answers 409
# Conflict, as in apply-actions.sh.
readonly failing='PUT repos/fy/atom-y/actions/permissions/workflow 409'

setup_org
apply FAIL_ON="$failing"
run "one fails" fail org/apply.sh BOT_APP_ID=42 -- atom-x atom-y atom-z
expect message 'atom-x: done'
expect no-message 'atom-y: done'
expect message 'atom-y: failed'
# The repository after the failed one is applied in full.
expect call repos/fy/atom-z/actions/permissions/workflow
expect message 'atom-z: done'
expect message 'not applied, run apply.sh again for: atom-y'
finish

setup_org
apply FAIL_ON="$failing"
run "only one" fail org/apply.sh BOT_APP_ID=42 -- atom-y
expect message 'not applied, run apply.sh again for: atom-y'
finish

setup_org
run "none fails" ok org/apply.sh BOT_APP_ID=42 -- atom-x atom-y
expect no-message 'not applied'
finish

conclude
