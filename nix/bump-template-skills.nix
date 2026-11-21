{pkgs}: let
  inherit (pkgs) lib;
  skills = import ./lib/skills.nix {
    inherit pkgs lib;
    checkAfterBump = false;
  };
in
  # gh is deliberately not a runtimeInput, as with skills-bump: it needs the
  # user's own `gh auth login`.
  pkgs.writeShellApplication {
    name = "bump-template-skills";
    runtimeInputs = [pkgs.jq pkgs.coreutils];
    text = ''
      die() {
        echo "bump-template-skills: $*" >&2
        exit 1
      }

      if [ $# -gt 1 ]; then
        echo "usage: bump-template-skills [TAG]" >&2
        exit 2
      fi

      shopt -s nullglob
      locks=(templates/*/agent-skills.lock.json)
      [ -f flake.nix ] && [ "''${#locks[@]}" -gt 0 ] \
        || die "run this from the rust-toolchains repo root (no templates/*/agent-skills.lock.json found)"
      command -v gh >/dev/null \
        || die "needs the GitHub CLI (gh) on PATH, signed in with 'gh auth login'"

      repo=$(jq -er .repo "''${locks[0]}") || die "''${locks[0]} has no repo"
      for lock in "''${locks[@]}"; do
        [ "$(jq -r .repo "$lock")" = "$repo" ] \
          || die "$lock does not pin $repo like ''${locks[0]}, so the templates cannot share one pin"
      done

      # Resolved once, so a release published mid-run cannot split the pins.
      tag=''${1:-}
      if [ -z "$tag" ]; then
        tag=$(gh api "repos/$repo/releases/latest" --jq .tag_name) \
          || die "could not look up the latest release of $repo; is gh signed in ('gh auth login')?"
      fi

      for lock in "''${locks[@]}"; do
        echo "bump-template-skills: $lock" >&2
        RUST_TOOLCHAINS_SKILLS_ROOT=$PWD/$(dirname "$lock") ${lib.getExe skills.bump} "$tag"
      done

      echo "Next: nix flake check '.?dir=tests', so init still reproduces each template, then commit the lockfiles."
    '';
  }
