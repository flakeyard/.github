# shellcheck shell=bash disable=SC2154 # globals of apply.sh
# Environments of a repository and their secrets, from
# repository/environments/, matched with glob.sh. Sourced by apply.sh, which
# sets org, bot_key_file and cache_token_file.

# Branches that may deploy to the environments "release" and "cache".
readonly deploy_branches=(main 'release/v*')

# is_released REPO: whether REPO releases, by environments/release.json.
is_released() { matches_glob environments/release.json "$1"; }

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

# create_deploy_environment ENV: create ENV with custom branch policies.
create_deploy_environment() {
  local env=$1
  gh api --silent -X PUT "$env" \
    -F 'deployment_branch_policy[protected_branches]=false' \
    -F 'deployment_branch_policy[custom_branch_policies]=true'
}

# deploy_environment REPO NAME: create the environment NAME of REPO,
# deployable only from the deploy branches.
deploy_environment() {
  local repo=$1 name=$2 env
  env="repos/$org/$repo/environments/$name"
  create_deploy_environment "$env"
  allow_deployment_branches "$env"
}

# store_secret REPO ENVIRONMENT SECRET FILE: store the contents of FILE as
# SECRET of ENVIRONMENT, when FILE is given.
store_secret() {
  local repo=$1 environment=$2 secret=$3 file=$4
  [[ -n $file ]] || return 0
  gh secret set "$secret" --repo "$org/$repo" --env "$environment" <"$file"
}

# The bot key and the cache token are available only to jobs on the deploy
# branches. The secret names must match those declared by the workflows: an
# environment secret reaches a reusable workflow only under the name the
# caller passes.
apply_environments() {
  local repo=$1
  if is_released "$repo"; then
    deploy_environment "$repo" release
    store_secret "$repo" release APP_PRIVATE_KEY "$bot_key_file"
  fi
  if pushes_to_cache "$repo"; then
    deploy_environment "$repo" cache
    store_secret "$repo" cache CACHIX_AUTH_TOKEN "$cache_token_file"
  fi
}
