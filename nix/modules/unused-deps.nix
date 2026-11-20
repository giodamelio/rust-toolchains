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
      devDependencies = {
        enable = lib.mkOption {
          type = lib.types.bool;
          default = true;
          description = "Whether a pre-push hook fails on unused `[dev-dependencies]`, which the Cargo lint does not check, as reported by cargo-shear.";
        };
        package = lib.mkOption {
          type = lib.types.package;
          default = pkgs.writeShellApplication {
            name = "cargo-unused-dev-deps";
            runtimeInputs = [config.rust-toolchains.toolchain pkgs.cargo-shear pkgs.jq];
            # cargo-shear has no dev-only mode and its JSON findings carry no
            # dependency kind, so each finding is matched against cargo
            # metadata. Only keys declared solely as dev-dependencies count:
            # the Cargo lint already reports normal and build dependencies, and
            # shear's heuristic is less accurate than the compiler for those.
            text = ''
              status=0
              report=$(cargo shear --offline --format=json "$@") || status=$?
              if [ "$status" -gt 1 ]; then
                printf '%s\n' "$report" >&2
                exit "$status"
              fi

              metadata=$(cargo metadata --offline --no-deps --format-version 1)
              unused=$(jq -r --argjson metadata "$metadata" '
                $metadata.workspace_root as $root
                | ($metadata.packages | map({key: .manifest_path, value: .dependencies}) | from_entries) as $deps
                | .findings[]
                | select(.code == "shear/unused_dependency")
                | (.message | capture("^unused dependency `(?<name>.+)`$").name
                  // error("unrecognised cargo-shear message: \(.message)")) as $name
                | (if .file | startswith("/") then .file else "\($root)/\(.file)" end) as $manifest
                | [$deps[$manifest][]? | select((.rename // .name) == $name) | .kind] as $kinds
                | if $kinds == [] then error("cargo metadata lists no dependency `\($name)` in \(.file)") end
                | select($kinds | all(. == "dev"))
                | "\(.file): unused dev-dependency `\($name)`"
              ' <<<"$report")

              if [ -n "$unused" ]; then
                printf '%s\n' "$unused" >&2
                echo 'To keep a false positive, add it to [package.metadata.cargo-shear] ignored = [...] in that Cargo.toml.' >&2
                exit 1
              fi
            '';
          };
          defaultText = lib.literalMD "`cargo shear` filtered to findings for keys declared only in `[dev-dependencies]`";
          description = "Command shared by the dev-dependency pre-push hook and the devshell.";
        };
      };
    };

    config = lib.mkIf cfg.enable (lib.mkMerge [
      {
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
      }
      (lib.mkIf cfg.devDependencies.enable {
        rust-toolchains.devShell.packages = [pkgs.cargo-shear cfg.devDependencies.package];

        rust-toolchains.prek.hooks.unused-dev-deps = {
          name = "unused-dev-deps";
          entry = lib.getExe cfg.devDependencies.package;
          language = "system";
          files = "(^|/)Cargo\\.toml$|\\.rs$";
          pass_filenames = false;
          stages = ["pre-push"];
          # After the tests and cargo-deny, so cargo-shear's `cargo metadata`
          # does not contend with them for cargo's locks.
          priority = 4;
        };
      })
    ]);
  });
}
