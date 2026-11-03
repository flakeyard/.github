# .github

[![OpenSSF Scorecard][scorecard-badge]][scorecard-viewer]

Organization-wide defaults for [flakeyard](https://github.com/flakeyard):

- Community health files (`CODE_OF_CONDUCT.md`, `CONTRIBUTING.md`,
  `SECURITY.md`, `SUPPORT.md`, issue, pull request and vulnerability report
  templates) used by every repository that does not define its own.
- The organization profile, `profile/README.md`.
- Organization and repository settings as code, see [org/](org/README.md).

## CI

[`test.yaml`](.github/workflows/test.yaml) runs the tests of `org/`
(`tests/run.sh`) and then calls [workflow-check][workflow-check], which checks
pull request titles, `renovate.json` and the immutable release behind its preset
tag ([FY-0031][fy-0031]). The repository has no flake, so no flake checks are
built. [`scorecard.yaml`](.github/workflows/scorecard.yaml) runs OpenSSF
Scorecard through [workflow-scorecard][workflow-scorecard].

## Bootstrap

This repository is bootstrapped under [FY-0022][fy-0022]. Until the providers of
its remaining checks are released:

- actionlint, zizmor, shellcheck, shfmt, Prettier, markdownlint, typos and
  `reuse lint` run locally before every pull request (provider: the atoms);
- rulesets require no status checks until every repository has adopted
  workflow-check.

## License

[MIT](LICENSE), except `CODE_OF_CONDUCT.md`, which is adapted from the
Contributor Covenant under [CC-BY-4.0](LICENSES/CC-BY-4.0.txt). Licensing of
every file is declared in [REUSE.toml](REUSE.toml).

[fy-0022]:
  https://github.com/flakeyard/decisions/blob/main/docs/adr/records/0022-bootstrap.md
[fy-0031]:
  https://github.com/flakeyard/decisions/blob/main/docs/adr/records/0031-check-pull-requests-and-pushes-with-workflow-check.md
[workflow-check]: https://github.com/flakeyard/workflow-check
[workflow-scorecard]: https://github.com/flakeyard/workflow-scorecard
[scorecard-badge]:
  https://api.scorecard.dev/projects/github.com/flakeyard/.github/badge
[scorecard-viewer]:
  https://scorecard.dev/viewer/?uri=github.com/flakeyard/.github
