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
    cfg = config.rust-toolchains.cargoDeny;
    toml = pkgs.formats.toml {};
  in {
    options.rust-toolchains.cargoDeny = {
      enable = lib.mkOption {
        type = lib.types.bool;
        default = true;
        description = "Whether to add cargo-deny to the devshell and run `cargo deny check` as a pre-push hook.";
      };
      settings = lib.mkOption {
        inherit (toml) type;
        description = ''
          cargo-deny config, rendered to TOML and passed with `--config`.
          Ignored when the repo has a `deny.toml`, `.deny.toml`, `.cargo/deny.toml` or `.config/deny.toml`.
          Lists such as `licenses.allow` are appended to the defaults; use `lib.mkForce` to replace them.
        '';
      };
      configFile = lib.mkOption {
        type = lib.types.package;
        readOnly = true;
        description = "The deny.toml generated from `settings`.";
      };
      runner = lib.mkOption {
        type = lib.types.package;
        readOnly = true;
        description = "`cargo-deny-check`, which runs `cargo deny check` with the repo's deny.toml if it has one and `configFile` otherwise.";
      };
    };

    config = lib.mkMerge [
      {
        # Scalars are mkDefault so a plain definition overrides them; lists are
        # left at normal priority so definitions concatenate.
        rust-toolchains.cargoDeny.settings = {
          licenses = {
            # Unpublished workspace crates often have no license field.
            private.ignore = lib.mkDefault true;
            allow = [
              "MIT"
              "MIT-0"
              "Apache-2.0"
              "Apache-2.0 WITH LLVM-exception"
              "BSD-2-Clause"
              "BSD-3-Clause"
              "ISC"
              "Unicode-3.0"
              "Zlib"
              "0BSD"
              "BSL-1.0"
              "CC0-1.0"
              "Unlicense"
            ];
            # The list is a broad allowance, not an inventory of what the project uses.
            unused-allowed-license = lib.mkDefault "allow";
          };
          bans.multiple-versions = lib.mkDefault "warn";
          sources = {
            unknown-registry = lib.mkDefault "deny";
            unknown-git = lib.mkDefault "deny";
            allow-registry = ["https://github.com/rust-lang/crates.io-index"];
          };
        };

        rust-toolchains.cargoDeny.configFile = toml.generate "deny.toml" cfg.settings;

        rust-toolchains.cargoDeny.runner = pkgs.writeShellApplication {
          name = "cargo-deny-check";
          runtimeInputs = [config.rust-toolchains.toolchain pkgs.cargo-deny];
          # Mirrors the file names cargo-deny itself looks for, so a hand-written
          # config always wins over the generated one.
          text = ''
            if [ -e deny.toml ] || [ -e .deny.toml ] || [ -e .cargo/deny.toml ] || [ -e .config/deny.toml ]; then
              exec cargo deny check "$@"
            else
              exec cargo deny --config ${cfg.configFile} check "$@"
            fi
          '';
        };
      }
      (lib.mkIf cfg.enable {
        rust-toolchains.devShell.packages = [pkgs.cargo-deny cfg.runner];

        rust-toolchains.prek.hooks.cargo-deny = {
          name = "cargo-deny";
          entry = lib.getExe cfg.runner;
          language = "system";
          files = "(^|/)(Cargo\\.(toml|lock)|\\.?deny\\.toml)$";
          pass_filenames = false;
          stages = ["pre-push"];
          # After the tests, so cargo-deny's `cargo metadata` does not contend
          # with the test build for cargo's locks.
          priority = 3;
        };
      })
    ];
  });
}
