{
  description = "Builds and checks the templates against this checkout of rust-toolchains";

  # A separate flake so flake-parts stays out of the root flake's inputs,
  # which every downstream lock inherits.
  inputs.flake-parts.url = "github:hercules-ci/flake-parts";

  outputs = {
    self,
    flake-parts,
  }: let
    # Loaded with getFlake rather than as a path input so it resolves fenix and
    # nixpkgs from the root flake.lock. A path input would copy them into this
    # flake's lock once and then go stale on the next `nix flake update fenix`.
    # getFlake refuses strings with store path context, and the source is
    # already in the store, so dropping the context loses nothing.
    rust-toolchains =
      if builtins.pathExists "${self.sourceInfo.outPath}/tests/flake.nix"
      then
        builtins.getFlake (builtins.unsafeDiscardStringContext
          "path:${self.sourceInfo.outPath}?narHash=${self.sourceInfo.narHash}")
      else throw "Run this from the repo root as `nix flake check 'path:.?dir=tests'`, so the whole checkout is in the flake source.";
    inherit (rust-toolchains.inputs) nixpkgs;

    system = "x86_64-linux";
    pkgs = nixpkgs.legacyPackages.${system};
    inherit (pkgs) lib;

    # A template with dependencies cannot resolve them offline in the sandbox,
    # so its lockfile is committed here; templates/ must never contain one.
    lockFiles = {
      basic = null;
      axum = ./axum/Cargo.lock;
    };

    # Its own store path so edits elsewhere in the repo do not rebuild the checks.
    templateSrc = name:
      builtins.path {
        name = "template-${name}";
        path = "${rust-toolchains}/templates/${name}";
      };

    # Import-from-derivation: the template's flake.nix reads ./Cargo.lock
    # relative to itself.
    tree = name: lockFile:
      pkgs.runCommand "rust-toolchains-template-${name}" {nativeBuildInputs = [rust-toolchains.packages.${system}.stable];} ''
        cp -r ${templateSrc name} $out
        chmod -R u+w $out
        ${
          if lockFile == null
          then "HOME=$TMPDIR cargo generate-lockfile --offline --manifest-path $out/Cargo.toml"
          else "cp ${lockFile} $out/Cargo.lock"
        }
      '';

    # Wrapping mkFlake injects the channel override without editing the
    # template, whose perSystem sets channel = "stable" at normal priority.
    withChannel = channel:
      flake-parts
      // {
        lib =
          flake-parts.lib
          // {
            mkFlake = args: module:
              flake-parts.lib.mkFlake args {
                imports = [
                  module
                  {perSystem = {lib, ...}: {rust-toolchains.channel = lib.mkForce channel;};}
                ];
              };
          };
      };

    evalTemplate = src: channel: let
      inputs = {
        inherit nixpkgs rust-toolchains;
        flake-parts = withChannel channel;
        self =
          outputs
          // {
            inherit inputs outputs;
            outPath = src;
          };
      };
      outputs = (import "${src}/flake.nix").outputs inputs;
    in
      outputs;

    checksFor = name: lockFile: channel:
      lib.mapAttrs' (check: lib.nameValuePair "${name}-${channel}-${check}")
      (evalTemplate (tree name lockFile) channel).checks.${system};

    # templates/init duplicates the files that carry placeholders, so its
    # defaults must keep reproducing templates/basic exactly.
    init-matches-basic = pkgs.runCommand "init-matches-basic" {} ''
      # cargo-generate derives `authors` from $USER and aborts without it.
      # vcs=none because the sandbox has no jj or git, and a repo would show
      # up in the diff.
      export HOME=$TMPDIR USER=nixbld
      cd $TMPDIR
      ${rust-toolchains.apps.${system}.init.program} --name rust-project --silent -d vcs=none
      diff -r ${templateSrc "basic"} rust-project
      touch $out
    '';
  in {
    checks.${system} =
      lib.concatMapAttrs (name: lockFile: checksFor name lockFile "stable" // checksFor name lockFile "nightly") lockFiles
      // {inherit init-matches-basic;};
  };
}
