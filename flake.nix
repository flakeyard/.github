{
  description = ".github: the checks of this repository, which come only from atoms.";

  inputs = {
    nixpkgs.url = "git+https://github.com/NixOS/nixpkgs?ref=nixos-26.05&rev=ac588ef1c914865dad517b337ea0eb9694a4021c&shallow=1";
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
    atom-nix = {
      url = "git+https://github.com/flakeyard/atom-nix?ref=v0&rev=d8e5b1d8f367d27181fbf6e2616c9e6c5ecbbafa&shallow=1";
      inputs.treefmt-nix.follows = "treefmt-nix";
      inputs.git-hooks.follows = "git-hooks";
    };
    atom-shell = {
      url = "git+https://github.com/flakeyard/atom-shell?ref=v0&rev=c6191ba89fd4b4be340cbddfc3fdbeb7f82d3cc5&shallow=1";
      inputs.treefmt-nix.follows = "treefmt-nix";
      inputs.git-hooks.follows = "git-hooks";
    };
    atom-workflows = {
      url = "git+https://github.com/flakeyard/atom-workflows?ref=v0&rev=82957679afb098f2c36fbcc1ccdf5d52f3286ba4&shallow=1";
      inputs.git-hooks.follows = "git-hooks";
    };
    atom-workspace.url = "git+https://github.com/flakeyard/atom-workspace?ref=v0&rev=53d4d101ec71025dbb19da3d423455e72e10198a&shallow=1";
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
        inputs.atom-nix.flakeModules.default
        inputs.atom-shell.flakeModules.default
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
