# .github

Organization-wide defaults for [flakeyard](https://github.com/flakeyard):

- Community health files (`CODE_OF_CONDUCT.md`, `CONTRIBUTING.md`,
  `SECURITY.md`, `SUPPORT.md`, issue, pull request and vulnerability report
  templates) used by every repository that does not define its own.
- The organization profile, `profile/README.md`.
- Organization and repository settings as code, see [org/](org/README.md).

## Bootstrap

This repository is bootstrapped under [FY-0022][fy-0022]. It has no CI checks
yet. Until their providers are released:

- shellcheck, shfmt, Prettier, markdownlint, typos and `reuse lint` run locally
  before every pull request (provider: `workflow-check` and the atoms);
- pull request titles are checked by the reviewer (provider: `workflow-check`);
- rulesets require no status checks (provider: `workflow-check`);
- OpenSSF Scorecard is not run (provider: `workflow-check`).

## License

[MIT](LICENSE), except `CODE_OF_CONDUCT.md`, which is adapted from the
Contributor Covenant under [CC-BY-4.0](LICENSES/CC-BY-4.0.txt). Licensing of
every file is declared in [REUSE.toml](REUSE.toml).

[fy-0022]:
  https://github.com/flakeyard/decisions/blob/main/docs/adr/records/0022-bootstrap.md
