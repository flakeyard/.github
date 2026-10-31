#!/usr/bin/env bash
# Apply repository settings, labels, topics, rulesets and security features.
#
# Usage: apply.sh [repo...]
#   Without arguments, applies to every non-archived repository of $ORG.
#
# Requires gh with a token that has the repo scope, and jq. The GitHub App
# that may create and move release tags is read from $BOT_APP_ID or from the
# organization variable BOT_APP_ID. When $BOT_PRIVATE_KEY_FILE names its private
# key, the key is stored in the environment "release" of released repositories.
# When $CACHIX_AUTH_TOKEN_FILE names the push token of the binary cache, it is
# stored in the environment "cache" of repositories that push to it.
# shellcheck source-path=SCRIPTDIR
set -euo pipefail

org=${ORG:-flakeyard}
here=$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)

die() {
  printf '%s\n' "$*" >&2
  exit 1
}

for tool in gh jq; do
  command -v "$tool" >/dev/null || die "missing tool: $tool"
done

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

repos=("$@")
if ((${#repos[@]} == 0)); then
  # Assigned separately so that a failing gh stops the script.
  all=$(gh repo list "$org" --limit 1000 --no-archived \
    --json name --jq '.[].name')
  [[ -n $all ]] || die "no repositories in $org"
  mapfile -t repos <<<"$all"
fi

for repo in "${repos[@]}"; do
  apply_settings "$repo"
  apply_labels "$repo"
  apply_topics "$repo"
  apply_rulesets "$repo"
  apply_environments "$repo"
  apply_security "$repo"
  printf '%s: done\n' "$repo"
done
