# flakeyard

Composable building blocks for Nix-based project templates.

- **Atoms** (`atom-*`): small, independent flake-parts modules, one concern each
  &mdash; formatting, linting, security checks, C++ toolchains, coverage,
  profiling and more.
- **Actions** (`action-*`): GitHub Actions for Nix-based CI, pinned by commit
  SHA.
- **Dev container**: a generic Nix + direnv image, so contributors do not need
  Nix on the host.
- **Templates** (`template-*`): [Copier](https://copier.readthedocs.io/)
  templates that compose atoms into ready-to-use projects.

> Status: work in progress.
