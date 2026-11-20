{
  self,
  modules,
  ...
}: {
  lib,
  flake-parts-lib,
  ...
}: {
  imports = [modules.toolchain modules.test-runner];

  options.perSystem = flake-parts-lib.mkPerSystemOption ({
    config,
    pkgs,
    system,
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
      # Everything the hooks, checks and jj fix run, so each is also callable by hand.
      packages =
        [
          config.rust-toolchains.toolchain
          config.rust-toolchains.testRunner
          pkgs.cargo-nextest
          pkgs.alejandra
          pkgs.prek
          self.packages.${system}.skills-cli
        ]
        ++ cfg.packages;
      inherit (cfg) shellHook;
    });
  });
}
