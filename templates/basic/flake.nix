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

      perSystem = {config, ...}: {
        rust-toolchains.channel = "stable";

        packages.default = config.rust-toolchains.rustPlatform.buildRustPackage {
          pname = "rust-project";
          version = "0.1.0";
          src = ./.;
          cargoLock.lockFile = ./Cargo.lock;
        };
      };
    };
}
