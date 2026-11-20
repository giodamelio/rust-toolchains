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
    name = "bump-toolchain";
    runtimeInputs = [pkgs.curl pkgs.jq pkgs.coreutils];
    text = ''
      usage() {
        echo "usage: bump-toolchain stable [VERSION] | nightly [YYYY-MM-DD]" >&2
        exit 2
      }

      if [ $# -lt 1 ] || [ $# -gt 2 ]; then
        usage
      fi
      channel=$1
      requested=''${2:-}
      pins=toolchains.json
      dist=https://static.rust-lang.org/dist

      [ -f "$pins" ] || { echo "bump-toolchain: run this from the rust-toolchains repo root ($pins not found)" >&2; exit 1; }

      tmp=$(mktemp -d)
      trap 'rm -rf "$tmp"' EXIT
      manifest="$tmp/channel.toml"

      fetch() {
        curl --fail --silent --show-error --location --output "$manifest" "$1"
      }

      missing() {
        nix eval --impure --json --expr "import ${missingComponents} $manifest" | jq -r '.[]'
      }

      case "$channel" in
        stable)
          if [ -n "$requested" ]; then
            version=$requested
          else
            fetch "$dist/channel-rust-stable.toml"
            version=$(nix eval --impure --raw --expr "builtins.head (builtins.split \" \" (builtins.fromTOML (builtins.readFile $manifest)).pkg.rustc.version)")
          fi
          url="$dist/channel-rust-$version.toml"
          fetch "$url" || { echo "bump-toolchain: no stable manifest for $version at $url" >&2; exit 1; }
          gaps=$(missing)
          if [ -n "$gaps" ]; then
            echo "bump-toolchain: stable $version is missing components:" >&2
            echo "$gaps" >&2
            exit 1
          fi
          key="version"
          value=$version
          ;;
        nightly)
          if [ -n "$requested" ]; then
            candidates=$requested
          else
            candidates=$(for days in $(seq 0 14); do date -u -d "-$days days" +%F; done)
          fi
          value=
          for date in $candidates; do
            url="$dist/$date/channel-rust-nightly.toml"
            if ! fetch "$url" 2>/dev/null; then
              echo "bump-toolchain: no nightly manifest for $date" >&2
              continue
            fi
            gaps=$(missing)
            if [ -z "$gaps" ]; then
              value=$date
              break
            fi
            echo "bump-toolchain: nightly $date is missing components:" >&2
            echo "$gaps" >&2
          done
          [ -n "$value" ] || { echo "bump-toolchain: no usable nightly found" >&2; exit 1; }
          key="date"
          ;;
        *)
          usage
          ;;
      esac

      sha256=$(nix hash path --mode flat --algo sha256 "$manifest")
      old=$(jq -r --arg c "$channel" --arg k "$key" '.[$c][$k]' "$pins")

      jq --arg c "$channel" --arg k "$key" --arg v "$value" --arg url "$url" --arg sha256 "$sha256" \
        '.[$c] = {($k): $v, url: $url, sha256: $sha256}' "$pins" > "$tmp/pins.json"
      mv "$tmp/pins.json" "$pins"

      if [ "$old" = "$value" ]; then
        echo "$channel is already at $value"
      else
        echo "$channel: $old -> $value"
        echo "Next: nix flake check --all-systems, then commit toolchains.json."
      fi
    '';
  }
