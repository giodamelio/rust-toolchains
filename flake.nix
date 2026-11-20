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
    manifests = {
      stable = builtins.fetchurl {
        url = "https://static.rust-lang.org/dist/channel-rust-1.100.0.toml";
        sha256 = "sha256-MFHoWVcPZKjFrLnQnodCXbUsfZcofGfo9tV9fTTvklg=";
      };
      nightly = builtins.fetchurl {
        url = "https://static.rust-lang.org/dist/2026-11-19/channel-rust-nightly.toml";
        sha256 = "sha256-nBrsF+c8Q9+bCrAG0wYnRTAWHKu61G29wlPdDGA9zIU=";
      };
    };

    components = ["rustc" "cargo" "clippy" "rustfmt" "rust-src" "rust-analyzer"];
  in {
    packages = eachSystem (system:
      builtins.mapAttrs
      (_: manifest: (fenix.packages.${system}.fromManifestFile manifest).withComponents components)
      manifests);

    formatter = eachSystem (system: nixpkgs.legacyPackages.${system}.alejandra);

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
