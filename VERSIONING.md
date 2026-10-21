# Versioning

Every repository of flakeyard is released from `main` with
[semantic versioning](https://semver.org/). The reasons behind these rules are
recorded in [flakeyard/decisions](https://github.com/flakeyard/decisions).

## Public API

A breaking change of any of the following requires a new major version:

- **Atoms**: flake outputs, and names, types and defaults of module options.
- **Actions and reusable workflows**: inputs, outputs, secrets and required
  permissions.
- **Templates**: questions and their defaults, the layout of generated projects
  and the minimum Copier version.
- **Dev container image**: the tools it provides and its Nix configuration.

## Releases

- **Patch**: fixes without changes to the public API.
- **Minor**: backwards-compatible additions. Features that will be removed are
  deprecated first and emit a warning.
- **Major**: removals and incompatible changes. Every major release comes with a
  migration guide.

Each release is tagged `vX.Y.Z`; these tags and their releases are immutable.
The tag `vX` points to the latest release of major version `X`.

## Support

The latest minor release of the current major version is supported. The previous
major version receives security fixes for 6 months after the next major version
is released, see [SECURITY.md](SECURITY.md).
