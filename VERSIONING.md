# Versioning

Every repository of flakeyard is released from `main` with
[semantic versioning](https://semver.org/). The reasons behind these rules are
recorded in [flakeyard/decisions](https://github.com/flakeyard/decisions).

## Public API

A breaking change of any of the following requires a new major version:

- **Atoms** ([FY-0004][fy-0004]):
  - their inputs and the names of those inputs;
  - `flakeModules` and the names of `apps`, `checks` and `devShells` they add;
  - the tools they enable, git hook ids and formatter names;
  - values they set whose change rewrites files or fails a project that passed
    before;
  - the files they read;
  - app names, arguments and environment variables;
  - supported systems and the oldest supported upstream revisions.
- **Actions and reusable workflows**: inputs, outputs, secrets and required
  permissions.
- **Templates**: questions and their defaults, the layout of generated projects
  and the minimum Copier version.
- **Dev container image** ([FY-0005][fy-0005]):
  - the user `dev`, its home `/home/dev`, and `DEV_UID`/`DEV_GID`;
  - the behaviour of the entrypoint and the environment variables it sets;
  - the Nix settings and `/etc/nix/local.conf`;
  - the settings in its `devcontainer.metadata` label;
  - the tools it provides by name, and the Nix implementation with its minor
    version;
  - supported platforms, container engines and required capabilities.

Tool versions are not part of the API of atoms or of the image, except for the
image's Nix: atoms run the tools from the project's nixpkgs, so a new warning
after a nixpkgs update comes from that update, not from an atom release.

## Releases

- **Patch**: fixes without changes to the public API.
- **Minor**: backwards-compatible additions. Features that will be removed are
  deprecated first and emit a warning. A new atom check that could fail a
  passing project ships disabled and is enabled in the next major version.
- **Major**: removals and incompatible changes. Every major release comes with a
  migration guide.

Each release is tagged `vX.Y.Z`; these tags and their releases are immutable.
The tag `vX` points to the latest release of major version `X`.

## Support

The latest minor release of the current major version is supported. The previous
major version receives security fixes for 6 months after the next major version
is released, see [SECURITY.md](SECURITY.md).

[fy-0004]:
  https://github.com/flakeyard/decisions/blob/main/docs/adr/records/0004-atom-contract.md
[fy-0005]:
  https://github.com/flakeyard/decisions/blob/main/docs/adr/records/0005-dev-container-image.md
