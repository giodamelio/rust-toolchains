{
  pkgs,
  lib,
  lockFile ? "agent-skills.lock.json",
  dir ? ".agents/skills",
  linkDirs ? [".claude/skills"],
  # rust-toolchains bumps its templates' lockfiles without installing their
  # skills, so checking for installed skills there would always complain.
  checkAfterBump ? true,
}: let
  # The lockfile and skill dirs live in the working tree, not the store, so
  # they are found from the repo root at runtime.
  depth = path: builtins.length (lib.splitString "/" path);
  linkTarget = link: lib.concatStrings (lib.replicate (depth link) "../") + dir;

  prelude = ''
    dir=${lib.escapeShellArg dir}
    links=(${lib.escapeShellArgs linkDirs})
    targets=(${lib.escapeShellArgs (map linkTarget linkDirs)})

    die() {
      echo "$(basename "$0"): $*" >&2
      exit 1
    }

    # init sets the override because a project created without a repo may
    # sit inside someone else's. jj comes from the user's PATH, so a
    # non-colocated jj repo, which git cannot see, still resolves when jj is
    # installed.
    find_lock() {
      root=''${RUST_TOOLCHAINS_SKILLS_ROOT:-}
      [ -n "$root" ] \
        || root=$(git rev-parse --show-toplevel 2>/dev/null) \
        || root=$(jj root 2>/dev/null) \
        || root=$PWD
      lock="$root/${lockFile}"
      [ -f "$lock" ]
    }

    require_lock() {
      find_lock || die "no ${lockFile} at the repo root ($root)"
      repo=$(jq -er '.repo' "$lock") || die "$lock has no repo"
      commit=$(jq -er '.commit' "$lock") || die "$lock has no commit"
      jq -e '.skills | type == "object"' "$lock" >/dev/null || die "$lock has no skills object"
      while IFS= read -r name; do
        valid_name "$name" || die "$lock lists an invalid skill name: $name"
      done < <(jq -r '.skills | keys[]' "$lock")
    }

    # Names end up in `rm -rf`, so nothing that could escape the skill dir
    # gets through.
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

    is_installed() {
      local name=$1 tree=$2 i
      is_current "$root/$dir/$name/SKILL.md" "$commit" "$tree" || return 1
      for i in "''${!links[@]}"; do
        [ "$(readlink "$root/''${links[i]}/$name")" = "''${targets[i]}/$name" ] || return 1
      done
    }

    # A null tree marks a skill missing upstream at the pinned commit, which
    # cannot be installed, so it is left out everywhere.
    skill_entries() {
      jq -r '.skills | to_entries[] | select(.value != null) | "\(.key)\t\(.value)"' "$lock"
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
in rec {
  check = mkScript "skills-check" ''
    find_lock || exit 0
    require_lock

    total=0
    stale=0
    while IFS=$'\t' read -r name tree; do
      total=$((total + 1))
      is_installed "$name" "$tree" || stale=$((stale + 1))
    done < <(skill_entries)
    [ "$stale" -eq 0 ] && exit 0

    echo "rust-toolchains: $stale of $total agent skills in ${lockFile} are missing or not at the pinned commit. Run skills-install." >&2
  '';

  install = mkScript "skills-install" ''
    require_lock
    require_gh

    total=0
    installed=()
    while IFS=$'\t' read -r name tree; do
      total=$((total + 1))
      is_installed "$name" "$tree" && continue

      # gh refuses to overwrite an installed skill, and --force keeps files
      # the old version had, so each one is cleared first. gh skill cannot
      # symlink, so the per-agent dirs get relative links by hand.
      rm -rf "''${root:?}/$dir/$name"
      for i in "''${!links[@]}"; do
        rm -rf "''${root:?}/''${links[i]}/$name"
      done
      mkdir -p "$root/$dir"
      echo "skills-install: installing $name" >&2
      # stdin is the lockfile loop, which gh must not consume. Its output is
      # kept for failures only, since it repeats the same warning per skill.
      if ! out=$(gh skill install "$repo" "skills/$name" --pin "$commit" --dir "$root/$dir" </dev/null 2>&1); then
        echo "$out" >&2
        die "gh skill install failed for $name"
      fi
      for i in "''${!links[@]}"; do
        mkdir -p "$root/''${links[i]}"
        ln -s "''${targets[i]}/$name" "$root/''${links[i]}/$name"
      done
      is_installed "$name" "$tree" \
        || die "$name was installed, but $dir/$name/SKILL.md does not record commit $commit and tree $tree"
      installed+=("$name")
    done < <(skill_entries)

    if [ "''${#installed[@]}" -eq 0 ]; then
      echo "skills-install: all $total agent skills are already at $repo@$commit"
      exit 0
    fi
    echo "skills-install: installed ''${#installed[@]} of $total agent skills from $repo@$commit"
    echo "Skills are third-party and unverified. Review one with: gh skill preview $repo <skill>@$commit"
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

    echo "skills-bump: ${lockFile} now pins $repo@$ref ($new_commit)"
    ${lib.optionalString checkAfterBump "exec ${lib.getExe check}"}
  '';
}
