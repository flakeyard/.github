# Contributing

## Getting started

Each repository describes its own setup and checks in its README. Make sure
those checks pass locally before opening a pull request.

## Commits and pull requests

- Branch from `main` and open a pull request against `main`.
- Pull requests are squash-merged, so the **PR title** becomes the commit
  message and must follow
  [Conventional Commits](https://www.conventionalcommits.org/):
  `<type>(<scope>): <description>` with types `feat`, `fix`, `docs`, `style`,
  `refactor`, `perf`, `test`, `build`, `ci`, `chore`, `revert`.
- Mark breaking changes with `!` after the type and describe them in the PR
  body.
- Open an issue first for non-trivial changes.

## Security

Do not report vulnerabilities in public issues; see [SECURITY.md](SECURITY.md).
