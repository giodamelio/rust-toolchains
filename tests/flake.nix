{
  description = "Builds and checks templates/basic against this checkout of rust-toolchains";

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

    # Its own store path so edits elsewhere in the repo do not rebuild the checks.
    template = builtins.path {
      name = "template-basic";
      path = "${rust-toolchains}/templates/basic";
    };

    # Import-from-derivation: the template's flake.nix reads ./Cargo.lock
    # relative to itself, and templates/ must never contain one.
    tree = pkgs.runCommand "rust-toolchains-template-basic" {nativeBuildInputs = [rust-toolchains.packages.${system}.stable];} ''
      cp -r ${template} $out
      chmod -R u+w $out
      HOME=$TMPDIR cargo generate-lockfile --offline --manifest-path $out/Cargo.toml
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

    evalTemplate = channel: let
      inputs = {
        inherit nixpkgs rust-toolchains;
        flake-parts = withChannel channel;
        self =
          outputs
          // {
            inherit inputs outputs;
            outPath = tree;
          };
      };
      outputs = (import "${tree}/flake.nix").outputs inputs;
    in
      outputs;

    checksFor = channel:
      pkgs.lib.mapAttrs' (name: pkgs.lib.nameValuePair "${channel}-${name}")
      (evalTemplate channel).checks.${system};

    # templates/init duplicates the files that carry placeholders, so its
    # defaults must keep reproducing templates/basic exactly.
    init-matches-basic = pkgs.runCommand "init-matches-basic" {} ''
      # cargo-generate derives `authors` from $USER and aborts without it.
      export HOME=$TMPDIR USER=nixbld
      cd $TMPDIR
      ${rust-toolchains.apps.${system}.init.program} --name rust-project --silent
      diff -r ${template} rust-project
      touch $out
    '';
  in {
    checks.${system} = checksFor "stable" // checksFor "nightly" // {inherit init-matches-basic;};
  };
}
