{pkgs}:
pkgs.writeShellApplication {
  name = "bump-skills-cli";
  runtimeInputs = [pkgs.nix-update];
  text = ''
    pkg=nix/packages/skills-cli.nix

    [ -f "$pkg" ] || { echo "bump-skills-cli: run this from the rust-toolchains repo root ($pkg not found)" >&2; exit 1; }

    nix-update --flake skills-cli "$@"
  '';
}
