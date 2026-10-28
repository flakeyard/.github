# Versioning

Every repository of flakeyard that consumers pin is released from `main` with
[semantic versioning](https://semver.org/). `.github` and `flakeyard/decisions`
are not released. The reasons behind these rules are recorded in
[FY-0024][fy-0024].

Compatibility guarantees start at `v1.0.0`. Releases `0.y.z` are pre-releases
without guarantees or support.

## Public API

A breaking change of any of the following requires a new major version:

- **Atoms** ([FY-0017][fy-0017]):
  - their inputs and the names of those inputs;
  - `flakeModules` and the names of `apps`, `checks` and `devShells` they add;
  - the tools they enable, git hook ids and formatter names;
  - values they set whose change rewrites files or fails a project that passed
    before;
  - the files they read;
  - app names, arguments and environment variables;
  - supported systems and the oldest supported upstream revisions.
- **Actions and reusable workflows**: inputs, outputs, secrets, required
  permissions and the events and runners they support.
- **`action-setup-nix`** ([FY-0023][fy-0023]), in addition:
  - the Nix implementation and its version;
  - the settings it writes into `/etc/nix/nix.conf` and the validation rules of
    its inputs;
  - its failure on runners where Nix was installed before;
  - the effects later steps rely on: `nix` on `PATH`, a running daemon, the
    shell profiles and build users set up by the Nix installer.
- **Templates**: questions and their defaults, the layout of generated projects,
  the major versions of other flakeyard repositories they reference and the
  minimum Copier version.
- **Dev container image** ([FY-0005][fy-0005]):
  - the user `dev`, its home `/home/dev`, and `DEV_UID`/`DEV_GID`;
  - the behaviour of the entrypoint and the environment variables it sets;
  - the Nix settings and `/etc/nix/local.conf`;
  - the settings in its `devcontainer.metadata` label;
  - the tools it provides by name, and the Nix implementation with its minor
    version;
  - supported platforms, container engines and required capabilities.
- **Renovate preset**: preset names, and rules that change which updates are
  proposed, grouped or merged automatically.

Tool versions are not part of the API of atoms or of the image: atoms run the
tools from the project's nixpkgs, so a new warning after a nixpkgs update comes
from that update, not from an atom release.

The Nix of the image and of `action-setup-nix` is part of their API. A new patch
version of Nix is a patch release and a new minor version a minor release,
unless the release notes of Nix list incompatible changes; such an update, and a
change of the Nix implementation, is a major release.

## Releases

- **Patch**: fixes without changes to the public API.
- **Minor**: backwards-compatible additions and deprecations. A deprecated
  feature keeps working and warns: atoms during evaluation, actions and
  workflows with an annotation, the image on standard error, templates after
  `copier update`. A new check, hook or rule that could fail a passing project
  ships disabled and is enabled in the next major version.
- **Major**: removals and incompatible changes. Only features deprecated in the
  previous major version are removed. Every major release comes with a migration
  guide in its release notes.

Each release is tagged `vX.Y.Z`; these tags and their releases are immutable.
The tag `vX` points to the latest release of major version `X`.

## Support

The latest minor release of the current major version is supported; older minor
releases are not patched. The previous major version receives security fixes for
6 months after the next major version is released, see
[SECURITY.md](SECURITY.md).

[fy-0017]:
  https://github.com/flakeyard/decisions/blob/main/docs/adr/records/0017-atom-contract.md
[fy-0005]:
  https://github.com/flakeyard/decisions/blob/main/docs/adr/records/0005-dev-container-image.md
[fy-0023]:
  https://github.com/flakeyard/decisions/blob/main/docs/adr/records/0023-setup-nix.md
[fy-0024]:
  https://github.com/flakeyard/decisions/blob/main/docs/adr/records/0024-versioning-and-support.md
