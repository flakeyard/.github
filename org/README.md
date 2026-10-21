# Organization settings

Settings of the flakeyard organization and its repositories, kept as code.
GitHub Free has no organization-level rulesets, so repository-level settings are
applied to every repository by a script.

| Path                       | Applied by    | Scope                          |
| -------------------------- | ------------- | ------------------------------ |
| `organization/*.json`      | `settings.sh` | organization, Actions policies |
| `repository/settings.json` | `apply.sh`    | merge, secret scanning         |
| `repository/labels.json`   | `apply.sh`    | issue and PR labels            |
| `repository/topics.json`   | `apply.sh`    | topics, matched by repo glob   |
| `repository/rulesets/`     | `apply.sh`    | `main` (signed) and `v*` tags  |

## Usage

Both scripts need [gh](https://cli.github.com/) and [jq](https://jqlang.org/),
and are safe to run repeatedly.

```sh
gh auth refresh -h github.com -s admin:org  # once, for settings.sh
./settings.sh                               # organization settings
./apply.sh                                  # all repositories
./apply.sh atom-lint                        # a single repository
```

`apply.sh` also enables Dependabot alerts, private vulnerability reporting and
immutable releases in every repository, CodeQL default setup in `atom-*` and
`action-*`, and Discussions in `.github`, which serve the whole organization.

Run `apply.sh` for every new repository. It needs the ID of the release bot
GitHub App, either as `BOT_APP_ID` in the environment or as the organization
variable of the same name; only that app may create, move or delete `v*` tags.

## Not covered

Some settings have no API or depend on external services and are configured in
the web UI:

- GitHub App for releases (`BOT_APP_ID`, `BOT_PRIVATE_KEY`).
- Renovate installation (Mend) and binary cache tokens.
- Visibility and Actions access of container packages (GHCR), available only
  after the first push.
- Code security configurations.
