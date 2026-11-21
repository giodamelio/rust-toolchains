{
  description = "Pinned Rust toolchains shared across projects so kache hits across them";

  inputs = {
    nixpkgs.url = "github:nixos/nixpkgs/nixos-unstable";
    fenix = {
      url = "github:nix-community/fenix";
      inputs.nixpkgs.follows = "nixpkgs";
    };
  };

  outputs = {
    self,
    nixpkgs,
    fenix,
  }: let
    systems = ["x86_64-linux" "aarch64-linux" "aarch64-darwin"];
    eachSystem = nixpkgs.lib.genAttrs systems;

    # Fetched at eval time rather than through toolchainOf, whose pkgs.fetchurl
    # would make other systems' outputs depend on import-from-derivation.
    nightlyManifest = let
      pin = builtins.fromJSON (builtins.readFile ./nightly.json);
    in
      builtins.fetchurl {inherit (pin) url sha256;};

    components = ["rustc" "cargo" "clippy" "rustfmt" "rust-src" "rust-analyzer"];

    # Built from pkgs.formats.toml rather than treefmt-nix, which would become
    # an input of every downstream lock.
    mkTreefmt = system: let
      pkgs = nixpkgs.legacyPackages.${system};
      inherit (pkgs) lib;
      config = (pkgs.formats.toml {}).generate "treefmt.toml" {
        excludes = ["flake.lock" "tests/flake.lock" "prek.toml" "result"];
        formatter = {
          alejandra = {
            command = lib.getExe pkgs.alejandra;
            includes = ["*.nix"];
          };
          # treefmt hands rustfmt bare files, so the edition Cargo.toml would
          # supply has to be passed explicitly.
          rustfmt = {
            command = lib.getExe' self.packages.${system}.stable "rustfmt";
            options = ["--edition" "2024"];
            includes = ["*.rs"];
          };
          # gfm keeps tables and other GitHub syntax intact; --number keeps
          # ordered lists as 1. 2. 3. instead of rewriting them all to 1.
          mdformat = {
            command = lib.getExe (pkgs.mdformat.withPlugins (p: [p.mdformat-gfm]));
            options = ["--number"];
            includes = ["*.md"];
          };
        };
      };
    in
      pkgs.writeShellApplication {
        name = "treefmt";
        text = ''exec ${lib.getExe pkgs.treefmt} --config-file ${config} "$@"'';
      };
  in {
    # Stable follows fenix as locked in this repo's flake.lock, so bumping it is
    # `nix flake update fenix`. Nightly is pinned by date in nightly.json.
    packages = eachSystem (system: let
      fenixPkgs = fenix.packages.${system};
    in {
      stable = fenixPkgs.stable.withComponents components;
      nightly = (fenixPkgs.fromManifestFile nightlyManifest).withComponents components;
    });

    formatter = eachSystem mkTreefmt;

    apps = eachSystem (system: let
      pkgs = nixpkgs.legacyPackages.${system};
      inherit (pkgs) lib;
      skills = import ./nix/lib/skills.nix {inherit pkgs lib;};
      # jj and git are deliberately not runtimeInputs: the repo is created with
      # the user's own versions and config, and only offered if installed.
      init = pkgs.writeShellApplication {
        name = "init";
        runtimeInputs = [pkgs.cargo-generate pkgs.coreutils pkgs.gum];
        text = ''
          die() {
            echo "init: $*" >&2
            exit 1
          }

          # cargo-generate reads every placeholder before it copies anything, so
          # the base template cannot be one of its questions; init takes it as
          # its own flag and passes everything else through.
          base="" dev_port="" silent=false args=()
          while [ $# -gt 0 ]; do
            case $1 in
              --dev-port)
                [ $# -ge 2 ] || die "--dev-port needs a port number"
                dev_port=$2
                shift 2
                continue
                ;;
              --dev-port=*)
                dev_port=''${1#--dev-port=}
                shift
                continue
                ;;
              # The project is found as the only entry cargo-generate creates
              # in an empty staging dir, so a destination of the user's own, or
              # --init's generating into it directly, would break that.
              --destination | --destination=* | --init)
                die "$1 is not supported; cd to the directory that should contain the project and run init there"
                ;;
              --template)
                [ $# -ge 2 ] || die "--template needs a value: basic or axum"
                base=$2
                shift 2
                continue
                ;;
              --template=*)
                base=''${1#--template=}
                shift
                continue
                ;;
              -d | --define)
                case ''${2-} in
                  template=*) die "choose the template with --template, not $1 template=..." ;;
                esac
                ;;
              --define=template=* | -dtemplate=*)
                die "choose the template with --template, not $1"
                ;;
              -s | --silent) silent=true ;;
            esac
            args+=("$1")
            shift
          done

          if [ -z "$base" ]; then
            if [ "$silent" = false ] && [ -t 0 ]; then
              base=$(gum choose --header "Template" --label-delimiter "|" \
                "basic - ${self.templates.basic.description}|basic" \
                "axum - ${self.templates.axum.description}|axum") || die "no template chosen"
            fi
            base=''${base:-basic}
          fi
          case $base in
            basic) base_dir=${./templates/basic} ;;
            axum) base_dir=${./templates/axum} ;;
            *) die "unknown template '$base'; choose basic or axum" ;;
          esac

          template=$(mktemp -d)
          staging=$(mktemp -d)
          trap 'rm -rf "$template" "$staging"' EXIT

          # cargo-generate copies a template keeping its read-only store mode and
          # then fails writing the rendered files, so it gets a writable copy.
          cp -r --no-preserve=mode "$base_dir"/. "$template"
          cp -r --no-preserve=mode ${./templates/init}/. "$template"

          # Each template stays a plain project that `nix flake init` can use.
          # Rather than keep a .liquid copy of its files that could drift from
          # it, init turns the template's literal defaults into placeholders.
          placeholder() {
            local file=$template/$1 content
            content=$(<"$file")
            [[ $content == *"$2"* ]] \
              || die "templates/$base/$1 no longer contains '$2', which init turns into a placeholder"
            printf '%s\n' "''${content//"$2"/"$3"}" >"$file"
          }
          placeholder Cargo.toml rust-project '{{ project-name }}'
          placeholder README.md '# rust-project' '# {{ project-name }}'
          placeholder Cargo.toml 'publish = false' "$(<${./templates/init/fields/Cargo.toml.liquid})"
          placeholder flake.nix '        rust-toolchains.channel = "stable";' "$(<${./templates/init/fields/flake.nix.liquid})"
          # axum's flake reads the crate name from Cargo.toml instead.
          if [ "$base" = basic ]; then
            placeholder flake.nix 'pname = "rust-project";' 'pname = "{{ project-name }}";'
          fi

          # A random dev port keeps several generated servers from colliding on
          # one machine; --dev-port pins it, which the drift check relies on.
          if [ "$base" = axum ]; then
            dev_port=''${dev_port:-$((8000 + RANDOM % 1000))}
            [[ $dev_port =~ ^[0-9]+$ ]] && [ "$dev_port" -ge 1 ] && [ "$dev_port" -le 65535 ] \
              || die "--dev-port must be a port number, got '$dev_port'"
            for file in src/main.rs flake.nix AGENTS.md README.md; do
              placeholder "$file" '127.0.0.1:8000' "127.0.0.1:$dev_port"
            done
          elif [ -n "$dev_port" ]; then
            die "--dev-port only applies to --template axum"
          fi

          vcs_choices=()
          command -v jj >/dev/null && vcs_choices+=(jj)
          command -v git >/dev/null && vcs_choices+=(git)
          vcs_choices+=(none)
          printf -v quoted '"%s", ' "''${vcs_choices[@]}"
          config="$template/cargo-generate.toml"
          toml=$(<"$config")
          toml=''${toml//'"@VCS_CHOICES@"'/''${quoted%, }}
          toml=''${toml//@VCS_DEFAULT@/''${vcs_choices[0]}}
          printf '%s\n' "$toml" >"$config"

          # Its progress lines go to stdout and name the staging dir, which is an
          # implementation detail; prompts go to stderr and are untouched.
          cargo-generate generate --path "$template" --destination "$staging" --vcs none --no-workspace --force "''${args[@]}" \
            | { grep --line-buffered -vF "$staging" || true; }

          shopt -s nullglob dotglob
          generated=("$staging"/*)
          [ "''${#generated[@]}" -eq 1 ] && [ -d "''${generated[0]}" ] \
            || die "expected cargo-generate to create one project directory, found ''${#generated[@]} entries"
          project="$PWD/$(basename "''${generated[0]}")"
          [ -e "$project" ] || [ -L "$project" ] && die "$project already exists, so it was left alone"
          mv -T "''${generated[0]}" "$project"

          answers="$project/.init-answers"
          [ -f "$answers" ] || die "the template's post hook did not write $answers"
          vcs="" install_skills=""
          while IFS='=' read -r key value; do
            case $key in
              vcs) vcs=$value ;;
              install_skills) install_skills=$value ;;
            esac
          done <"$answers"
          rm "$answers"
          echo "init: created $project"

          # Run from the user's directory with the project path, so jj and git
          # report the new project rather than ".".
          case $vcs in
            jj) setup=(jj git init "$project") ;;
            git) setup=(git init "$project") ;;
            none) setup=() ;;
            *) die "created $project, but the vcs answer '$vcs' is unknown" ;;
          esac
          if [ "''${#setup[@]}" -gt 0 ]; then
            cmd="''${setup[*]}"
            command -v "$vcs" >/dev/null \
              || die "created $project, but could not set up $vcs: it is not on PATH. Install it and run '$cmd' there."
            "''${setup[@]}" \
              || die "created $project, but '$cmd' failed. Fix the error above and run it there."
          fi

          cd "$project"
          if [ "$install_skills" = true ]; then
            RUST_TOOLCHAINS_SKILLS_ROOT=$project ${lib.getExe skills.install} \
              || die "created $project, but downloading the agent skills failed. Run skills-install in its devshell to retry."
          fi
        '';
      };
    in {
      init = {
        type = "app";
        program = pkgs.lib.getExe init;
        meta.description = "Generate a new project from templates/basic or templates/axum, asking for the channel, modules, license and version control, and optionally downloading the agent skills";
      };
    });

    devShells = eachSystem (system: let
      pkgs = nixpkgs.legacyPackages.${system};
      prekLib = import ./nix/lib/prek.nix {inherit (pkgs) lib pkgs;};
      treefmt = self.formatter.${system};
    in {
      default = pkgs.mkShell {
        packages = [
          pkgs.alejandra
          treefmt
          pkgs.prek
          (import ./nix/bump-nightly.nix {inherit pkgs components systems;})
        ];
        shellHook =
          prekLib.mkShellHook (prekLib.mkConfig [
            {
              id = "treefmt";
              name = "treefmt";
              entry = "${pkgs.lib.getExe treefmt} --fail-on-change";
              language = "system";
              files = "\\.(nix|rs|md)$";
              stages = ["pre-commit" "pre-push"];
              priority = 0;
            }
          ])
          + import ./nix/lib/banner.nix {inherit (pkgs) lib pkgs;} {
            title = "rust-toolchains";
            commands = [
              {
                command = "nix run .#init";
                description = "Generate a new project interactively";
              }
              {
                command = "nix flake update fenix";
                description = "Bump stable to fenix's latest";
              }
              {
                command = "bump-nightly [YYYY-MM-DD]";
                description = "Bump the nightly pin in nightly.json";
              }
              {
                command = "nix fmt";
                description = "Format Nix, Rust and Markdown with treefmt";
              }
              {
                command = "prek run --all-files";
                description = "Check formatting with treefmt";
              }
              {
                command = "nix flake check --all-systems";
                description = "Evaluate every output on every system";
              }
              {
                command = "nix flake check 'path:.?dir=tests'";
                description = "Build and check the templates against this checkout";
              }
            ];
          };
      };
    });

    flakeModules = import ./nix/modules {inherit self;};

    templates = {
      default = self.templates.basic;
      basic = {
        path = ./templates/basic;
        description = "Rust binary using the pinned rust-toolchains toolchain, flake-parts and prek hooks";
      };
      axum = {
        path = ./templates/axum;
        description = "axum HTTP server with systemd socket activation, Type=notify, a NixOS module and a VM test, on top of basic";
      };
    };
  };
}
