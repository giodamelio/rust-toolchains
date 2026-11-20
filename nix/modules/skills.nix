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
    prelude = ''
      dirs=(${lib.escapeShellArgs cfg.dirs})

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

      # Names become paths that skills-install deletes, so nothing that could
      # escape the skill dir gets through.
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

    install = mkScript "skills-install" ''
      require_gh
      require_lock

      installed=0
      current=0
      while IFS=$'\t' read -r name tree; do
        for dir in "''${dirs[@]}"; do
          target="$root/$dir"
          if [ "$tree" = null ]; then
            echo "skills-install: $name does not exist at $repo@$commit, so it is not installed" >&2
            rm -rf "''${target:?}/$name"
            continue
          fi
          if is_current "$target/$name/SKILL.md" "$commit" "$tree"; then
            current=$((current + 1))
            continue
          fi
          # gh refuses to overwrite without --force, and --force leaves files
          # the old version had, so the stale copy goes first.
          rm -rf "''${target:?}/$name"
          if ! out=$(gh skill install "$repo" "skills/$name" --pin "$commit" --dir "$target" </dev/null 2>&1); then
            printf '%s\n' "$out" >&2
            die "gh skill install failed for $name"
          fi
          is_current "$target/$name/SKILL.md" "$commit" "$tree" \
            || die "$dir/$name was installed but its SKILL.md does not record commit $commit and tree $tree"
          echo "installed $dir/$name"
          installed=$((installed + 1))
        done
      done < <(skill_entries)

      echo "skills-install: $installed installed, $current already at $repo@$commit"
      if [ "$installed" -gt 0 ]; then
        echo "Skills are not verified by GitHub. Review them with: gh skill preview $repo <skill>@$commit"
      fi
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
      exec ${lib.getExe install}
    '';

    add = mkScript "skills-add" ''
      [ "$#" -gt 0 ] || die "usage: skills-add SKILL..."
      require_gh
      require_lock

      upstream=$(upstream_trees "$commit")
      for name in "$@"; do
        valid_name "$name" || die "invalid skill name: $name"
        jq -e --arg name "$name" '.[$name] != null' <<<"$upstream" >/dev/null \
          || die "$name does not exist in $repo@$commit"
      done

      new=$(jq --argjson up "$upstream" --args '
        reduce $ARGS.positional[] as $name (.; .skills[$name] = $up[$name])
      ' "$@" <"$lock")
      write_lock "$new"
      exec ${lib.getExe install}
    '';

    remove = mkScript "skills-remove" ''
      [ "$#" -gt 0 ] || die "usage: skills-remove SKILL..."
      require_lock

      for name in "$@"; do
        valid_name "$name" || die "invalid skill name: $name"
        jq -e --arg name "$name" '.skills | has($name)' "$lock" >/dev/null \
          || die "$name is not in ${cfg.lockFile}"
      done

      new=$(jq --args 'reduce $ARGS.positional[] as $name (.; del(.skills[$name]))' "$@" <"$lock")
      write_lock "$new"
      for name in "$@"; do
        for dir in "''${dirs[@]}"; do
          rm -rf "''${root:?}/$dir/$name"
        done
        echo "removed $name"
      done
    '';

    check = mkScript "skills-check" ''
      find_lock || exit 0

      commit=$(jq -r '.commit' "$lock")
      total=0
      stale=0
      while IFS=$'\t' read -r name tree; do
        [ "$tree" = null ] && continue
        for dir in "''${dirs[@]}"; do
          total=$((total + 1))
          is_current "$root/$dir/$name/SKILL.md" "$commit" "$tree" || stale=$((stale + 1))
        done
      done < <(skill_entries)

      if [ "$stale" -gt 0 ]; then
        echo "rust-toolchains: $stale of $total agent skills in ${cfg.lockFile} are missing or not at the pinned commit. Run skills-install." >&2
      fi
    '';
  in {
    options.rust-toolchains.skills = {
      enable = lib.mkOption {
        type = lib.types.bool;
        default = true;
        description = "Whether to add the skills-* scripts to the devshell and check the installed agent skills on shell entry.";
      };
      lockFile = lib.mkOption {
        type = lib.types.str;
        default = "agent-skills.lock.json";
        description = ''
          Lockfile naming the skill source repo, its pinned commit and the skills to install, relative to the repo root.
          A string rather than a Nix path because skills-bump rewrites it in the working tree.
        '';
      };
      dirs = lib.mkOption {
        type = lib.types.listOf lib.types.str;
        default = [".claude/skills"];
        description = ''
          Directories, relative to the repo root, that every skill is installed into.
          `.claude/skills` is read by Claude Code; `.agents/skills` by Copilot, Codex, Cursor, Gemini CLI, OpenCode and others.
          Keep them gitignored.
        '';
      };
    };

    config = lib.mkIf cfg.enable {
      rust-toolchains.devShell.packages = [install bump add remove];
      rust-toolchains.devShell.shellHook = lib.getExe check;
    };
  });
}
