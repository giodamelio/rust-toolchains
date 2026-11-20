{self}: let
  # The key lets flake-parts dedupe a module that is imported both directly
  # and through another module that depends on it.
  mk = name: {
    key = "rust-toolchains#${name}";
    _file = ./. + "/${name}.nix";
    imports = [(import (./. + "/${name}.nix") {inherit self modules;})];
  };

  modules = {
    toolchain = mk "toolchain";
    test-runner = mk "test-runner";
    devshell = mk "devshell";
    prek = mk "prek";
    jj-fix = mk "jj-fix";
    checks = mk "checks";
    formatter = mk "formatter";
    banner = mk "banner";
    unused-deps = mk "unused-deps";
  };

  # Opt-in because cargo-deny fails any workspace crate without a license
  # field unless it sets `publish = false`, which the template does not.
  optIn = {
    cargo-deny = mk "cargo-deny";
  };
in
  modules
  // optIn
  // {
    default = {
      key = "rust-toolchains#default";
      imports = builtins.attrValues modules;
    };
  }
