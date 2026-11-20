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
    manifests =
      builtins.mapAttrs
      (_: pin: builtins.fetchurl {inherit (pin) url sha256;})
      (builtins.fromJSON (builtins.readFile ./toolchains.json));

    components = ["rustc" "cargo" "clippy" "rustfmt" "rust-src" "rust-analyzer"];
  in {
    packages = eachSystem (system:
      builtins.mapAttrs
      (_: manifest: (fenix.packages.${system}.fromManifestFile manifest).withComponents components)
      manifests);

    formatter = eachSystem (system: nixpkgs.legacyPackages.${system}.alejandra);

    devShells = eachSystem (system: let
      pkgs = nixpkgs.legacyPackages.${system};
      prekLib = import ./nix/lib/prek.nix {inherit (pkgs) lib pkgs;};
    in {
      default = pkgs.mkShell {
        packages = [
          pkgs.alejandra
          pkgs.prek
          (import ./nix/bump-toolchain.nix {inherit pkgs components systems;})
        ];
        shellHook = prekLib.mkShellHook (prekLib.mkConfig [({id = "alejandra";} // prekLib.hooks.alejandra)]);
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
