#!/usr/bin/env bash
# Apply organization-wide settings from organization/*.json.
# Requires gh with a token that has the admin:org scope, and jq.
#
# The release bot GitHub App is recorded as organization variables when its
# identifiers are given: BOT_APP_ID (numeric) and BOT_CLIENT_ID.
set -euo pipefail

org=${ORG:-flakeyard}

die() {
  printf '%s\n' "$*" >&2
  exit 1
}

for tool in gh jq; do
  command -v "$tool" >/dev/null || die "missing tool: $tool"
done

declare -A patterns=([BOT_APP_ID]='^[0-9]+$' [BOT_CLIENT_ID]='^Iv[0-9A-Za-z.]+$')
# Validate before anything is changed.
for name in "${!patterns[@]}"; do
  [[ -z ${!name:-} || ${!name} =~ ${patterns[$name]} ]] \
    || die "$name has an unexpected format: ${!name}"
done

cd -- "$(dirname -- "${BASH_SOURCE[0]}")/organization"

# set_org METHOD PATH FILE: send FILE to orgs/$org/PATH.
set_org() {
  gh api --silent -X "$1" "orgs/$org$2" --input "$3"
  printf '%s orgs/%s%s\n' "$1" "$org" "$2"
}

set_org PATCH "" organization.json
# The selected actions list is accepted only once the policy is "selected".
set_org PUT /actions/permissions actions-permissions.json
set_org PUT /actions/permissions/selected-actions actions-selected.json
set_org PUT /actions/permissions/workflow actions-workflow.json
set_org PUT /actions/permissions/fork-pr-contributor-approval \
  actions-fork-pr-approval.json
set_org PUT /actions/permissions/artifact-and-log-retention \
  actions-retention.json
set_org PUT /actions/permissions/self-hosted-runners \
  actions-self-hosted-runners.json

for name in "${!patterns[@]}"; do
  if [[ -n ${!name:-} ]]; then
    gh variable set "$name" --org "$org" --visibility all --body "${!name}"
    printf 'variable %s\n' "$name"
  fi
done
