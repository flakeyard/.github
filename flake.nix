{
  description = ".github: the checks of this repository, which come only from atoms.";

  inputs = {
    nixpkgs.url = "git+https://github.com/NixOS/nixpkgs?ref=nixos-26.05&rev=0dc498bfe49baeb18b0f9891e800b53bb2603193&shallow=1";
    flake-parts = {
      url = "git+https://github.com/hercules-ci/flake-parts?ref=main&rev=ea2630b7470978622c7689a1ff75d2b389175399&shallow=1";
      inputs.nixpkgs-lib.follows = "nixpkgs";
    };
    git-hooks = {
      url = "git+https://github.com/cachix/git-hooks.nix?ref=master&rev=204b6977e00caac19e2313015a598543ca7be150&shallow=1";
      inputs.nixpkgs.follows = "nixpkgs";
    };
    treefmt-nix = {
      url = "git+https://github.com/numtide/treefmt-nix?ref=main&rev=0d6d739a833ba9a9c93034862e4a7b061a062a1c&shallow=1";
      inputs.nixpkgs.follows = "nixpkgs";
    };
    atom-data-formats = {
      url = "git+https://github.com/flakeyard/atom-data-formats?ref=v0&rev=933cbb3ff234825dd19a55c91a1bb279ea2682cb&shallow=1";
      inputs.treefmt-nix.follows = "treefmt-nix";
      inputs.git-hooks.follows = "git-hooks";
    };
    atom-markdown = {
      url = "git+https://github.com/flakeyard/atom-markdown?ref=v0&rev=90a9dc7b59521c187fabd6662205b88e712d088d&shallow=1";
      inputs.treefmt-nix.follows = "treefmt-nix";
      inputs.git-hooks.follows = "git-hooks";
    };
    atom-nix = {
      url = "git+https://github.com/flakeyard/atom-nix?ref=v0&rev=c591b0716c9fe3f16074637e63ee9128e602ee6a&shallow=1";
      inputs.treefmt-nix.follows = "treefmt-nix";
      inputs.git-hooks.follows = "git-hooks";
    };
    atom-shell = {
      url = "git+https://github.com/flakeyard/atom-shell?ref=v0&rev=912d34e8313d5d300c49c6484466bbcb396aab46&shallow=1";
      inputs.treefmt-nix.follows = "treefmt-nix";
      inputs.git-hooks.follows = "git-hooks";
    };
    atom-text = {
      url = "git+https://github.com/flakeyard/atom-text?ref=v0&rev=68467987a5d8db04681d587ffaa2d9aa755a4f62&shallow=1";
      inputs.git-hooks.follows = "git-hooks";
    };
    atom-workflows = {
      url = "git+https://github.com/flakeyard/atom-workflows?ref=v0&rev=5eeed2dd0411ebdd186d37bc401712edc5069aa1&shallow=1";
      inputs.git-hooks.follows = "git-hooks";
    };
    atom-workspace.url = "git+https://github.com/flakeyard/atom-workspace?ref=v0&rev=19b05dd722aa405c6110364ca60438d94855d1fe&shallow=1";
  };

  outputs =
    inputs:
    inputs.flake-parts.lib.mkFlake { inherit inputs; } {
      systems = [
        "x86_64-linux"
        "aarch64-linux"
      ];
      # The flake only imports atoms (FY-0038).
      imports = [
        inputs.atom-data-formats.flakeModules.default
        inputs.atom-markdown.flakeModules.default
        inputs.atom-nix.flakeModules.default
        inputs.atom-shell.flakeModules.default
        inputs.atom-text.flakeModules.default
        inputs.atom-workflows.flakeModules.default
        inputs.atom-workspace.flakeModules.default
      ];
      # The tools that tests/run.sh needs and no atom provides yet;
      # atom-workspace joins them into devShells.default.
      perSystem =
        { pkgs, ... }:
        {
          devShells.flakeyard-project = pkgs.mkShellNoCC {
            packages = with pkgs; [
              jq
            ];
          };
        };
    };
}
