# shellcheck shell=bash disable=SC2154 # globals of apply.sh
# Labels of a repository, from repository/labels.json. Sourced by apply.sh,
# which sets org and here.

# Labels are compared as "name<TAB>color<TAB>description" lines.

# current_labels REPO: print every label of REPO.
current_labels() {
  local repo=$1
  gh api --paginate "repos/$org/$repo/labels?per_page=100" \
    --jq '.[] | [.name, .color, .description // ""] | @tsv'
}

# wanted_labels: print every label of labels.json.
wanted_labels() {
  jq -r '.[] | [.name, .color, .description] | @tsv' \
    "$here/repository/labels.json"
}

# create_label REPO LABEL: create the label described by the line LABEL.
create_label() {
  local repo=$1 label=$2 name color description
  IFS=$'\t' read -r name color description <<<"$label"
  gh api --silent -X POST "repos/$org/$repo/labels" \
    -f name="$name" -f color="$color" -f description="$description"
}

# update_label REPO OLD LABEL: make the label named OLD match the line LABEL.
update_label() {
  local repo=$1 old=$2 label=$3 path name color description
  IFS=$'\t' read -r name color description <<<"$label"
  path=$(jq -rn --arg name "$old" '$name | @uri')
  gh api --silent -X PATCH "repos/$org/$repo/labels/$path" \
    -f new_name="$name" -f color="$color" -f description="$description"
}

apply_labels() {
  local repo=$1 current wanted label name existing
  local -A by_name=()
  current=$(current_labels "$repo")
  wanted=$(wanted_labels)
  # GitHub compares label names ignoring case.
  while IFS= read -r label; do
    name=${label%%$'\t'*}
    [[ -n $name ]] && by_name[${name,,}]=$label
  done <<<"$current"
  while IFS= read -r label; do
    name=${label%%$'\t'*}
    existing=${by_name[${name,,}]-}
    if [[ -z $existing ]]; then
      create_label "$repo" "$label"
    elif [[ $existing != "$label" ]]; then
      update_label "$repo" "${existing%%$'\t'*}" "$label"
    fi
  done <<<"$wanted"
}
