{
  inputs = {
    nixpkgs.url = "github:nixos/nixpkgs/nixos-unstable";
    flake-parts = {
      url = "github:hercules-ci/flake-parts";
      inputs.nixpkgs-lib.follows = "nixpkgs";
    };
    rust-toolchains = {
      url = "github:giodamelio/rust-toolchains";
      inputs.nixpkgs.follows = "nixpkgs";
    };
  };

  outputs = inputs @ {
    flake-parts,
    rust-toolchains,
    ...
  }:
    flake-parts.lib.mkFlake {inherit inputs;} {
      imports = [rust-toolchains.flakeModules.default];

      systems = ["x86_64-linux" "aarch64-linux" "aarch64-darwin"];

      perSystem = {pkgs, ...}: {
        rust-toolchains.channel = "stable";

        # Built with nixpkgs' rustc: kache never runs in the sandbox, and this
        # keeps the package buildable without rust-toolchains.
        packages.default = pkgs.rustPlatform.buildRustPackage {
          pname = "rust-project";
          version = "0.1.0";
          src = ./.;
          cargoLock.lockFile = ./Cargo.lock;
        };
      };
    };
}
