{
  description = ".github: the checks of this repository, which come only from atoms.";

  inputs = {
    nixpkgs.url = "git+https://github.com/NixOS/nixpkgs?ref=nixos-26.05&rev=f1e5c356f35d07e7b71a6b5e6c9338e0b029e0c0&shallow=1";
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
      url = "git+https://github.com/flakeyard/atom-data-formats?ref=v0&rev=0c643933ae631061f9fb6f1f26cf556db689f011&shallow=1";
      inputs.treefmt-nix.follows = "treefmt-nix";
      inputs.git-hooks.follows = "git-hooks";
    };
    atom-markdown = {
      url = "git+https://github.com/flakeyard/atom-markdown?ref=v0&rev=0d3bca6f2fee47de01ecbe2ce1e49c0219870988&shallow=1";
      inputs.treefmt-nix.follows = "treefmt-nix";
      inputs.git-hooks.follows = "git-hooks";
    };
    atom-nix = {
      url = "git+https://github.com/flakeyard/atom-nix?ref=v0&rev=1ed903c4516d57313ab09415d3990834dbfd4495&shallow=1";
      inputs.treefmt-nix.follows = "treefmt-nix";
      inputs.git-hooks.follows = "git-hooks";
    };
    atom-shell = {
      url = "git+https://github.com/flakeyard/atom-shell?ref=v0&rev=1ccc313cdbc71333cd8117c72996dc40eecd2889&shallow=1";
      inputs.treefmt-nix.follows = "treefmt-nix";
      inputs.git-hooks.follows = "git-hooks";
    };
    atom-text = {
      url = "git+https://github.com/flakeyard/atom-text?ref=v0&rev=5d3eff102fc73979c01625325f07c13d2ea1a6c6&shallow=1";
      inputs.git-hooks.follows = "git-hooks";
    };
    atom-workflows = {
      url = "git+https://github.com/flakeyard/atom-workflows?ref=v0&rev=82957679afb098f2c36fbcc1ccdf5d52f3286ba4&shallow=1";
      inputs.git-hooks.follows = "git-hooks";
    };
    atom-workspace.url = "git+https://github.com/flakeyard/atom-workspace?ref=v0&rev=c84994b6c03a1edbd095cf98c7b9d90b0a324467&shallow=1";
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
