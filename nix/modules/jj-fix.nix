{modules, ...}: {
  lib,
  flake-parts-lib,
  ...
}: {
  imports = [modules.toolchain modules.devshell];

  options.perSystem = flake-parts-lib.mkPerSystemOption ({
    config,
    pkgs,
    ...
  }: let
    cfg = config.rust-toolchains.jjFix;
    tools = lib.filterAttrs (_: tool: tool.enable) cfg.tools;

    setTool = name: tool: ''
      jj config set --repo fix.tools.${name}.command ${lib.escapeShellArg (builtins.toJSON tool.command)}
      jj config set --repo fix.tools.${name}.patterns ${lib.escapeShellArg (builtins.toJSON tool.patterns)}
    '';
  in {
    options.rust-toolchains.jjFix = {
      enable = lib.mkOption {
        type = lib.types.bool;
        default = true;
        description = "Whether entering the devshell writes `jj fix` tools into the jj repo config.";
      };
      edition = lib.mkOption {
        type = lib.types.str;
        default = "2024";
        description = "Rust edition passed to rustfmt, which cannot read it from Cargo.toml when formatting stdin.";
      };
      tools = lib.mkOption {
        type = lib.types.attrsOf (lib.types.submodule {
          options = {
            enable = lib.mkOption {
              type = lib.types.bool;
              default = true;
            };
            command = lib.mkOption {type = lib.types.listOf lib.types.str;};
            patterns = lib.mkOption {type = lib.types.listOf lib.types.str;};
          };
        });
        description = "`jj fix` tools, keyed by tool name.";
      };
    };

    config = {
      rust-toolchains.jjFix.tools = {
        rustfmt = {
          command = ["${config.rust-toolchains.toolchain}/bin/rustfmt" "--emit" "stdout" "--edition" cfg.edition];
          patterns = ["glob:'**/*.rs'"];
        };
        alejandra = {
          command = [(lib.getExe pkgs.alejandra) "--quiet" "-"];
          patterns = ["glob:'**/*.nix'"];
        };
      };

      # jj keeps repo config outside the repo, so it is written on shell entry
      # instead of being committed.
      rust-toolchains.devShell.shellHook = lib.mkIf cfg.enable ''
        if command -v jj >/dev/null && jj root >/dev/null 2>&1; then
          ${lib.concatStrings (lib.mapAttrsToList setTool tools)}
        fi
      '';
    };
  });
}
