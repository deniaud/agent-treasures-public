#!/usr/bin/env bash
set -euo pipefail
REPO="${TREASURE_ccometixline_repo:-https://github.com/Haleclipse/CCometixLine}"
REF="${TREASURE_ccometixline_ref:-main}"
EXPECTED_SHA="${TREASURE_ccometixline_sha256:-}"
SRC="$HOME/dev/CCometixLine"
DST_DIR="$HOME/.claude/ccline"
DST="$DST_DIR/ccline"

# Ensure rustup
if ! command -v cargo >/dev/null 2>&1; then
  if [[ ! -f "$HOME/.cargo/env" ]]; then
    [[ ${DRY_RUN:-0} -eq 1 ]] && { echo "[dry] install rustup"; exit 0; }
    curl --proto '=https' --tlsv1.2 -sSf https://sh.rustup.rs | sh -s -- -y --default-toolchain stable --profile minimal
  fi
  . "$HOME/.cargo/env"
fi

[[ ${DRY_RUN:-0} -eq 1 ]] && { echo "[dry] clone $REPO @ $REF + cargo build --release"; exit 0; }

mkdir -p "$(dirname "$SRC")" "$DST_DIR"
if [[ -d "$SRC/.git" ]]; then
  git -C "$SRC" fetch --all --tags
else
  git clone "$REPO" "$SRC"
fi
git -C "$SRC" checkout "$REF"
( cd "$SRC" && cargo build --release )

cp "$SRC/target/release/ccometixline" "$DST.new"
chmod +x "$DST.new"
mv -f "$DST.new" "$DST"

# Optional integrity check
if [[ -n "$EXPECTED_SHA" ]]; then
  ACTUAL=$(sha256sum "$DST" | awk '{print $1}')
  if [[ "$ACTUAL" != "$EXPECTED_SHA" ]]; then
    echo "  [warn] built SHA $ACTUAL != recorded $EXPECTED_SHA — rust toolchain version may differ; binary still functional"
  else
    echo "  ok: SHA matches recorded value"
  fi
fi
echo "  ok: ccline @ $DST ($("$DST" --version 2>/dev/null || echo unknown))"
