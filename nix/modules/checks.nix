{modules, ...}: {
  lib,
  flake-parts-lib,
  ...
}: {
  imports = [modules.toolchain modules.test-runner];

  options.perSystem = flake-parts-lib.mkPerSystemOption ({
    config,
    pkgs,
    ...
  }: let
    cfg = config.rust-toolchains.checks;
    inherit (config.rust-toolchains) toolchain;

    mkCheck = name: command:
      pkgs.stdenv.mkDerivation {
        name = "${cfg.package.pname}-${name}";
        inherit (cfg.package) src cargoDeps;
        nativeBuildInputs = [toolchain pkgs.rustPlatform.cargoSetupHook] ++ cfg.nativeBuildInputs;
        inherit (cfg) buildInputs;
        buildPhase = ''
          runHook preBuild
          ${command}
          runHook postBuild
        '';
        installPhase = "touch $out";
      };
  in {
    options.rust-toolchains.checks = {
      enable = lib.mkOption {
        type = lib.types.bool;
        default = true;
        description = "Whether to add fmt, clippy and test checks built with the pinned toolchain.";
      };
      package = lib.mkOption {
        type = lib.types.package;
        default = config.packages.default;
        defaultText = lib.literalExpression "config.packages.default";
        description = "A buildRustPackage derivation whose src and cargoDeps the checks reuse.";
      };
      nativeBuildInputs = lib.mkOption {
        type = lib.types.listOf lib.types.package;
        default = [];
        description = "Extra build tools the checks need, such as pkg-config.";
      };
      buildInputs = lib.mkOption {
        type = lib.types.listOf lib.types.package;
        default = cfg.package.buildInputs or [];
        defaultText = lib.literalExpression "config.rust-toolchains.checks.package.buildInputs";
        description = "Libraries the checks link against.";
      };
    };

    config.checks = lib.mkIf cfg.enable {
      rust-build = cfg.package;
      rust-fmt = mkCheck "fmt" "cargo fmt --check";
      rust-clippy = mkCheck "clippy" "cargo clippy --offline --all-targets -- -D warnings";
      rust-test = mkCheck "test" (lib.getExe config.rust-toolchains.testRunner);
    };
  });
}
