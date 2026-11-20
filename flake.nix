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
      pkgs = nixpkgs.legacyPackages.${system};
    in {
      stable = fenixPkgs.stable.withComponents components;
      nightly = (fenixPkgs.fromManifestFile nightlyManifest).withComponents components;
      skills-cli = pkgs.callPackage ./nix/packages/skills-cli.nix {};
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
          (import ./nix/bump-skills-cli.nix {inherit pkgs;})
          self.packages.${system}.skills-cli
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
                command = "bump-skills-cli [--version X]";
                description = "Bump skills-cli to its latest release";
              }
              {
                command = "prek run --all-files";
                description = "Run alejandra";
              }
              {
                command = "nix flake check --all-systems";
                description = "Evaluate every output on every system";
              }
              {
                command = "nix flake check 'path:.?dir=tests'";
                description = "Build and check the template against this checkout";
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
