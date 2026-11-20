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

    # The lockfile and skill dirs live in the working tree, not the store, so
    # they are found from the repo root at runtime.
    depth = path: builtins.length (lib.splitString "/" path);
    linkTarget = link: lib.concatStrings (lib.replicate (depth link) "../") + cfg.dir;

    prelude = ''
      dir=${lib.escapeShellArg cfg.dir}
      links=(${lib.escapeShellArgs cfg.linkDirs})
      targets=(${lib.escapeShellArgs (map linkTarget cfg.linkDirs)})

      die() {
        echo "$(basename "$0"): $*" >&2
        exit 1
      }

      find_lock() {
        root=$(git rev-parse --show-toplevel 2>/dev/null) || return 1
        lock="$root/${cfg.lockFile}"
        [ -f "$lock" ]
      }

      require_lock() {
        find_lock || die "no ${cfg.lockFile} at the root of a git repository"
        repo=$(jq -er '.repo' "$lock") || die "$lock has no repo"
        commit=$(jq -er '.commit' "$lock") || die "$lock has no commit"
        jq -e '.skills | type == "object"' "$lock" >/dev/null || die "$lock has no skills object"
        while IFS= read -r name; do
          valid_name "$name" || die "$lock lists an invalid skill name: $name"
        done < <(jq -r '.skills | keys[]' "$lock")
      }

      # Names end up in an `rm -rf` the user is told to run, so nothing that
      # could escape the skill dir gets through.
      valid_name() {
        [[ $1 =~ ^[A-Za-z0-9][A-Za-z0-9._-]*$ ]]
      }

      require_gh() {
        gh skill --help >/dev/null 2>&1 \
          || die "needs GitHub CLI with the 'gh skill' subcommand on PATH; install or upgrade gh"
      }

      # Plain bash, no subprocesses, so the shell hook stays fast.
      is_current() {
        local file=$1 want_commit=$2 want_tree=$3 line fences=0 pinned="" tree=""
        [ -f "$file" ] || return 1
        while IFS= read -r line; do
          if [ "$line" = "---" ]; then
            fences=$((fences + 1))
            [ "$fences" -eq 2 ] && break
            continue
          fi
          case $line in
            *"github-pinned: "*) pinned=''${line#*github-pinned: } ;;
            *"github-tree-sha: "*) tree=''${line#*github-tree-sha: } ;;
          esac
        done <"$file"
        [ "$pinned" = "$want_commit" ] && [ "$tree" = "$want_tree" ]
      }

      skill_entries() {
        jq -r '.skills | to_entries[] | "\(.key)\t\(.value)"' "$lock"
      }

      upstream_trees() {
        gh api "repos/$repo/contents/skills?ref=$1" \
          --jq '[.[] | select(.type == "dir") | {key: .name, value: .sha}] | from_entries'
      }

      write_lock() {
        jq '.skills |= (to_entries | sort_by(.key) | from_entries)' <<<"$1" >"$lock.tmp"
        mv "$lock.tmp" "$lock"
      }
    '';

    mkScript = name: text:
      pkgs.writeShellApplication {
        inherit name;
        runtimeInputs = [pkgs.jq pkgs.git pkgs.coreutils];
        # The prelude sets globals that only some of the scripts read.
        excludeShellChecks = ["SC2034"];
        text = prelude + text;
      };

    check = mkScript "skills-check" ''
          find_lock || exit 0
          require_lock

          stale=()
          while IFS=$'\t' read -r name tree; do
            [ "$tree" = null ] && continue
            ok=1
            is_current "$root/$dir/$name/SKILL.md" "$commit" "$tree" || ok=0
            for i in "''${!links[@]}"; do
              [ "$(readlink "$root/''${links[i]}/$name")" = "''${targets[i]}/$name" ] || ok=0
            done
            [ "$ok" = 1 ] || stale+=("$name")
          done < <(skill_entries)
          [ "''${#stale[@]}" -eq 0 ] && exit 0

          # gh refuses to overwrite an installed skill, and --force keeps files
          # the old version had, so the command clears each one first. gh skill
          # cannot symlink, so the per-agent dirs get relative links by hand.
          clear="rm -rf \"$dir/\$s\""
          link=""
          mkdirs=""
          for i in "''${!links[@]}"; do
            clear+=" \"''${links[i]}/\$s\""
            link+=" && ln -s \"''${targets[i]}/\$s\" \"''${links[i]}/\$s\""
            mkdirs+=" ''${links[i]}"
          done
          cat >&2 <<EOF
      rust-toolchains: ''${#stale[@]} agent skills in ${cfg.lockFile} are missing or not at the pinned commit.
      Download them from the repo root with:
        mkdir -p $dir$mkdirs && for s in ''${stale[*]}; do $clear && gh skill install $repo "skills/\$s" --pin $commit --dir $dir$link; done
      EOF
    '';

    bump = mkScript "skills-bump" ''
      require_gh
      require_lock

      ref=''${1:-}
      if [ -z "$ref" ]; then
        ref=$(gh api "repos/$repo/releases/latest" --jq '.tag_name')
      fi
      new_commit=$(gh api "repos/$repo/commits/$ref" --jq '.sha')
      upstream=$(upstream_trees "$new_commit")

      while IFS= read -r name; do
        echo "skills-bump: $name does not exist in $repo@$ref; it stays listed with a null tree and is not installed" >&2
      done < <(jq -r --argjson up "$upstream" '.skills | keys[] | select($up[.] == null)' "$lock")

      # A skill missing upstream keeps its entry, so bumping back to a ref
      # that has it restores it instead of silently shrinking the list.
      new=$(jq --arg ref "$ref" --arg commit "$new_commit" --argjson up "$upstream" '
        .ref = $ref
        | .commit = $commit
        | .skills |= with_entries(.value = $up[.key])
      ' "$lock")
      write_lock "$new"

      echo "skills-bump: ${cfg.lockFile} now pins $repo@$ref ($new_commit)"
      exec ${lib.getExe check}
    '';
  in {
    options.rust-toolchains.skills = {
      enable = lib.mkOption {
        type = lib.types.bool;
        default = true;
        description = "Whether to check the installed agent skills against the lockfile on shell entry, offline, and add skills-bump to the devshell.";
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
      rust-toolchains.devShell.packages = [bump];
      rust-toolchains.devShell.shellHook = lib.getExe check;
    };
  });
}
