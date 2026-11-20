{
  pkgs,
  components,
  systems,
}: let
  inherit (pkgs) lib;
  targets = map (system: (lib.systems.elaborate system).rust.rustcTarget) systems;
  toNixList = list: "[${lib.concatMapStringsSep " " builtins.toJSON list}]";

  # Manifest names some components with a -preview suffix, and rust-src is
  # published once for target "*".
  missingComponents = pkgs.writeText "missing-components.nix" ''
    manifest: let
      m = builtins.fromTOML (builtins.readFile manifest);
      components = ${toNixList components};
      targets = ${toNixList targets};
      available = c: t: let
        pkg = m.pkg.''${c} or m.pkg."''${c}-preview" or {};
        target = pkg.target.''${t} or pkg.target."*" or {};
      in
        target.available or false;
    in
      builtins.concatMap
      (c: map (t: "''${c} on ''${t}") (builtins.filter (t: !(available c t)) targets))
      components
  '';
in
  pkgs.writeShellApplication {
    name = "bump-nightly";
    runtimeInputs = [pkgs.curl pkgs.jq pkgs.coreutils];
    text = ''
      usage() {
        echo "usage: bump-nightly [YYYY-MM-DD]" >&2
        exit 2
      }

      if [ $# -gt 1 ]; then
        usage
      fi
      pin=nightly.json
      dist=https://static.rust-lang.org/dist

      [ -f "$pin" ] || { echo "bump-nightly: run this from the rust-toolchains repo root ($pin not found)" >&2; exit 1; }

      tmp=$(mktemp -d)
      trap 'rm -rf "$tmp"' EXIT
      manifest="$tmp/channel.toml"

      if [ $# -eq 1 ]; then
        candidates=$1
      else
        candidates=$(for days in $(seq 0 14); do date -u -d "-$days days" +%F; done)
      fi

      found=
      for date in $candidates; do
        url="$dist/$date/channel-rust-nightly.toml"
        if ! curl --fail --silent --location --output "$manifest" "$url"; then
          echo "bump-nightly: no nightly manifest for $date" >&2
          continue
        fi
        gaps=$(nix eval --impure --json --expr "import ${missingComponents} $manifest" | jq -r '.[]')
        if [ -z "$gaps" ]; then
          found=$date
          break
        fi
        echo "bump-nightly: nightly $date is missing components:" >&2
        echo "$gaps" >&2
      done
      [ -n "$found" ] || { echo "bump-nightly: no usable nightly found" >&2; exit 1; }

      old=$(jq -r .date "$pin")
      jq -n --arg date "$found" --arg url "$url" --arg sha256 "$(nix hash path --mode flat --algo sha256 "$manifest")" \
        '{date: $date, url: $url, sha256: $sha256}' > "$pin"

      if [ "$old" = "$found" ]; then
        echo "nightly is already at $found"
      else
        echo "nightly: $old -> $found"
        echo "Next: nix flake check --all-systems, then commit nightly.json."
      fi
    '';
  }
