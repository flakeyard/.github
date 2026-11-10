#!/usr/bin/env bash
# Run every test of tests/cases/ and fail when one of them fails. The tests use
# the harness of internal/testing of the shell library at the commit that
# test.yaml pins.
set -euo pipefail

cd -- "$(dirname -- "${BASH_SOURCE[0]}")"
readonly LIBRARY_URL=https://github.com/flakeyard/action-shell-lib
# The pin of the library; the commit is the first group.
readonly LIBRARY_PIN_RE='uses: flakeyard/action-shell-lib@([0-9a-f]{40})'

# load_library FILE: unless SHELL_LIB is set, as by the CI, export it as the
# library at the commit that FILE pins, fetched once into the cache. Each
# repository keeps this loader, since it cannot come from the library that it
# loads (FY-0035).
load_library() {
  local file=$1 commit
  [[ -z ${SHELL_LIB-} ]] || return 0
  [[ $(<"$file") =~ $LIBRARY_PIN_RE ]] || { echo "$file pins no action-shell-lib" >&2 && exit 2; }
  commit=${BASH_REMATCH[1]}
  export SHELL_LIB=${XDG_CACHE_HOME:-$HOME/.cache}/flakeyard/action-shell-lib/$commit
  # HEAD is set once the checkout is complete, so a failed fetch is repeated.
  git -C "$SHELL_LIB" rev-parse -q --verify HEAD &>/dev/null || { git init -q "$SHELL_LIB" \
    && git -C "$SHELL_LIB" fetch -q --depth 1 "$LIBRARY_URL" "$commit" \
    && git -C "$SHELL_LIB" checkout -qf FETCH_HEAD; } || exit 2
}

load_library ../.github/workflows/test.yaml
failed=()
for test in cases/*.sh; do
  printf '# %s\n' "$test"
  bash "$test" || failed+=("$test")
done
if ((${#failed[@]} > 0)); then
  printf 'failed: %s\n' "${failed[*]}" >&2
  exit 1
fi
