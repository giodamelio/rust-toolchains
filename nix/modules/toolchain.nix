{self, ...}: {
  lib,
  flake-parts-lib,
  ...
}: {
  options.perSystem = flake-parts-lib.mkPerSystemOption ({
    config,
    pkgs,
    system,
    ...
  }: {
    options.rust-toolchains = {
      channel = lib.mkOption {
        type = lib.types.enum ["stable" "nightly"];
        default = "stable";
        description = "Which pinned rust-toolchains toolchain the devshell, hooks and checks use.";
      };
      toolchain = lib.mkOption {
        type = lib.types.package;
        default = self.packages.${system}.${config.rust-toolchains.channel};
        defaultText = lib.literalExpression "rust-toolchains.packages.\${system}.\${channel}";
        description = "The Rust toolchain package. Override only to leave the shared pin, which loses kache sharing.";
      };
      rustPlatform = lib.mkOption {
        type = lib.types.raw;
        default = pkgs.makeRustPlatform {
          cargo = config.rust-toolchains.toolchain;
          rustc = config.rust-toolchains.toolchain;
        };
        defaultText = lib.literalExpression "pkgs.makeRustPlatform { cargo = toolchain; rustc = toolchain; }";
        description = "A rustPlatform built from the toolchain, so packages compile with the same rustc as the devshell.";
      };
    };
  });
}
