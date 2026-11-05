# Organization settings

Settings of the flakeyard organization and its repositories, kept as code.
GitHub Free has no organization-level rulesets, so repository-level settings are
applied to every repository by a script.

| Path                         | Applied by    | Scope                         |
| ---------------------------- | ------------- | ----------------------------- |
| `organization/settings.json` | `settings.sh` | base permissions, members     |
| `organization/actions/`      | `settings.sh` | Actions policies              |
| `repository/settings.json`   | `apply.sh`    | merge, secret scanning        |
| `repository/actions/`        | `apply.sh`    | permissions of `GITHUB_TOKEN` |
| `repository/labels.json`     | `apply.sh`    | issue and PR labels           |
| `repository/topics.json`     | `apply.sh`    | topics, matched by repo glob  |
| `repository/environments/`   | `apply.sh`    | environments and reviewers    |
| `repository/rulesets/`       | `apply.sh`    | branch and tag protection     |

Only `settings.sh`, `apply.sh` and `audit/releases.sh` are run, the last by the
workflow `audit` too. `apply.sh` sources one file per concern from `apply/`:
`settings.sh`, `actions.sh`, `labels.sh`, `topics.sh`, `rulesets.sh`,
`environments.sh` and `security.sh` apply one part each, and `http.sh`,
`glob.sh` and `contains.sh` are helpers they share. `settings.sh` sources
`settings/installations.sh`, which checks the installed GitHub Apps. The files
under `apply/` and `settings/` are not run on their own ([FY-0011][fy-0011]).

## Usage

