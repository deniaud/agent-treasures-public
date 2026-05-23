#!/usr/bin/env bash
set -euo pipefail
REPO="${TREASURE_tweakcc_fixed_repo:-https://github.com/skrabe/tweakcc-fixed}"
REF="${TREASURE_tweakcc_fixed_ref:-main}"
TARGET="$HOME/dev/tweakcc-fixed"

[[ ${DRY_RUN:-0} -eq 1 ]] && { echo "[dry] clone $REPO @ $REF -> $TARGET && npm i && npm run build"; exit 0; }

mkdir -p "$(dirname "$TARGET")"
if [[ -d "$TARGET/.git" ]]; then
  git -C "$TARGET" fetch --all --tags
else
  git clone "$REPO" "$TARGET"
fi
git -C "$TARGET" checkout "$REF"
( cd "$TARGET" && npm install --no-audit --no-fund && npm run build )
[[ -f "$TARGET/dist/index.mjs" ]] || { echo "[!] tweakcc-fixed build missing dist/index.mjs"; exit 1; }
echo "  ok: tweakcc-fixed ready @ $TARGET"
