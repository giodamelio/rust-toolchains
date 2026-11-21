# AGENTS.md

This project gets its Rust toolchain, devshell, git hooks and checks from [rust-toolchains](https://github.com/giodamelio/rust-toolchains) through `rust-toolchains.flakeModules.default`. Most tooling is defined there, not in this repo.

The crate is an axum HTTP server with one route, `GET /health`, which returns `ok`. It is started by systemd socket activation, tells systemd when it is ready, and shuts down gracefully on SIGTERM and Ctrl-C.

## Run the server locally

Run `cargo run`. Without socket activation, the server binds `LISTEN_ADDR`, or `127.0.0.1:8000` when that is unset:

```sh
cargo run
curl 127.0.0.1:8000/health
LISTEN_ADDR=127.0.0.1:8080 cargo run
```

Set the log level with `RUST_LOG`, for example `RUST_LOG=debug`. The default is `info`.

To try socket activation without installing anything, run the binary under `systemd-socket-activate`, which listens on the address and starts the server on the first connection:

```sh
cargo build
systemd-socket-activate -l 127.0.0.1:3001 "$(cargo metadata --format-version 1 | jq -r .target_directory)/debug/<crate-name>"
```

## Understand socket activation and readiness

- systemd owns the listening socket. The `.socket` unit binds it and passes it to the service as fd 3, described by `LISTEN_FDS` and `LISTEN_PID`. `main` takes it with the `listenfd` crate, which validates it is a TCP listener, before the tokio runtime starts, because reading those variables unsets them.
- The fd is set non-blocking before it is handed to tokio, because systemd passes it in blocking mode.
- Only when `LISTEN_FDS` is absent does the server bind an address itself. Under the NixOS module, `SocketBindDeny=any` makes that fallback fail loudly instead of listening on the wrong address.
- The service is `Type=notify`. Once the listener and signal handlers are ready, `sd-notify` sends `READY=1`, and systemd only marks the unit active after that. On shutdown it sends `STOPPING=1`. Both are no-ops when `NOTIFY_SOCKET` is unset, as under `cargo run`.
- Keep slow startup work, such as connecting to a database or running migrations, before `READY=1`, so systemd only reports the unit active once it can serve requests. Connections that arrive meanwhile wait in the socket's backlog.

## Deploy with the NixOS module

`flake.nix` exports `nixosModules.default`. Its options are named after `package.name` in `Cargo.toml`:

- `services.<crate-name>.enable` adds the `<crate-name>.socket` and `<crate-name>.service` units.
- `services.<crate-name>.listenStream` is the socket's `ListenStream=`, by default `127.0.0.1:8000`.
- `services.<crate-name>.package` is the server package, by default this flake's `packages.default`.

The service runs with `DynamicUser`, `ProtectSystem=strict` and further sandboxing. If new code needs to write files, add a `StateDirectory=` or similar rather than loosening the sandbox. If it needs a new address family or system call, relax `RestrictAddressFamilies` or `SystemCallFilter` as narrowly as possible.

The `nixos-vm` check, on `x86_64-linux` only, boots a VM with the module enabled. It checks that the service stays inactive until the first request, answers `/health`, reaches the active state under `Type=notify`, and logs its graceful shutdown on stop. It needs a builder with KVM. Run it on its own with:

```sh
nix build .#checks.x86_64-linux.nixos-vm
```

When you add routes or startup steps, extend the test script in `flake.nix` with them.

## Keep the shared toolchain

The user runs kache, a rustc wrapper cache that keys on the full `rustc -vV` output. Every project that uses rust-toolchains gets a byte-identical rustc, so they share cache entries.

- Do not add a `rust-toolchain.toml`, a rustup override, or another Rust toolchain to the devshell. Any of these breaks cache sharing.
- To switch to nightly, set `rust-toolchains.channel = "nightly";` in `flake.nix`.
- To pick up a newer pinned toolchain and tooling, run `nix flake update rust-toolchains`.
- Do not set `CARGO_TARGET_DIR` or any `KACHE_*` variable. The user's shell sets them per project.

## Work inside the devshell

Enter it with `nix develop`, or let direnv load it from `.envrc`. Run every cargo command inside it.

It provides:

- `cargo`, `rustc`, `clippy`, `rustfmt` and `rust-analyzer`, from the pinned toolchain
- `cargo-nextest` and `cargo-test-auto`
- `alejandra` and `prek`
- `cargo-unused-deps`, `cargo-shear` and `cargo-unused-dev-deps` <!-- module:unusedDeps -->
- `cargo-deny` and `cargo-deny-check` <!-- module:cargoDeny -->
- `skills-install` and `skills-bump` <!-- module:skills -->

To add a project-specific tool, append it to `rust-toolchains.devShell.packages` in `flake.nix`.

<!-- module:skills -->

## Install the agent skills

`agent-skills.lock.json` lists the Rust agent skills this project uses and pins their source repo to one commit. The skill files live in `.agents/skills/`, and `.claude/skills/<name>` is a relative symlink to each one. Commit the lockfile, the skill files and the symlinks.

- Entering the devshell checks the installed skills against the lockfile, offline. If any are missing or stale, it says how many and tells you to run `skills-install`. Nothing is downloaded automatically.
- `skills-install` downloads each missing or stale skill at the pinned commit and recreates its `.claude/skills` symlink. It skips skills that are already current, so running it again does nothing.
- To add a skill, add `"name": null` to the lockfile's `skills` object and run `skills-bump` with the lockfile's current `ref`, which fills in its tree hash. Then run `skills-install`. To drop one, delete its entry, its `.agents/skills/<name>` directory and its `.claude/skills/<name>` symlink.
- Run `skills-bump` to move the pin to the source repo's latest release, or `skills-bump TAG` for a specific tag or commit. Then run `skills-install`.
- `skills-install` needs GitHub CLI with the `gh skill` subcommand. `skills-bump` also needs `gh auth login`.
- To opt out, delete `agent-skills.lock.json`, or set `rust-toolchains.skills.enable = false;`.

<!-- /module:skills -->

<!-- module:banner -->

## Keep the devshell banner current

Entering the devshell prints a box of common commands, titled with the crate name. When the project gains a CLI, script or workflow command someone will run often, add it to `rust-toolchains.banner.commands` in `flake.nix`:

```nix
rust-toolchains.banner.commands = [
  {
    command = "cargo run -- serve";
    description = "Start the server";
  }
];
```

Remove entries when the command they describe goes away.

<!-- /module:banner -->

## Run the checks before you finish

- `prek run --all-files` runs rustfmt, clippy and alejandra, the pre-commit hooks. <!-- module:prek -->
- `prek run --all-files --hook-stage pre-push` also runs the pre-push hooks, which are the commands below. <!-- module:prek -->
- `cargo-test-auto` runs `cargo nextest run` when `.config/nextest.toml` exists, and `cargo test` otherwise.
- `cargo-unused-deps` fails on dependencies flagged by Cargo's `unused_dependencies` lint. <!-- module:unusedDeps -->
- `cargo-unused-dev-deps` runs cargo-shear for the dev-dependencies that lint skips. To keep a dev-dependency that cargo-shear wrongly reports as unused, add it to `[package.metadata.cargo-shear] ignored = ["crate-name"]` in that crate's `Cargo.toml`. <!-- module:unusedDeps -->
- `cargo-deny-check` checks advisories, licenses, banned crates and sources. To change its policy, set `rust-toolchains.cargoDeny.settings` in `flake.nix`, or add a `deny.toml`, which takes precedence. If you vendor crates with a `[source.crates-io] replace-with` in `.cargo/config.toml`, cargo-deny cannot check for yanked crates and warns `index-failure` for each one, so set `rust-toolchains.cargoDeny.settings.advisories.yanked = "allow";`. <!-- module:cargoDeny -->
- Keep `publish = false` in `Cargo.toml` unless the crate gets a `license` field. cargo-deny rejects unlicensed crates that could be published. <!-- module:cargoDeny -->

<!-- module:checks -->

`nix flake check` runs fmt, clippy and tests in the Nix sandbox with the same toolchain.

<!-- /module:checks -->

On `x86_64-linux`, `nix flake check` runs the `nixos-vm` test.

<!-- module:prek -->

If the repo uses jj, git hooks do not fire on jj commands, so run the prek commands yourself. To have `prek run --all-files` run the pre-push hooks too, set `rust-toolchains.prek.allHooksInPreCommit = true;` in `flake.nix`.

`prek.toml` is generated on shell entry and gitignored. To change hooks, edit `rust-toolchains.prek.hooks` in `flake.nix`, never `prek.toml`.

<!-- /module:prek -->

<!-- module:jjFix -->

If the repo uses jj, `jj fix` formats Rust and Nix files with rustfmt and alejandra.

<!-- /module:jjFix -->

## Commit the lockfile

`Cargo.lock` belongs in version control. `packages.default` and the flake checks read it, so `nix build` and `nix flake check` fail until it exists and is tracked.

## Contribute tooling improvements back

When you improve tooling that is not specific to this project, such as hooks, devshell packages, checks, lints or flake structure, it probably belongs in rust-toolchains so every project gets it.

1. Ask the user whether to send the improvement upstream. Describe it in one or two sentences.

2. If the user approves, send it with `agent-dms`. Name this project, say what changed and why, and include the relevant diff or file contents:

   ```sh
   agent-dms send rust-toolchains -s "Add cargo-deny check to the flake module" <<'EOF'
   From <project>: ...
   EOF
   ```

3. Keep the local change until rust-toolchains ships it, then remove the local copy and run `nix flake update rust-toolchains`.

Never send anything without the user's approval. If `agent-dms` is not available, tell the user what you would have sent instead.
