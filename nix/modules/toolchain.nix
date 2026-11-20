{self, ...}: {
  lib,
  flake-parts-lib,
  ...
}: {
  options.perSystem = flake-parts-lib.mkPerSystemOption ({
    config,
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
    };
  });
}
