{modules, ...}: {
  lib,
  flake-parts-lib,
  ...
}: {
  imports = [modules.toolchain modules.devshell modules.prek];

  options.perSystem = flake-parts-lib.mkPerSystemOption ({
    config,
    pkgs,
    ...
  }: let
    cfg = config.rust-toolchains.unusedDeps;
  in {
    options.rust-toolchains.unusedDeps = {
      enable = lib.mkOption {
        type = lib.types.bool;
        default = true;
        description = "Whether a pre-push hook fails on dependencies reported by Cargo's `cargo::unused_dependencies` lint.";
      };
      package = lib.mkOption {
        type = lib.types.package;
        default = pkgs.writeShellApplication {
          name = "cargo-unused-deps";
          runtimeInputs = [config.rust-toolchains.toolchain];
          # The lint is warn by default and `clippy -D warnings` only reaches
          # rustc lints, so build.warnings is what turns Cargo's lints into a
          # failure. Rustc warnings fail here too, as they already do in clippy.
          text = ''
            exec cargo check --offline --workspace --config 'build.warnings="deny"' "$@"
          '';
        };
        defaultText = lib.literalMD "`cargo check --workspace` with `build.warnings = \"deny\"`";
        description = "Command shared by the pre-push hook and the devshell.";
      };
    };

    config = lib.mkIf cfg.enable {
      rust-toolchains.devShell.packages = [cfg.package];

      rust-toolchains.prek.hooks.unused-deps = {
        name = "unused-deps";
        entry = lib.getExe cfg.package;
        language = "system";
        files = "(^|/)Cargo\\.toml$|\\.rs$";
        pass_filenames = false;
        stages = ["pre-push"];
        priority = 2;
      };
    };
  });
}
