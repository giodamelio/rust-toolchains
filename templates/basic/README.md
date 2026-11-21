# rust-project

A Rust binary on [rust-toolchains](https://github.com/giodamelio/rust-toolchains).

## Use the project

- Enter the devshell: `nix develop`, or `direnv allow`.
- Build and run: `cargo run`.
- Test: `cargo-test-auto`.
- Create the lockfile, then commit it: `nix develop -c cargo generate-lockfile`.
- Run the pre-commit hooks: `prek run --all-files`. <!-- module:prek -->
- Run the pre-push hooks: `prek run --all-files --hook-stage pre-push`. <!-- module:prek -->
- Check in the Nix sandbox: `nix flake check`. <!-- module:checks -->
- Update the tooling: `nix flake update rust-toolchains`.

## Configure the project

- Rename the crate: `name` in `Cargo.toml` and `pname` in `flake.nix`.
- Switch to nightly: `rust-toolchains.channel = "nightly";` in `flake.nix`.
- Everything else: the [rust-toolchains module reference](https://github.com/giodamelio/rust-toolchains#configure-the-flake-modules).
