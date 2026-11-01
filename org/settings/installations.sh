# shellcheck shell=bash disable=SC2154 # globals of settings.sh
# GitHub Apps installed on the organization, checked against
# organization/installations.json. Installing an App has no API, so drift is
# only reported. Sourced by settings.sh, which sets org.

# A jq program that reads installations.json and prints one line for every
# difference from the installations given as $installed. The permissions of
# an App are a ceiling: a permission that is missing or lower is fine, one
# that is not listed or higher is drift.
# shellcheck disable=SC2016 # jq variables, not shell ones
readonly jq_installation_problems='
  def level: {read: 1, write: 2, admin: 3}[.] // infinite;
  def ceiling($name): if has($name) then .[$name] | level else 0 end;
  def installation($slug):
    $installed | map(select(.app_slug == $slug)) | first;

  def selection_problem($found):
    select($found.repository_selection != .repository_selection)
    | "\(.app_slug): installed for \($found.repository_selection)"
      + " repositories, not \(.repository_selection)";

  def permission_problems($found):
    .app_slug as $slug | .permissions as $allowed
    | $found.permissions | to_entries[] | .key as $name
    | select((.value | level) > ($allowed | ceiling($name)))
    | "\($slug): permission \($name) is \(.value),"
      + " allowed \($allowed[$name] // "none")";

  def problems:
    installation(.app_slug) as $found
    | if $found == null then "\(.app_slug): not installed"
      else selection_problem($found), permission_problems($found) end;

  def unlisted($listed):
    $installed[].app_slug | select(IN($listed[]) | not)
    | "\(.): installed, but not listed";

  (.[] | problems), unlisted(map(.app_slug))
'

# installed_apps: print the installations of $org as one JSON list.
installed_apps() {
  gh api --paginate "orgs/$org/installations?per_page=100" \
    --jq '.installations[]' | jq -s .
}

# check_installations: print every difference between installations.json and
# the installed Apps, and fail when there is one.
check_installations() {
  local installed problems
  installed=$(installed_apps) || return
  problems=$(jq -r --argjson installed "$installed" \
    "$jq_installation_problems" installations.json) || return
  if [[ -n $problems ]]; then
    printf 'GitHub Apps differ from installations.json:\n%s\n' "$problems" >&2
    return 1
  fi
  printf 'installations of GitHub Apps checked\n'
}
