#!/usr/bin/env bash
# Apply repository settings, Actions permissions, labels, topics, rulesets,
# environments and security features.
#
# Usage: apply.sh [repo...]
#   Without arguments, applies to every non-archived repository of $ORG.
#
# A repository that fails does not stop the others: the script lists every
# repository that it did not apply to at the end, and then fails.
#
# Requires gh with a token that has the repo scope, and jq. The GitHub App
# that may create and move release tags is read from $BOT_APP_ID or from the
# organization variable BOT_APP_ID. When $BOT_PRIVATE_KEY_FILE names its private
# key, the key is stored in the environment "release" of released repositories.
# When $CACHIX_AUTH_TOKEN_FILE names the push token of the binary cache, it is
# stored in the environment "cache" of repositories that push to it.
# shellcheck source-path=SCRIPTDIR
set -euo pipefail

here=$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)
# shellcheck source=lib.sh
source "$here/lib.sh"

bot_app_id=${BOT_APP_ID:-}
if [[ -z $bot_app_id ]]; then
  bot_app_id=$(gh variable get BOT_APP_ID --org "$org" 2>/dev/null) || true
fi
[[ $bot_app_id =~ ^[0-9]+$ ]] \
  || die "BOT_APP_ID is not set (environment or organization variable)"

bot_key_file=${BOT_PRIVATE_KEY_FILE:-}
[[ -z $bot_key_file || -r $bot_key_file ]] \
  || die "cannot read BOT_PRIVATE_KEY_FILE: $bot_key_file"

cache_token_file=${CACHIX_AUTH_TOKEN_FILE:-}
[[ -z $cache_token_file || -r $cache_token_file ]] \
  || die "cannot read CACHIX_AUTH_TOKEN_FILE: $cache_token_file"

# The steps and their helpers, one file per concern.
# shellcheck source=apply/http.sh
source "$here/apply/http.sh"
# shellcheck source=apply/glob.sh
source "$here/apply/glob.sh"
# shellcheck source=apply/contains.sh
source "$here/apply/contains.sh"
# shellcheck source=apply/settings.sh
source "$here/apply/settings.sh"
# shellcheck source=apply/actions.sh
source "$here/apply/actions.sh"
# shellcheck source=apply/labels.sh
source "$here/apply/labels.sh"
# shellcheck source=apply/topics.sh
source "$here/apply/topics.sh"
# shellcheck source=apply/rulesets.sh
source "$here/apply/rulesets.sh"
# shellcheck source=apply/environments.sh
source "$here/apply/environments.sh"
# shellcheck source=apply/security.sh
source "$here/apply/security.sh"

# apply_repository REPO: apply every step to REPO.
apply_repository() {
  local repo=$1
  apply_settings "$repo"
  apply_actions "$repo"
  apply_labels "$repo"
  apply_topics "$repo"
  apply_rulesets "$repo"
  apply_environments "$repo"
  apply_security "$repo"
  printf '%s: done\n' "$repo"
}

# apply_or_record REPO: apply every step to REPO, and add REPO to failed when
# one fails. The steps run in a subshell, since one may exit through die, and
# with errexit, which a function called as a condition would lose; so this one
# must not be called as one.
apply_or_record() {
  local repo=$1 status
  set +e
  (
    set -e
    apply_repository "$repo"
  )
  status=$?
  set -e
  ((status == 0)) && return
  printf '%s: failed\n' "$repo" >&2
  failed+=("$repo")
}

select_repositories "$@"

failed=()
for repo in "${repos[@]}"; do
  apply_or_record "$repo"
done
((${#failed[@]} == 0)) \
  || die "not applied, run apply.sh again for: ${failed[*]}"
