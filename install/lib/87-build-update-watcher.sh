#!/usr/bin/env bash
# Install build-update-{check,apply,gate}.sh into ~/.claude/scripts/.
# These are the runtime scripts that the claude() shell wrapper calls.
set -euo pipefail

SRC="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)/files/build-update"
DST="$HOME/.claude/scripts"

for f in build-update-check.sh build-update-apply.sh build-update-gate.sh; do
  [[ -f "$SRC/$f" ]] || { echo "[!] missing source: $SRC/$f"; exit 1; }
done

[[ ${DRY_RUN:-0} -eq 1 ]] && {
  echo "[dry] install build-update-check.sh + build-update-apply.sh + build-update-gate.sh → $DST/"
  exit 0
}

mkdir -p "$DST"
for f in build-update-check.sh build-update-apply.sh build-update-gate.sh; do
  install -m 0755 "$SRC/$f" "$DST/$f"
  echo "  ok: $DST/$f"
done
