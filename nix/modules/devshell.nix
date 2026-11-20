{modules, ...}: {
  lib,
  flake-parts-lib,
  ...
}: {
  imports = [modules.toolchain];

  options.perSystem = flake-parts-lib.mkPerSystemOption ({
    config,
    pkgs,
    ...
  }: let
    cfg = config.rust-toolchains.devShell;
  in {
    options.rust-toolchains.devShell = {
      packages = lib.mkOption {
        type = lib.types.listOf lib.types.package;
        default = [];
        description = "Extra packages for the default devshell.";
      };
      shellHook = lib.mkOption {
        type = lib.types.lines;
        default = "";
        description = "Shell code run when entering the default devshell.";
      };
    };

    config.devShells.default = lib.mkDefault (pkgs.mkShell {
      packages = [config.rust-toolchains.toolchain] ++ cfg.packages;
      inherit (cfg) shellHook;
    });
  });
}
