{modules, ...}: {
  lib,
  flake-parts-lib,
  ...
}: {
  imports = [modules.devshell];

  options.perSystem = flake-parts-lib.mkPerSystemOption ({
    config,
    pkgs,
    ...
  }: let
    cfg = config.rust-toolchains.skills;
    scripts = import ../lib/skills.nix {
      inherit pkgs lib;
      inherit (cfg) lockFile dir linkDirs;
    };
  in {
    options.rust-toolchains.skills = {
      enable = lib.mkOption {
        type = lib.types.bool;
        default = true;
        description = "Whether to check the installed agent skills against the lockfile on shell entry, offline, and add skills-install and skills-bump to the devshell.";
      };
      lockFile = lib.mkOption {
        type = lib.types.str;
        default = "agent-skills.lock.json";
        description = ''
          Lockfile naming the skill source repo, its pinned commit and the skills to install, relative to the repo root.
          A string rather than a Nix path because skills-bump rewrites it in the working tree.
        '';
      };
      dir = lib.mkOption {
        type = lib.types.str;
        default = ".agents/skills";
        description = ''
          Directory, relative to the repo root, that skills are installed into.
          `.agents/skills` is read by Copilot, Codex, Cursor, Gemini CLI, OpenCode and others.
        '';
      };
      linkDirs = lib.mkOption {
        type = lib.types.listOf lib.types.str;
        default = [".claude/skills"];
        description = ''
          Directories, relative to the repo root, that get a relative symlink to each skill in `dir`,
          for agents that do not read `.agents/skills`. `.claude/skills` is read by Claude Code.
        '';
      };
    };

    config = lib.mkIf cfg.enable {
      rust-toolchains.devShell.packages = [scripts.install scripts.bump];
      rust-toolchains.devShell.shellHook = lib.getExe scripts.check;
    };
  });
}
