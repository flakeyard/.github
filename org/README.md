# Organization settings

Settings of the flakeyard organization and its repositories, kept as code.
GitHub Free has no organization-level rulesets, so repository-level settings are
applied to every repository by a script.

| Path                         | Applied by    | Scope                           |
| ---------------------------- | ------------- | ------------------------------- |
| `organization/settings.json` | `settings.sh` | base permissions, members       |
| `organization/actions/`      | `settings.sh` | Actions policies                |
| `repository/settings.json`   | `apply.sh`    | merge, secret scanning          |
| `repository/actions/`        | `apply.sh`    | permissions of `GITHUB_TOKEN`   |
| `repository/labels.json`     | `apply.sh`    | issue and PR labels             |
| `repository/topics.json`     | `apply.sh`    | topics, matched by repo glob    |
| `repository/environments/`   | `apply.sh`    | repos and reviewers of each env |
| `repository/rulesets/`       | `apply.sh`    | `main`, `release/v*`, `v*` refs |

Only `settings.sh` and `apply.sh` are run. `apply.sh` sources one file per
concern from `apply/`: `settings.sh`, `actions.sh`, `labels.sh`, `topics.sh`,
`rulesets.sh`, `environments.sh` and `security.sh` apply one part each, and
`http.sh`, `glob.sh` and `contains.sh` are helpers they share. `settings.sh`
sources `settings/installations.sh`, which checks the installed GitHub Apps. The
files under `apply/` and `settings/` are not run on their own
([FY-0011][fy-0011]).

## Usage

