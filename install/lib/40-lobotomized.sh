#!/usr/bin/env bash
set -euo pipefail
REPO="${TREASURE_lobotomized_repo:-https://github.com/skrabe/lobotomized-claude-code}"
REF="${TREASURE_lobotomized_ref:-main}"
TARGET="$HOME/.tweakcc/lobotomized-claude-code"

[[ ${DRY_RUN:-0} -eq 1 ]] && { echo "[dry] clone $REPO @ $REF -> $TARGET + symlinks"; exit 0; }

mkdir -p "$HOME/.tweakcc"
if [[ -d "$TARGET/.git" ]]; then
  git -C "$TARGET" fetch --all
else
  git clone "$REPO" "$TARGET"
fi
git -C "$TARGET" checkout "$REF"

for name in system-prompts system-reminders; do
  link="$HOME/.tweakcc/$name"; dest="$TARGET/$name"
  [[ -d "$dest" ]] || continue
  [[ -e "$link" || -L "$link" ]] && rm -f "$link"
  ln -s "$dest" "$link"
  echo "  ln -s $dest $link"
done
echo "  ok: lobotomized-claude-code @ $TARGET"
