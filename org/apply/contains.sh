# shellcheck shell=bash
# Membership in a list of words. Sourced by apply.sh.

# contains WORD LIST...: whether WORD is one of LIST.
contains() {
  local word=$1 item
  shift
  for item; do
    [[ $item == "$word" ]] && return 0
  done
  return 1
}
