#!/usr/bin/env bash
set -euo pipefail
# Skills in ~/.claude/skills/, ~/.config/opencode/skills/, ~/.codex/skills/
# point to ~/.cc-switch/skills/<name> via symlinks. Manifests are generated
# by snapshot-recipe.sh (`gen_symlinks_manifest`); this script re-creates the
# symlinks against the local cc-switch tree on each pull.

apply_manifest() {
  local manifest="$1" target_dir="$2"
  if [[ ! -f "$manifest" ]]; then
    echo "  [skip] no $manifest"
    return 0
  fi
  if [[ ${DRY_RUN:-0} -eq 1 ]]; then
    echo "[dry] would re-create symlinks in $target_dir from $manifest"
    return 0
  fi
  mkdir -p "$target_dir"
  while IFS= read -r line; do
    [[ -z "$line" || "${line:0:1}" == "#" ]] && continue
    local name="${line%% -> *}"
    local target_name="${line##* -> }"
    local link="$target_dir/$name"
    local target="$HOME/.cc-switch/skills/$target_name"
    if [[ ! -d "$target" ]]; then
      echo "  [warn] $target missing — skill '$name' will be broken until cc-switch syncs"
    fi
    [[ -e "$link" || -L "$link" ]] && rm -f "$link"
    ln -sfn "$target" "$link"
    echo "  ln -sfn $target $link"
  done < "$manifest"
}

apply_manifest "$HOME/.claude/skills/_symlinks.txt"           "$HOME/.claude/skills"
apply_manifest "$HOME/.config/opencode/skills/_symlinks.txt"  "$HOME/.config/opencode/skills"
apply_manifest "$HOME/.codex/skills/_symlinks.txt"            "$HOME/.codex/skills"
