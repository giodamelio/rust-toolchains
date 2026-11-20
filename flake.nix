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

    # Built from pkgs.formats.toml rather than treefmt-nix, which would become
    # an input of every downstream lock.
    mkTreefmt = system: let
      pkgs = nixpkgs.legacyPackages.${system};
      inherit (pkgs) lib;
      config = (pkgs.formats.toml {}).generate "treefmt.toml" {
        excludes = ["flake.lock" "tests/flake.lock" "prek.toml" "result"];
        formatter = {
          alejandra = {
            command = lib.getExe pkgs.alejandra;
            includes = ["*.nix"];
          };
          # treefmt hands rustfmt bare files, so the edition Cargo.toml would
          # supply has to be passed explicitly.
          rustfmt = {
            command = lib.getExe' self.packages.${system}.stable "rustfmt";
            options = ["--edition" "2024"];
            includes = ["*.rs"];
          };
          # gfm keeps tables and other GitHub syntax intact; --number keeps
          # ordered lists as 1. 2. 3. instead of rewriting them all to 1.
          mdformat = {
            command = lib.getExe (pkgs.mdformat.withPlugins (p: [p.mdformat-gfm]));
            options = ["--number"];
            includes = ["*.md"];
          };
        };
      };
    in
      pkgs.writeShellApplication {
        name = "treefmt";
        text = ''exec ${lib.getExe pkgs.treefmt} --config-file ${config} "$@"'';
      };
  in {
    # Stable follows fenix as locked in this repo's flake.lock, so bumping it is
    # `nix flake update fenix`. Nightly is pinned by date in nightly.json.
    packages = eachSystem (system: let
      fenixPkgs = fenix.packages.${system};
    in {
      stable = fenixPkgs.stable.withComponents components;
      nightly = (fenixPkgs.fromManifestFile nightlyManifest).withComponents components;
    });

    formatter = eachSystem mkTreefmt;

    devShells = eachSystem (system: let
      pkgs = nixpkgs.legacyPackages.${system};
      prekLib = import ./nix/lib/prek.nix {inherit (pkgs) lib pkgs;};
      treefmt = self.formatter.${system};
    in {
      default = pkgs.mkShell {
        packages = [
          pkgs.alejandra
          treefmt
          pkgs.prek
          (import ./nix/bump-nightly.nix {inherit pkgs components systems;})
        ];
        shellHook =
          prekLib.mkShellHook (prekLib.mkConfig [
            {
              id = "treefmt";
              name = "treefmt";
              entry = "${pkgs.lib.getExe treefmt} --fail-on-change";
              language = "system";
              files = "\\.(nix|rs|md)$";
              stages = ["pre-commit" "pre-push"];
              priority = 0;
            }
          ])
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
                command = "nix fmt";
                description = "Format Nix, Rust and Markdown with treefmt";
              }
              {
                command = "prek run --all-files";
                description = "Check formatting with treefmt";
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
