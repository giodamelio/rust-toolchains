# rust-toolchains

Pinned Rust toolchains, flake-parts modules and project templates.

- Stable: fenix, at the revision in `flake.lock`.
- Nightly: pinned by date in `nightly.json`.
- Components: `rustc`, `cargo`, `clippy`, `rustfmt`, `rust-src`, `rust-analyzer`.
- Systems: `x86_64-linux`, `aarch64-linux`, `aarch64-darwin`.

## Start a new project

| Template | Description                                                                        | Docs                                      |
| -------- | ---------------------------------------------------------------------------------- | ----------------------------------------- |
| `basic`  | Rust binary.                                                                       | [basic README](templates/basic/README.md) |
| `axum`   | axum HTTP server with systemd socket activation, `Type=notify` and a NixOS module. | [axum README](templates/axum/README.md)   |

```sh
nix flake init -t github:giodamelio/rust-toolchains#<template>
nix run github:giodamelio/rust-toolchains#init
```

## Generate a project with init

| Option           | Values                                                                                                 | Default                        |
| ---------------- | ------------------------------------------------------------------------------------------------------ | ------------------------------ |
| `--template`     | `basic`, `axum`                                                                                        | asked, `basic` with `--silent` |
| `--name`         | crate name                                                                                             | asked                          |
| `channel`        | `stable`, `nightly`                                                                                    | `stable`                       |
| `modules`        | `prek`, `jjFix`, `checks`, `banner`, `unusedDeps`, `unusedDeps.devDependencies`, `cargoDeny`, `skills` | all                            |
| `install_skills` | `true`, `false`                                                                                        | `false`                        |
| `vcs`            | `jj`, `git`, `none` (those on `PATH`)                                                                  | `jj`, else `git`, else `none`  |
| `publish`        | `true`, `false`                                                                                        | `false`                        |
| `license`        | `MIT OR Apache-2.0`, `MIT`, `Apache-2.0`                                                               | `MIT OR Apache-2.0`            |

```sh
nix run github:giodamelio/rust-toolchains#init -- \
  --name my-tool --silent --template axum \
  -d channel=nightly -d modules=prek,checks,banner -d publish=true -d license=MIT
```

## Use a toolchain directly

```nix
devShells.${system}.default = pkgs.mkShell {
  packages = [rust-toolchains.packages.${system}.stable]; # or .nightly
};
```

## Configure the flake modules

`flakeModules.default` imports every module. Options live under `perSystem.rust-toolchains`.

| Module        | Adds                                                                          | Options                                                                                  |
| ------------- | ----------------------------------------------------------------------------- | ---------------------------------------------------------------------------------------- |
| `toolchain`   | the pinned toolchain and a matching `rustPlatform`                            | `channel`, `toolchain`, `rustPlatform`                                                   |
| `test-runner` | `cargo-test-auto` (nextest if `.config/nextest.toml`)                         | `testRunner`                                                                             |
| `devshell`    | `devShells.default`                                                           | `devShell.packages`, `devShell.shellHook`                                                |
| `prek`        | pre-commit and pre-push hooks                                                 | `prek.enable`, `prek.hooks.<id>`                                                         |
| `jj-fix`      | `jj fix` tools for rustfmt and alejandra                                      | `jjFix.enable`, `jjFix.edition`, `jjFix.tools.<name>`                                    |
| `checks`      | `rust-build`, `rust-fmt`, `rust-clippy`, `rust-test`                          | `checks.enable`, `checks.package`, `checks.nativeBuildInputs`, `checks.buildInputs`      |
| `formatter`   | `formatter` set to alejandra                                                  |                                                                                          |
| `banner`      | a box of common commands on shell entry                                       | `banner.enable`, `banner.title`, `banner.commands`                                       |
| `unused-deps` | `cargo-unused-deps`, `cargo-unused-dev-deps` (pre-push)                       | `unusedDeps.enable`, `unusedDeps.package`, `unusedDeps.devDependencies.{enable,package}` |
| `cargo-deny`  | `cargo-deny-check` (pre-push)                                                 | `cargoDeny.enable`, `cargoDeny.settings`                                                 |
| `skills`      | an offline agent skills check on shell entry, `skills-install`, `skills-bump` | `skills.enable`, `skills.lockFile`, `skills.dir`, `skills.linkDirs`                      |

## Manage agent skills

- `agent-skills.lock.json` pins a skill repo commit and each skill's tree hash.
- Skills live in `.agents/skills/`, symlinked from `.claude/skills/`.
- `skills-install` downloads missing or stale skills with `gh skill`.
- `skills-bump [TAG]` moves the pin. It needs `gh auth login`.

## Maintain this repo

| Task                         | Command                                |
| ---------------------------- | -------------------------------------- |
| Bump stable                  | `nix flake update fenix`               |
| Bump nightly                 | `bump-nightly [YYYY-MM-DD]`            |
| Bump the templates' skills   | `bump-template-skills [TAG]`           |
| Refresh `tests/*/Cargo.lock` | `refresh-test-lockfiles [TEMPLATE...]` |
| Check every output           | `nix flake check --all-systems`        |
| Check the templates          | `nix flake check '.?dir=tests'`        |
| Format                       | `nix fmt`                              |

CI enables KVM for the NixOS VM tests and runs both checks and `nix fmt -- --fail-on-change`.
