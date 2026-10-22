# Contributing

## Getting started

Repositories are developed in the flakeyard dev container ([FY-0012][fy-0012]).
You need a container engine, git and an editor that supports
[Dev Containers](https://containers.dev/), or a plain `docker run`. Opening a
repository in the container loads its development shell through direnv; with Nix
on the host, `direnv` or `nix develop` give the same shell.

Until the first release of the image, each README lists the tools to install
instead.

Each repository's README lists its checks. They are the same commands CI runs,
usually `nix flake check`; make sure they pass before opening a pull request.

## Commits and pull requests

- Branch from `main` and open a pull request against `main`.
- Pull requests are squash-merged, so the **PR title** becomes the commit
  message and must follow
  [Conventional Commits](https://www.conventionalcommits.org/):
  `<type>(<scope>): <description>` with types `feat`, `fix`, `docs`, `refactor`,
  `perf`, `test`, `build`, `ci`, `chore`, `revert` ([FY-0007][fy-0007]).
- Mark breaking changes with `!` after the type and describe them in the PR
  body.
- Open an issue first for non-trivial changes.

## Security

Do not report vulnerabilities in public issues; see [SECURITY.md](SECURITY.md).

[fy-0007]:
  https://github.com/flakeyard/decisions/blob/main/docs/adr/records/0007-branching-and-releases.md
[fy-0012]:
  https://github.com/flakeyard/decisions/blob/main/docs/adr/records/0012-develop-in-container.md
