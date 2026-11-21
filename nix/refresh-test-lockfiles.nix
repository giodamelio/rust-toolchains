{
  pkgs,
  stable,
}:
pkgs.writeShellApplication {
  name = "refresh-test-lockfiles";
  runtimeInputs = [stable pkgs.coreutils];
  text = ''
    die() {
      echo "refresh-test-lockfiles: $*" >&2
      exit 1
    }

    [ -f flake.nix ] && [ -f tests/flake.nix ] \
      || die "run this from the rust-toolchains repo root (tests/flake.nix not found)"

    # The committed lockfiles name the templates that need one, so a new
    # template opts in by being named once on the command line.
    if [ $# -gt 0 ]; then
      names=("$@")
    else
      shopt -s nullglob
      names=()
      for lock in tests/*/Cargo.lock; do
        names+=("$(basename "$(dirname "$lock")")")
      done
      [ "''${#names[@]}" -gt 0 ] || die "no tests/*/Cargo.lock found; name the templates to create one for"
    fi

    tmp=$(mktemp -d)
    trap 'rm -rf "$tmp"' EXIT

    for name in "''${names[@]}"; do
      [ -f "templates/$name/Cargo.toml" ] || die "templates/$name/Cargo.toml not found"
      cp -r "templates/$name" "$tmp/$name"
      cargo generate-lockfile --manifest-path "$tmp/$name/Cargo.toml"
      mkdir -p "tests/$name"
      cp "$tmp/$name/Cargo.lock" "tests/$name/Cargo.lock"
      echo "refresh-test-lockfiles: wrote tests/$name/Cargo.lock"
    done

    echo "Next: add any new template to lockFiles in tests/flake.nix, run nix flake check '.?dir=tests', then commit the lockfiles."
  '';
}
