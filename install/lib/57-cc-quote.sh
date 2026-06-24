#!/usr/bin/env bash
# Install cc-quote: TUI text-selection citation feature for Claude Code.
# Distributed via git, NOT npm — the package was never published to the
# registry. We clone the source @ pin, build it (dist/ is gitignored, so it
# must be produced here), and install the built package globally so the
# `cc-quote` CLI lands on $PATH. Then `cc-quote apply` patches the CC binary.
#
# Requires step 10 (claude-code) to be done — cc-quote apply patches CC's
# bundled JS and is version-pinned to the installed CC version.
set -euo pipefail

REPO="${TREASURE_cc_quote_repo:-https://github.com/deniaud/cc-quote}"
REF="${TREASURE_cc_quote_ref:-main}"
TARGET="$HOME/dev/cc-quote"

[[ ${DRY_RUN:-0} -eq 1 ]] && {
  echo "[dry] clone $REPO @ $REF -> $TARGET && build from source && npm i -g . && cc-quote apply"
  exit 0
}

# 1. Source clone + checkout pin.
mkdir -p "$(dirname "$TARGET")"
if [[ -d "$TARGET/.git" ]]; then
  git -C "$TARGET" fetch --all --tags
else
  git clone "$REPO" "$TARGET"
fi
git -C "$TARGET" checkout "$REF"

# 2. Build from source, then install the built package globally. Prefer pnpm
#    (repo ships pnpm-lock.yaml); npm is the fallback. `npm i -g <dir>` packs
#    per the package.json "files" list (dist/ + README/LICENSE/docs), so the
#    build must run first.
if command -v pnpm >/dev/null 2>&1; then
  pnpm -C "$TARGET" install --frozen-lockfile
  pnpm -C "$TARGET" run build
  npm i -g "$TARGET"
elif command -v npm >/dev/null 2>&1; then
  (cd "$TARGET" && npm install && npm run build && npm i -g .)
else
  echo "[!] neither pnpm nor npm available — install Node.js first"
  exit 1
fi

# 3. Patch the Claude Code binary. cc-quote apply makes a backup at
#    ~/.cc-quote/backup-<ccVersion>.bin first, so this is reversible
#    via `cc-quote restore`.
if command -v cc-quote >/dev/null 2>&1; then
  cc-quote apply
  cc-quote status | head -5 || true
else
  echo "[!] cc-quote not on PATH after install — check global npm bin dir"
  exit 1
fi
