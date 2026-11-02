#!/usr/bin/env bash
# Run every test of tests/cases/ and fail when one of them fails.
set -euo pipefail

cd -- "$(dirname -- "${BASH_SOURCE[0]}")"
failed=()
for test in cases/*.sh; do
  printf '# %s\n' "$test"
  bash "$test" || failed+=("$test")
done
if ((${#failed[@]} > 0)); then
  printf 'failed: %s\n' "${failed[*]}" >&2
  exit 1
fi
