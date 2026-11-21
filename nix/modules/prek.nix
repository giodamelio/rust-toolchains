{modules, ...}: {
  lib,
  flake-parts-lib,
  ...
}: {
  imports = [modules.toolchain modules.test-runner modules.devshell];

  options.perSystem = flake-parts-lib.mkPerSystemOption ({
    config,
    pkgs,
    ...
  }: let
    cfg = config.rust-toolchains.prek;
    prekLib = import ../lib/prek.nix {inherit lib pkgs;};

    withToolchain = name: text:
      lib.getExe (pkgs.writeShellApplication {
        inherit name text;
        runtimeInputs = [config.rust-toolchains.toolchain];
      });
  in {
    options.rust-toolchains.prek = {
      enable = lib.mkOption {
        type = lib.types.bool;
        default = true;
        description = "Whether entering the devshell links prek.toml and installs the git hooks.";
      };
      hooks = lib.mkOption {
        type = lib.types.attrsOf (lib.types.submodule {
          freeformType = (pkgs.formats.toml {}).type;
          options.enable = lib.mkOption {
            type = lib.types.bool;
            default = true;
            description = "Whether to include this hook in prek.toml.";
          };
        });
        description = "Local prek hooks, keyed by hook id. Other attributes are written to prek.toml as-is.";
      };
      allHooksInPreCommit = lib.mkOption {
        type = lib.types.bool;
        default = false;
        description = ''
          Whether every pre-push hook also runs in the pre-commit stage, so `prek run --all-files` runs them all.
          Useful in jj repos, where git hooks never fire and a push alias runs the pre-commit stage by hand.
        '';
      };
      configFile = lib.mkOption {
        type = lib.types.package;
        readOnly = true;
        description = "The generated prek.toml.";
      };
    };

    config = {
      # Hook commands and flags adapted from git-hooks.nix (modules/hooks.nix).
      # Thanks to the cachix/git-hooks.nix project: https://github.com/cachix/git-hooks.nix
      rust-toolchains.prek.hooks = {
        inherit (prekLib.hooks) alejandra;
        rustfmt = {
          name = "rustfmt";
          entry = withToolchain "prek-rustfmt" "cargo fmt --check";
          language = "system";
          files = "\\.rs$";
          pass_filenames = false;
          stages = ["pre-commit" "pre-push"];
          priority = 0;
        };
        clippy = {
          name = "clippy";
          entry = withToolchain "prek-clippy" "cargo clippy --offline --all-targets -- -D warnings";
          language = "system";
          files = "\\.rs$";
          pass_filenames = false;
          stages = ["pre-commit" "pre-push"];
          priority = 1;
        };
        test = {
          name = "test";
          entry = lib.getExe config.rust-toolchains.testRunner;
          language = "system";
          pass_filenames = false;
          always_run = true;
          stages = ["pre-push"];
          priority = 2;
        };
      };

      rust-toolchains.prek.configFile = prekLib.mkConfig (
        lib.mapAttrsToList
        (id: hook:
          {inherit id;}
          // builtins.removeAttrs hook ["enable"]
          // lib.optionalAttrs (cfg.allHooksInPreCommit && lib.elem "pre-push" (hook.stages or []) && !lib.elem "pre-commit" hook.stages) {
            stages = ["pre-commit"] ++ hook.stages;
          })
        (lib.filterAttrs (_: hook: hook.enable) cfg.hooks)
      );

      rust-toolchains.devShell.shellHook = lib.mkIf cfg.enable (prekLib.mkShellHook cfg.configFile);
    };
  });
}