Both scripts need [gh](https://cli.github.com/) and [jq](https://jqlang.org/),
and are safe to run repeatedly. Settings changed only in the web interface are
drift and are overwritten by the next run ([FY-0011][fy-0011]): topics that
`topics.json` does not list are removed, and so are deployment branch policies
other than `main` and `release/v*`.

```sh
gh auth refresh -h github.com -s admin:org  # once, for settings.sh
./settings.sh                               # organization settings
./apply.sh                                  # all repositories
./apply.sh atom-shell                       # a single repository
```

`apply.sh` also enables Dependabot alerts, private vulnerability reporting and
immutable releases in every repository, CodeQL default setup in `atom-*` and
`action-*`, and Discussions in `.github`, which serve the whole organization.

`settings.sh` also stores the identifiers of the release bot GitHub App as the
organization variables `BOT_APP_ID` and `BOT_CLIENT_ID` when they are given:

```sh
BOT_APP_ID=5414823 BOT_CLIENT_ID=Iv23... ./settings.sh
```

Last, `settings.sh` checks that every GitHub App of
`organization/installations.json` is installed on the organization for the
listed repositories, and that no other App is installed. The permissions listed
there are a ceiling: an App that holds a permission not listed, or a higher
level of one, is drift. A lower or missing permission is not, so the check does
not break when an App asks for less. An App that asks for more needs the owner's
approval on GitHub, and then a pull request that lists the new permission. The
check changes nothing and runs after every setting is applied: it prints every
difference and then fails.

Run `apply.sh` for every new repository. It needs the ID of the release bot
GitHub App, either as `BOT_APP_ID` in the environment or as the organization
variable of the same name; only that app may create, move or delete `v*` tags.

Workflows get a read-only `GITHUB_TOKEN` in every repository, from
`repository/actions/workflow.json`. Only released repositories also let it
create and approve pull requests: their release pull request is opened with
`GITHUB_TOKEN`, and the bot key is used only by the job that releases. The flag
lets anyone who can push a branch make `github-actions[bot]` open or approve a
pull request, so `apply.sh` clears it in every other repository. An approval by
the bot grants nothing, since the ruleset `main` requires no approving review.

A repository can turn the flag on only when the organization allows it, and
GitHub answers HTTP 409 otherwise ([API][workflow-api]), so
`organization/actions/workflow.json` allows it. The organization value applies
to every repository that does not set its own, so when `settings.sh` changes it,
run `apply.sh` for all repositories right after, to turn the flag off where it
must be off.

Every released repository, matched by a glob of `environments/release.json`,
gets the environment `release`, deployable only from `main` and `release/v*`.
The bot's private key is the secret `APP_PRIVATE_KEY` of that environment
([FY-0021][fy-0021]). Pass the key file to store it, for a new repository or
after a rotation:

```sh
BOT_PRIVATE_KEY_FILE=~/flakeyard-bot.pem ./apply.sh atom-shell
```

Every job of `release` waits until a required reviewer approves it, so no
release, tag or release pull request is made without the owner, even when a
compromised app merges a pull request into `main`. The reviewers are the users
of `environments/release-reviewers.json`, by user ID; the login there is only
for readers. `apply.sh` replaces the reviewers of the environment with that
list. Self-review stays allowed: the owner merges the release pull requests, and
the run that the merge starts waits for their own approval.

Admins cannot bypass the rules of `release` and `cache`. A waiting job starts
only after a required reviewer approves it, and only on a deploy branch, even
for an organization owner. The owner still approves their runs as the reviewer;
they lose only the option to start a job without a review.

Until a repository calls `workflow-release` v0.2.0, both the release job and the
pull request job of that workflow use `release`, so with the reviewer every
merge waits for two approvals. `apply.sh` sets the reviewer on every released
repository regardless ([FY-0029][fy-0029]): a missing reviewer is a gap in the
protection of the bot key, a second approval only a delay. Run `apply.sh` for a
released repository right before merging the pull request that moves it to
v0.2.0, which needs the flag above to open its release pull request. In
`workflow-release`, which calls its own workflow, run it before merging that
change.

Every repository that pushes to the binary cache, matched by a glob of
`environments/cache.json`, gets the environment `cache`, deployable from the
same branches. The push token is the secret `CACHIX_AUTH_TOKEN` of that
environment ([FY-0009][fy-0009]); pass its file the same way:

```sh
CACHIX_AUTH_TOKEN_FILE=~/flakeyard-cachix.token ./apply.sh atom-shell
```

The environment `cache` has no reviewers, and `apply.sh` removes any that were
added by hand. Its push job runs on every push to `main`, and an approval of
each push would hold up every merge. The push token stays protected only by the
deploy branches, the risk that [FY-0019][fy-0019] accepts; a release still waits
for the reviewer of `release`.

## Tests

The tests run the scripts of `org/` against a stub of `gh` that answers from
fixtures and logs the calls, so they need neither a token nor the network:

```sh
../tests/run.sh
```

## Not covered

Some settings have no API or depend on external services. They are configured by
hand, by an organization owner:

- **Release GitHub App** ([FY-0021][fy-0021]). In Settings → Developer settings
  → GitHub Apps, create `flakeyard-bot` without a webhook, with the repository
  permissions listed in FY-0021 and no organization permissions, installable
  only on this account. Install it on all repositories; `settings.sh` checks the
  installation. Record its identifiers with
  `BOT_APP_ID=... BOT_CLIENT_ID=... ./settings.sh`.
- **Private keys of the release App.** Generate a key on the App's page, store
  it with `BOT_PRIVATE_KEY_FILE=... ./apply.sh` and keep the file outside of any
  repository. Rotate it once a year and at once when it may have been exposed:
  generate a new key, store it in every released repository, then delete the old
  key on the App's page.
- **Renovate** ([FY-0029][fy-0029]). Install the Mend Renovate app from [its
  page][renovate-app] on the organization for all repositories. `settings.sh`
  checks the installation and its permissions, not the mode. In the [Mend
  Developer Portal][mend-portal], set the organization settings of Renovate:
  Silent mode off, Automated PRs on, Require config file on and Create
  onboarding PRs off. The last two are also kept in code, as `requireConfig` and
  `onboarding` of `org-inherited-config.json` in `renovate-config`.
- **Binary cache** ([FY-0019][fy-0019]). Create the public Cachix cache
  `flakeyard` on the open source plan and a push token for it in the Cachix web
  interface. Store it with `CACHIX_AUTH_TOKEN_FILE=... ./apply.sh` and keep the
  file outside of any repository.
- **Container packages** (GHCR). After the first publication of an image, check
  in the package settings that it is public, linked to its repository, and that
  the repository has write access under Manage Actions access.
- **Code security configurations.** Not used: `apply.sh` enables the same
  features in every repository, CodeQL default setup only in `atom-*` and
  `action-*`, and a configuration attached to a repository would override them.
  In Settings → Code security → Configurations, keep no configuration attached
  to repositories and none as the default for new repositories.
- **Personal access token policy.** GitHub offers no API for it. In Settings →
  Personal access tokens, allow fine-grained tokens with administrator approval
  and a maximum lifetime of 90 days, and restrict classic tokens.

[mend-portal]: https://developer.mend.io/
[renovate-app]: https://github.com/apps/renovate
[fy-0009]:
  https://github.com/flakeyard/decisions/blob/main/docs/adr/records/0009-ci-on-runners.md
[fy-0011]:
  https://github.com/flakeyard/decisions/blob/main/docs/adr/records/0011-settings-as-code.md
[fy-0019]:
  https://github.com/flakeyard/decisions/blob/main/docs/adr/records/0019-binary-cache.md
[fy-0021]:
  https://github.com/flakeyard/decisions/blob/main/docs/adr/records/0021-release-bot.md
[fy-0029]:
  https://github.com/flakeyard/decisions/blob/main/docs/adr/records/0029-renovate-mend.md
[workflow-api]:
  https://docs.github.com/en/rest/actions/permissions#set-default-workflow-permissions-for-a-repository
