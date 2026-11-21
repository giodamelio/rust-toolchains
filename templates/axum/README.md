# rust-project

An axum HTTP server on [rust-toolchains](https://github.com/giodamelio/rust-toolchains), with one route, `GET /health`. It takes its socket from systemd socket activation and runs as `Type=notify`.

## Use the project

- Enter the devshell: `nix develop`, or `direnv allow`.
- Run the server: `cargo run`, which listens on `LISTEN_ADDR`, by default `127.0.0.1:8000`.
- Test: `cargo-test-auto`.
- Create the lockfile, then commit it: `nix develop -c cargo generate-lockfile`.
- Run the pre-commit hooks: `prek run --all-files`.
- Run the pre-push hooks: `prek run --all-files --hook-stage pre-push`.
- Check in the Nix sandbox: `nix flake check`.
- Run the NixOS VM test, which needs KVM: `nix build .#checks.x86_64-linux.nixos-vm`.
- Update the tooling: `nix flake update rust-toolchains`.

## Deploy with the NixOS module

`nixosModules.default` has these options:

- `services.<crate-name>.enable`: a `.socket` unit and a `Type=notify` `.service` unit.
- `services.<crate-name>.listenStream`: by default `127.0.0.1:8000`.
- `services.<crate-name>.package`: by default `packages.default`.

## Configure the project

- Rename the crate: `name` in `Cargo.toml`.
- Switch to nightly: `rust-toolchains.channel = "nightly";` in `flake.nix`.
- Everything else: the [rust-toolchains module reference](https://github.com/giodamelio/rust-toolchains#configure-the-flake-modules).
