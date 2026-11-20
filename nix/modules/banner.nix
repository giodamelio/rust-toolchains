{modules, ...}: {
  lib,
  flake-parts-lib,
  self,
  ...
}: {
  imports = [modules.devshell];

  options.perSystem = flake-parts-lib.mkPerSystemOption ({
    config,
    options,
    pkgs,
    ...
  }: let
    cfg = config.rust-toolchains.banner;
    cargoToml = self + "/Cargo.toml";
    enabled = name: options.rust-toolchains ? ${name} && config.rust-toolchains.${name}.enable;
  in {
    options.rust-toolchains.banner = {
      enable = lib.mkOption {
        type = lib.types.bool;
        default = true;
        description = "Whether entering the devshell prints a box of useful commands.";
      };
      title = lib.mkOption {
        type = lib.types.str;
        default =
          (builtins.fromTOML (builtins.readFile cargoToml)).package.name
          or (throw "rust-toolchains.banner.title: Cargo.toml has no package.name, so set the title yourself");
        defaultText = lib.literalMD "`package.name` from `Cargo.toml`";
        description = "Title of the banner box.";
      };
      commands = lib.mkOption {
        type = lib.types.listOf (lib.types.submodule {
          options = {
            command = lib.mkOption {type = lib.types.str;};
            description = lib.mkOption {type = lib.types.str;};
          };
        });
        description = "Commands listed in the banner. Definitions from several modules are concatenated.";
      };
    };

    config = {
      rust-toolchains.banner.commands =
        [
          {
            command = "cargo run";
            description = "Build and run";
          }
          {
            command = "cargo-test-auto";
            description = "Run tests (nextest if .config/nextest.toml exists)";
          }
        ]
        ++ lib.optionals (enabled "prek") [
          {
            command = "prek run --all-files";
            description = "Run rustfmt, clippy and alejandra";
          }
          {
            command = "prek run --all-files --hook-stage pre-push";
            description = "Run the pre-commit hooks plus tests";
          }
        ]
        ++ lib.optional (enabled "jjFix") {
          command = "jj fix";
          description = "Format changed Rust and Nix files";
        }
        ++ lib.optional (enabled "checks") {
          command = "nix flake check";
          description = "Build, lint and test in the Nix sandbox";
        }
        ++ [
          {
            command = "nix flake update rust-toolchains";
            description = "Pick up a newer pinned toolchain and tooling";
          }
        ];

      rust-toolchains.devShell.shellHook = lib.mkIf cfg.enable (lib.mkAfter (
        import ../lib/banner.nix {inherit lib pkgs;} {inherit (cfg) title commands;}
      ));
    };
  });
}
