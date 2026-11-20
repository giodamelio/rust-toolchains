# AGENTS.md

This project gets its Rust toolchain, devshell, git hooks and checks from [rust-toolchains](https://github.com/giodamelio/rust-toolchains) through `rust-toolchains.flakeModules.default`. Most tooling is defined there, not in this repo.

## Keep the shared toolchain

The user runs kache, a rustc wrapper cache that keys on the full `rustc -vV` output. Every project that uses rust-toolchains gets a byte-identical rustc, so they share cache entries.

- Do not add a `rust-toolchain.toml`, a rustup override, or another Rust toolchain to the devshell. Any of these breaks cache sharing.
- To switch to nightly, set `rust-toolchains.channel = "nightly";` in `flake.nix`.
- To pick up a newer pinned toolchain and tooling, run `nix flake update rust-toolchains`.
- Do not set `CARGO_TARGET_DIR` or any `KACHE_*` variable. The user's shell sets them per project.

## Work inside the devshell

Enter it with `nix develop`, or let direnv load it from `.envrc`. Run every cargo command inside it.

It provides `cargo`, `rustc`, `clippy`, `rustfmt`, `rust-analyzer`, `cargo-nextest`, `cargo-test-auto`, `cargo-unused-deps`, `cargo-shear`, `cargo-unused-dev-deps`, `cargo-deny`, `cargo-deny-check`, `alejandra` and `prek`.

To add a project-specific tool, append it to `rust-toolchains.devShell.packages` in `flake.nix`.

## Install the agent skills

`agent-skills.lock.json` lists the Rust agent skills this project uses and pins their source repo to one commit. The skill files live in `.agents/skills/`, and `.claude/skills/<name>` is a relative symlink to each one. Commit the lockfile, the skill files and the symlinks.

- Entering the devshell checks the installed skills against the lockfile, offline. If any are missing or stale, it says how many and tells you to run `skills-install`. Nothing is downloaded automatically.
- `skills-install` downloads each missing or stale skill at the pinned commit and recreates its `.claude/skills` symlink. It skips skills that are already current, so running it again does nothing.
- To add a skill, add `"name": null` to the lockfile's `skills` object and run `skills-bump` with the lockfile's current `ref`, which fills in its tree hash. Then run `skills-install`. To drop one, delete its entry, its `.agents/skills/<name>` directory and its `.claude/skills/<name>` symlink.
- Run `skills-bump` to move the pin to the source repo's latest release, or `skills-bump TAG` for a specific tag or commit. Then run `skills-install`.
- `skills-install` needs GitHub CLI with the `gh skill` subcommand. `skills-bump` also needs `gh auth login`.
- To opt out, delete `agent-skills.lock.json`, or set `rust-toolchains.skills.enable = false;`.

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

## Run the checks before you finish

- `prek run --all-files` runs rustfmt, clippy and alejandra, the pre-commit hooks.
- `prek run --all-files --hook-stage pre-push` also runs the tests, `cargo-unused-deps`, which fails on dependencies flagged by Cargo's `unused_dependencies` lint, `cargo-unused-dev-deps`, which runs cargo-shear for the dev-dependencies that lint skips, and `cargo-deny-check`, which checks advisories, licenses, banned crates and sources.
- To keep a dev-dependency that cargo-shear wrongly reports as unused, add it to `[package.metadata.cargo-shear] ignored = ["crate-name"]` in that crate's `Cargo.toml`.
- Keep `publish = false` in `Cargo.toml` unless the crate gets a `license` field. cargo-deny rejects unlicensed crates that could be published.
- To change cargo-deny's policy, set `rust-toolchains.cargoDeny.settings` in `flake.nix`, or add a `deny.toml`, which takes precedence.
- `nix flake check` runs fmt, clippy and tests in the Nix sandbox with the same toolchain.
- `cargo-test-auto` runs `cargo nextest run` when `.config/nextest.toml` exists, and `cargo test` otherwise.

If the repo uses jj, git hooks do not fire on jj commands, so run the prek commands yourself. `jj fix` formats Rust and Nix files with the same tools.

`prek.toml` is generated on shell entry and gitignored. To change hooks, edit `rust-toolchains.prek.hooks` in `flake.nix`, never `prek.toml`.

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