Both scripts need [gh](https://cli.github.com/) and [jq](https://jqlang.org/),
and are safe to run repeatedly. Settings changed only in the web interface are
drift and are overwritten by the next run ([FY-0011][fy-0011]): topics that
`topics.json` does not list are removed, and so are deployment branch policies
other than `main` and `release/v*`. Rulesets that `repository/rulesets/` does
not define and environments that `repository/environments/` does not give to the
repository are kept, but `apply.sh` prints a warning that names them; delete
them by hand. A ruleset only adds rules, and deleting an environment deletes its
secrets. Rulesets inherited from the organization are not touched.

```sh
gh auth refresh -h github.com -s admin:org  # once, for settings.sh
./settings.sh                               # organization settings
./apply.sh                                  # all repositories
./apply.sh atom-shell                       # a single repository
```

`apply.sh` also enables Dependabot alerts, private vulnerability reporting and
immutable releases and CodeQL default setup in every repository, and Discussions
in `.github`, which serve the whole organization.

`settings.sh` also stores the identifiers of the release bot GitHub App as the
organization variables `BOT_APP_ID` and `BOT_CLIENT_ID` when they are given:

```sh
BOT_APP_ID=5414823 BOT_CLIENT_ID=Iv23... ./settings.sh
```

Last, `settings.sh` checks that every GitHub App of
`organization/installations.json` is installed on the organization for the
listed repositories and is not suspended, and that no other App is installed.
The permissions listed there are a ceiling: an App that holds a permission not
listed, or a higher level of one, is drift. A lower or missing permission is
not, so the check does not break when an App asks for less. An App that asks for
more needs the owner's approval on GitHub, and then a pull request that lists
the new permission. The check changes nothing and runs after every setting is
applied: it prints every difference and then fails.

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
([FY-0030][fy-0030]). No copy of the key is kept; a new released repository gets
it by a rotation, see [Release bot key](#release-bot-key).

Every job of `release` waits until a required reviewer approves it, so no
release, tag or release pull request is made without the owner, even when a
compromised app merges a pull request into `main`. The reviewers are the users
of `environments/release-reviewers.json`, by user ID; the login there is only
for readers. `apply.sh` replaces the reviewers of the environment with that
list. Self-review stays allowed: the owner merges the release pull requests, and
the run that the merge starts waits for their own approval.

Every repository that publishes container images, matched by a glob of
`environments/publish.json`, also gets the environment `publish`, deployable
from the same branches and with the reviewers of `release`. The jobs that push
an image to GHCR, attest it, tag it and write its release notes run in it, so no
image is published without the owner's approval of that run. It holds no secret:
publication uses `GITHUB_TOKEN`, and the bot key stays in `release`
([FY-0027][fy-0027]).

Admins cannot bypass the rules of `release`, `publish` and `cache`. A waiting
job starts only after a required reviewer approves it, and only on a deploy
branch, even for an organization owner. The owner still approves their runs as
the reviewer; they lose only the option to start a job without a review.

Every repository that pushes to the binary cache, matched by a glob of
`environments/cache.json`, gets the environment `cache`, deployable from the
same branches. The push token is the secret `CACHIX_AUTH_TOKEN` of that
environment ([FY-0009][fy-0009]). Images get no `cache`: their checks build the
image, whose paths are not pushed ([FY-0019][fy-0019]). Pass the token file the
same way:

```sh
CACHIX_AUTH_TOKEN_FILE=~/flakeyard-cachix.token ./apply.sh atom-shell
```

The environment `cache` has no reviewers, and `apply.sh` removes any that were
added by hand. Its push job runs on every push to `main`, and an approval of
each push would hold up every merge. The push token stays protected only by the
deploy branches, the risk that [FY-0019][fy-0019] accepts; a release still waits
for the reviewer of `release`.

## Release bot key

The private key of `flakeyard-bot` exists only as the secret `APP_PRIVATE_KEY`
of the environment `release`, and no copy is kept on the owner's machine. A
secret cannot be read back, so storing the key always means a new key, for a new
released repository, for the yearly rotation and after a leak alike:

1. On the App's page, in Settings → Developer settings → GitHub Apps, generate a
   new private key. The browser downloads it as a `.pem` file.
2. Store it in every released repository. Run `apply.sh` without arguments, so
   that no repository keeps the older key:

   ```sh
   BOT_PRIVATE_KEY_FILE=~/Downloads/flakeyard-bot.pem ./apply.sh
   ```

3. Delete the file.
4. On the App's page, delete every older key. Only the new one is left.

### Leaked key

When the key may have been exposed:

1. Delete the key on the App's page. No new token can be made with it; tokens
   made before expire within an hour.
2. Store a new key as above.
3. Run the [release audit](#release-audit) and look at every mismatch it
   reports.
4. Review every tag `v*` and every release created since the key may have been
   exposed, also those the audit passes. A tag `vX` must point to the commit of
   the newest genuine `vX.Y.Z`; the audit does not check it.
5. Delete each forged release and its tag, and move each forged `vX` back. Only
   the App may change tags `v*`, so turn off the ruleset `release-tags` of that
   repository for the change; the next `apply.sh` turns it back on. Never reuse
   the version of a forged release: consumers may have pinned it.
6. Publish a security advisory in every affected repository. It names the forged
   versions and their commits, the period of the exposure, and the versions to
   move to.

## Release audit

The workflow `audit` of this repository runs `audit/releases.sh` every Monday
and on dispatch. For every release `vX.Y.Z` of every non-archived repository, it
checks that `flakeyard-bot` made it, and that its tag points to the merge commit
of a release pull request ([FY-0007][fy-0007], [FY-0030][fy-0030]): one from the
branch `release-please--branches--<base>` of the same repository, merged into
`<base>`, which is `main` or `release/vN` with `N >= 1`, labelled
`autorelease: tagged`, and merged by a reviewer of the environment `release`
(`repository/environments/release-reviewers.json`). A key of the App can open,
label and merge such a pull request, but it merges as the App, so the last check
tells it from a release the owner merged. It reports every mismatch as an error
and then fails. A failed run is the alert; follow [Leaked key](#leaked-key).

The job reads with `GITHUB_TOKEN`, since every repository is public. It checks
the organization, not a commit, so it is not a check workflow: it posts no
commit status, and no ruleset requires it. It does not check tags `vX`, images
or releases that were deleted. To run it locally or for some repositories:

```sh
BOT_LOGIN='flakeyard-bot[bot]' ./audit/releases.sh atom-shell
```

## Tests

The tests run the scripts of `org/` against a stub of `gh` that answers from
fixtures and logs the calls, so they need neither a token nor the network:

```sh
../tests/run.sh
```

## Not covered

Some settings have no API or depend on external services. They are configured by
hand, by an organization owner:

- **Release GitHub App** ([FY-0030][fy-0030]). In Settings → Developer settings
  → GitHub Apps, create `flakeyard-bot` without a webhook, with the repository
  permissions of `organization/installations.json` and no organization
  permissions, installable only on this account. Install it on all repositories;
  `settings.sh` checks the installation. Record its identifiers with
  `BOT_APP_ID=... BOT_CLIENT_ID=... ./settings.sh`. It needs `workflows: write`
  because GitHub refuses the tag of a release made by an App without it, since
  the commits of every tag carry workflow files. A permission added to the App
  reaches the installation only after an owner accepts it in Settings → GitHub
  Apps → `flakeyard-bot`.
- **Private keys of the release App.** Generated on the App's page and stored as
  [Release bot key](#release-bot-key) says. Rotate the key once a year and at
  once when it may have been exposed.
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
  features in every repository, and a configuration attached to a repository
  would override them. In Settings → Code security → Configurations, keep no
  configuration: delete any that exists, even one attached to no repository.
  Attaching an enforced configuration takes one click and overrides `apply.sh`
  in every repository it is attached to.
- **Personal access token policy.** GitHub offers no API for it. In Settings →
  Personal access tokens, allow fine-grained tokens with administrator approval
  and a maximum lifetime of 90 days, and restrict classic tokens.

[mend-portal]: https://developer.mend.io/
[renovate-app]: https://github.com/apps/renovate
[fy-0007]:
  https://github.com/flakeyard/decisions/blob/main/docs/adr/records/0007-branching-and-releases.md
[fy-0009]:
  https://github.com/flakeyard/decisions/blob/main/docs/adr/records/0009-ci-on-runners.md
[fy-0011]:
  https://github.com/flakeyard/decisions/blob/main/docs/adr/records/0011-settings-as-code.md
[fy-0019]:
  https://github.com/flakeyard/decisions/blob/main/docs/adr/records/0019-binary-cache.md
[fy-0027]:
  https://github.com/flakeyard/decisions/blob/main/docs/adr/records/0027-publish-image.md
[fy-0029]:
  https://github.com/flakeyard/decisions/blob/main/docs/adr/records/0029-renovate-mend.md
[fy-0030]:
  https://github.com/flakeyard/decisions/blob/main/docs/adr/records/0030-actions-workflows-and-release-bot.md
[workflow-api]:
  https://docs.github.com/en/rest/actions/permissions#set-default-workflow-permissions-for-a-repository
