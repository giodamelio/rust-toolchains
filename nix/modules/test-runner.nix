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
  }: {
    options.rust-toolchains.testRunner = lib.mkOption {
      type = lib.types.package;
      default = pkgs.writeShellApplication {
        name = "cargo-test-auto";
        runtimeInputs = [config.rust-toolchains.toolchain pkgs.cargo-nextest];
        text = ''
          if [ -f .config/nextest.toml ]; then
            exec cargo nextest run --no-tests=warn "$@"
          else
            exec cargo test "$@"
          fi
        '';
      };
      defaultText = lib.literalMD "`cargo nextest run` when `.config/nextest.toml` exists, otherwise `cargo test`";
      description = "Test command shared by the pre-push hook and the flake check.";
    };
  });
}
