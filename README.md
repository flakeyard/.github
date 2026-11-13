# .github

[![OpenSSF Scorecard][scorecard-badge]][scorecard-viewer]

Organization-wide defaults for [flakeyard](https://github.com/flakeyard):

- Community health files (`CODE_OF_CONDUCT.md`, `CONTRIBUTING.md`,
  `SECURITY.md`, `SUPPORT.md`, issue, pull request and vulnerability report
  templates) used by every repository that does not define its own.
- The organization profile, `profile/README.md`.
- Organization and repository settings as code, see [org/](org/README.md).

## Development

Open the repository in its dev container,
[`.devcontainer/devcontainer.json`](.devcontainer/devcontainer.json), with
"Reopen in Container" in VS Code or `devcontainer up --workspace-folder .`. The
checks of [CI](#ci) and [Bootstrap](#bootstrap), such as `tests/run.sh`, run in
it as in CI; tools that the image does not have come from nixpkgs, such as
`nix run nixpkgs#prettier`. Nix on the host works as well.

## CI

[`test.yaml`](.github/workflows/test.yaml) runs the tests of `org/`
(`tests/run.sh`) and then calls [workflow-check][workflow-check], which checks
`flake.lock`, pull request titles, `renovate.json` and the immutable release
behind its preset tag ([workflow-check ADR-0001][workflow-check-adr-0001]), and
builds the checks of the root [`flake.nix`](flake.nix), which only imports atoms
([FY-0038][fy-0038]): [atom-workflows][atom-workflows] lints the workflows with
actionlint and zizmor (`checks.workflows`). Run them with `nix flake check`. The
weekly run of `test.yaml` also checks the end of life of the nixpkgs branch in
`flake.lock` ([FY-0036][fy-0036]).
[`scorecard.yaml`](.github/workflows/scorecard.yaml) runs OpenSSF Scorecard
through [workflow-scorecard][workflow-scorecard].
[`audit.yaml`](.github/workflows/audit.yaml) audits the releases of every
repository each week, see [org/](org/README.md#release-audit).

## Bootstrap

This repository is bootstrapped under [FY-0022][fy-0022]. Until the providers of
its remaining checks are released:

- shellcheck, shfmt, Prettier, markdownlint, typos and `reuse lint` run locally
  before every pull request (provider: the atoms).

## License

[MIT](LICENSE), except `CODE_OF_CONDUCT.md`, which is adapted from the
Contributor Covenant under [CC-BY-4.0](LICENSES/CC-BY-4.0.txt). Licensing of
every file is declared in [REUSE.toml](REUSE.toml).

[atom-workflows]: https://github.com/flakeyard/atom-workflows
[fy-0022]:
  https://github.com/flakeyard/decisions/blob/main/docs/adr/records/0022-bootstrap.md
[fy-0036]:
  https://github.com/flakeyard/decisions/blob/main/docs/adr/records/0036-check-the-end-of-life-of-nixpkgs-in-flake-lock.md
[fy-0038]:
  https://github.com/flakeyard/decisions/blob/main/docs/adr/records/0038-roll-out-the-atoms.md
[workflow-check-adr-0001]:
  https://github.com/flakeyard/workflow-check/blob/main/docs/adr/records/0001-check-pull-requests-and-pushes.md
[workflow-check]: https://github.com/flakeyard/workflow-check
[workflow-scorecard]: https://github.com/flakeyard/workflow-scorecard
[scorecard-badge]:
  https://api.scorecard.dev/projects/github.com/flakeyard/.github/badge
[scorecard-viewer]:
  https://scorecard.dev/viewer/?uri=github.com/flakeyard/.github
