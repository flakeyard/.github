# shellcheck shell=bash disable=SC2154 # globals of apply.sh
# Environments of a repository, their required reviewers and their secrets,
# from repository/environments/, matched with glob.sh. Sourced by apply.sh,
# which sets org, here, bot_key_file and cache_token_file.

# Branches that may deploy to the environments "release" and "cache".
readonly deploy_branches=(main 'release/v*')

# pushes_to_cache REPO: whether REPO pushes to the binary cache, by
# environments/cache.json.
pushes_to_cache() { matches_glob environments/cache.json "$1"; }

# branch_policies ENV: print "id<TAB>type<TAB>name" of every deployment policy.
branch_policies() {
  local env=$1
  gh api --paginate "$env/deployment-branch-policies?per_page=100" \
    --jq '.branch_policies[] | [.id, .type // "branch", .name] | @tsv'
}

# allow_deployment_branches ENV: make the release branches the only policies.
allow_deployment_branches() {
  local env=$1 policies id type name kept=() branch
  policies=$(branch_policies "$env")
  while IFS=$'\t' read -r id type name; do
    [[ -n $id ]] || continue
    if [[ $type == branch ]] && contains "$name" "${deploy_branches[@]}"; then
      kept+=("$name")
    else
      gh api --silent -X DELETE "$env/deployment-branch-policies/$id"
    fi
  done <<<"$policies"
  for branch in "${deploy_branches[@]}"; do
    contains "$branch" "${kept[@]}" && continue
    gh api --silent -X POST "$env/deployment-branch-policies" \
      -f name="$branch" -f type=branch
  done
}

# environment_reviewers NAME: print the required reviewers of the environment
# NAME as the JSON list of the API, from environments/NAME-reviewers.json. An
# environment without that file has no reviewers.
environment_reviewers() {
  local name=$1 file
  file="$here/repository/environments/$name-reviewers.json"
  if [[ -e $file ]]; then
    jq -c 'map({type, id})' "$file"
  else
    printf '[]\n'
  fi
}

# create_deploy_environment ENV REVIEWERS: create ENV with custom branch
# policies and the JSON list REVIEWERS, which replaces the reviewers it had.
# Self-review stays allowed: a reviewer approves the runs that their own
# merges start. Admins may not bypass the rules: a waiting job runs only after
# a reviewer approves it, and only on a deploy branch.
create_deploy_environment() {
  local env=$1 reviewers=$2
  jq -n --argjson reviewers "$reviewers" '{
    reviewers: $reviewers,
    prevent_self_review: false,
    can_admins_bypass: false,
    deployment_branch_policy:
      {protected_branches: false, custom_branch_policies: true}
  }' | gh api --silent -X PUT "$env" --input -
}

# deploy_environment REPO NAME: create the environment NAME of REPO,
# deployable only from the deploy branches, with its reviewers.
deploy_environment() {
  local repo=$1 name=$2 env reviewers
  env="repos/$org/$repo/environments/$name"
  reviewers=$(environment_reviewers "$name")
  create_deploy_environment "$env" "$reviewers"
  allow_deployment_branches "$env"
}

# store_secret REPO ENVIRONMENT SECRET FILE: store the contents of FILE as
# SECRET of ENVIRONMENT, when FILE is given.
store_secret() {
  local repo=$1 environment=$2 secret=$3 file=$4
  [[ -n $file ]] || return 0
  gh secret set "$secret" --repo "$org/$repo" --env "$environment" <"$file"
}

# environment_names REPO: print the name of every environment of REPO.
environment_names() {
  local repo=$1
  gh api --paginate "repos/$org/$repo/environments?per_page=100" \
    --jq '.environments[].name'
}

# warn_unmanaged_environments REPO MANAGED...: warn about every environment of
# REPO that is not one of MANAGED. It is drift, but it is left in place:
# deleting it would delete its secrets too, so that is left to the owner.
warn_unmanaged_environments() {
  local repo=$1 names name unmanaged=()
  shift
  names=$(environment_names "$repo")
  while IFS= read -r name; do
    [[ -n $name ]] || continue
    contains "$name" "$@" || unmanaged+=("$name")
  done <<<"$names"
  ((${#unmanaged[@]} > 0)) || return 0
  printf 'warning: %s: environments not in repository/environments/:\n' \
    "$repo" >&2
  printf '%s\n' "${unmanaged[@]}" >&2
}

# The bot key and the cache token are available only to jobs on the deploy
# branches, and the bot key only after a reviewer approves the job. The secret
# names must match those declared by the workflows: an environment secret
# reaches a reusable workflow only under the name the caller passes.
apply_environments() {
  local repo=$1 managed=()
  if is_released "$repo"; then
    deploy_environment "$repo" release
    store_secret "$repo" release APP_PRIVATE_KEY "$bot_key_file"
    managed+=(release)
  fi
  if pushes_to_cache "$repo"; then
    deploy_environment "$repo" cache
    store_secret "$repo" cache CACHIX_AUTH_TOKEN "$cache_token_file"
    managed+=(cache)
  fi
  warn_unmanaged_environments "$repo" "${managed[@]}"
}
