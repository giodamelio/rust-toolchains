{
  lib,
  pkgs,
}: rec {
  # Hook commands and flags adapted from git-hooks.nix (modules/hooks.nix).
  # Thanks to the cachix/git-hooks.nix project: https://github.com/cachix/git-hooks.nix
  hooks = {
    alejandra = {
      name = "alejandra";
      entry = "${lib.getExe pkgs.alejandra} --check";
      language = "system";
      files = "\\.nix$";
      stages = ["pre-commit" "pre-push"];
      priority = 0;
    };
  };

  mkConfig = hooks:
    (pkgs.formats.toml {}).generate "prek.toml" {
      default_install_hook_types = ["pre-commit" "pre-push"];
      repos = [
        {
          repo = "local";
          inherit hooks;
        }
      ];
    };

  mkShellHook = configFile: ''
    if root=$(${lib.getExe pkgs.git} rev-parse --show-toplevel 2>/dev/null); then
      if [ -e "$root/prek.toml" ] && [ ! -L "$root/prek.toml" ]; then
        echo "rust-toolchains: $root/prek.toml is not a symlink, so it was left alone. Move it into the Nix hook config and delete it." >&2
      else
        # An indirect GC root keeps the hook binaries alive until the next shell entry replaces the link.
        nix-store --add-root "$root/prek.toml" --indirect --realise ${configFile} >/dev/null
        ${lib.getExe pkgs.prek} install --quiet --cd "$root"
      fi
    else
      echo "rust-toolchains: no git repository found, so the prek hooks were not installed." >&2
    fi
  '';
}
