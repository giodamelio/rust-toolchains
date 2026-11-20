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
    toml = pkgs.formats.toml {};

    withToolchain = name: text:
      lib.getExe (pkgs.writeShellApplication {
        inherit name text;
        runtimeInputs = [config.rust-toolchains.toolchain];
      });

    hooks =
      lib.mapAttrsToList
      (id: hook: {inherit id;} // builtins.removeAttrs hook ["enable"])
      (lib.filterAttrs (_: hook: hook.enable) cfg.hooks);
  in {
    options.rust-toolchains.prek = {
      enable = lib.mkOption {
        type = lib.types.bool;
        default = true;
        description = "Whether entering the devshell links prek.toml and installs the git hooks.";
      };
      hooks = lib.mkOption {
        type = lib.types.attrsOf (lib.types.submodule {
          freeformType = toml.type;
          options.enable = lib.mkOption {
            type = lib.types.bool;
            default = true;
            description = "Whether to include this hook in prek.toml.";
          };
        });
        description = "Local prek hooks, keyed by hook id. Other attributes are written to prek.toml as-is.";
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
        alejandra = {
          name = "alejandra";
          entry = "${lib.getExe pkgs.alejandra} --check";
          language = "system";
          files = "\\.nix$";
          stages = ["pre-commit" "pre-push"];
          priority = 0;
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

      rust-toolchains.prek.configFile = toml.generate "prek.toml" {
        default_install_hook_types = ["pre-commit" "pre-push"];
        repos = [
          {
            repo = "local";
            inherit hooks;
          }
        ];
      };

      rust-toolchains.devShell = lib.mkIf cfg.enable {
        packages = [pkgs.prek];
        shellHook = ''
          if root=$(${lib.getExe pkgs.git} rev-parse --show-toplevel 2>/dev/null); then
            if [ -e "$root/prek.toml" ] && [ ! -L "$root/prek.toml" ]; then
              echo "rust-toolchains: $root/prek.toml is not a symlink, so it was left alone. Move it into rust-toolchains.prek.hooks and delete it." >&2
            else
              # An indirect GC root keeps the hook binaries alive until the next shell entry replaces the link.
              nix-store --add-root "$root/prek.toml" --indirect --realise ${cfg.configFile} >/dev/null
              ${lib.getExe pkgs.prek} install --quiet --cd "$root"
            fi
          else
            echo "rust-toolchains: no git repository found, so the prek hooks were not installed." >&2
          fi
        '';
      };
    };
  });
}
