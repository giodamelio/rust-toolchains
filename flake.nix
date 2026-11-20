{
  description = "Pinned Rust toolchains shared across projects so kache hits across them";

  inputs = {
    nixpkgs.url = "github:nixos/nixpkgs/nixos-unstable";
    fenix = {
      url = "github:nix-community/fenix";
      inputs.nixpkgs.follows = "nixpkgs";
    };
  };

  outputs = {
    self,
    nixpkgs,
    fenix,
  }: let
    systems = ["x86_64-linux" "aarch64-linux" "aarch64-darwin"];
    eachSystem = nixpkgs.lib.genAttrs systems;

    # Fetched at eval time rather than through toolchainOf, whose pkgs.fetchurl
    # would make other systems' outputs depend on import-from-derivation.
    nightlyManifest = let
      pin = builtins.fromJSON (builtins.readFile ./nightly.json);
    in
      builtins.fetchurl {inherit (pin) url sha256;};

    components = ["rustc" "cargo" "clippy" "rustfmt" "rust-src" "rust-analyzer"];
  in {
    # Stable follows fenix as locked in this repo's flake.lock, so bumping it is
    # `nix flake update fenix`. Nightly is pinned by date in nightly.json.
    packages = eachSystem (system: let
      fenixPkgs = fenix.packages.${system};
    in {
      stable = fenixPkgs.stable.withComponents components;
      nightly = (fenixPkgs.fromManifestFile nightlyManifest).withComponents components;
    });

    formatter = eachSystem (system: nixpkgs.legacyPackages.${system}.alejandra);

    devShells = eachSystem (system: let
      pkgs = nixpkgs.legacyPackages.${system};
      prekLib = import ./nix/lib/prek.nix {inherit (pkgs) lib pkgs;};
    in {
      default = pkgs.mkShell {
        packages = [
          pkgs.alejandra
          pkgs.prek
          (import ./nix/bump-nightly.nix {inherit pkgs components systems;})
        ];
        shellHook =
          prekLib.mkShellHook (prekLib.mkConfig [({id = "alejandra";} // prekLib.hooks.alejandra)])
          + import ./nix/lib/banner.nix {inherit (pkgs) lib pkgs;} {
            title = "rust-toolchains";
            commands = [
              {
                command = "nix flake update fenix";
                description = "Bump stable to fenix's latest";
              }
              {
                command = "bump-nightly [YYYY-MM-DD]";
                description = "Bump the nightly pin in nightly.json";
              }
              {
                command = "prek run --all-files";
                description = "Run alejandra";
              }
              {
                command = "nix flake check --all-systems";
                description = "Evaluate every output on every system";
              }
            ];
          };
      };
    });

    flakeModules = import ./nix/modules {inherit self;};

    templates = {
      default = self.templates.basic;
      basic = {
        path = ./templates/basic;
        description = "Rust binary using the pinned rust-toolchains toolchain, flake-parts and prek hooks";
      };
    };
  };
}
