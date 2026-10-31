# Organization settings

Settings of the flakeyard organization and its repositories, kept as code.
GitHub Free has no organization-level rulesets, so repository-level settings are
applied to every repository by a script.

| Path                       | Applied by    | Scope                           |
| -------------------------- | ------------- | ------------------------------- |
| `organization/*.json`      | `settings.sh` | organization, Actions policies  |
| `repository/settings.json` | `apply.sh`    | merge, secret scanning          |
| `repository/labels.json`   | `apply.sh`    | issue and PR labels             |
| `repository/topics.json`   | `apply.sh`    | topics, matched by repo glob    |
| `repository/rulesets/`     | `apply.sh`    | `main`, `release/v*`, `v*` refs |

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

Run `apply.sh` for every new repository. It needs the ID of the release bot
GitHub App, either as `BOT_APP_ID` in the environment or as the organization
variable of the same name; only that app may create, move or delete `v*` tags.

Every released repository, all except `.github` and `decisions`, gets the
environment `release`, deployable only from `main` and `release/v*`. The bot's
private key is the secret `APP_PRIVATE_KEY` of that environment
([FY-0021][fy-0021]). Pass the key file to store it, for a new repository or
after a rotation:

```sh
BOT_PRIVATE_KEY_FILE=~/flakeyard-bot.pem ./apply.sh atom-shell
```

## Not covered

Some settings have no API or depend on external services. They are configured by
hand, by an organization owner:

- **Release GitHub App** ([FY-0021][fy-0021]). In Settings → Developer settings
  → GitHub Apps, create `flakeyard-bot` without a webhook, with the repository
  permissions listed in FY-0021 and no organization permissions, installable
  only on this account. Install it on all repositories. Record its identifiers
  with `BOT_APP_ID=... BOT_CLIENT_ID=... ./settings.sh`.
- **Private keys of the release App.** Generate a key on the App's page, store
  it with `BOT_PRIVATE_KEY_FILE=... ./apply.sh` and keep the file outside of any
  repository. Rotate it once a year and at once when it may have been exposed:
  generate a new key, store it in every released repository, then delete the old
  key on the App's page.
- **Renovate.** Install the Mend Renovate app on the organization for all
  repositories.
- **Binary cache** ([FY-0019][fy-0019]). Create the public Cachix cache
  `flakeyard` on the open source plan and a push token for it in the Cachix web
  interface. Store the token as a secret of the environment that FY-0009
  restricts to `main` and `release/v*`.
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

[fy-0011]:
  https://github.com/flakeyard/decisions/blob/main/docs/adr/records/0011-settings-as-code.md
[fy-0019]:
  https://github.com/flakeyard/decisions/blob/main/docs/adr/records/0019-binary-cache.md
[fy-0021]:
  https://github.com/flakeyard/decisions/blob/main/docs/adr/records/0021-release-bot.md
