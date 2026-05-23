#!/usr/bin/env bash
# Install cc-quote: TUI text-selection citation feature for Claude Code.
# Clones the source repo @ pin for diagnostics/dev, but the actual install
# is the published npm package — that's what the CLI looks for on its
# global path. Then `cc-quote apply` patches the Claude Code binary.
#
# Requires step 10 (claude-code) to be done — cc-quote apply patches CC's
# bundled JS and is version-pinned to the installed CC version.
set -euo pipefail

REPO="${TREASURE_cc_quote_repo:-https://github.com/deniaud/cc-quote}"
REF="${TREASURE_cc_quote_ref:-main}"
NPM_VER="${TREASURE_cc_quote_npm_version:-latest}"
TARGET="$HOME/dev/cc-quote"

[[ ${DRY_RUN:-0} -eq 1 ]] && {
  echo "[dry] clone $REPO @ $REF -> $TARGET && npm i -g cc-quote@$NPM_VER && cc-quote apply"
  exit 0
}

# 1. Source clone (for dev / diagnostics — npm package is what runs).
mkdir -p "$(dirname "$TARGET")"
if [[ -d "$TARGET/.git" ]]; then
  git -C "$TARGET" fetch --all --tags
else
  git clone "$REPO" "$TARGET"
fi
git -C "$TARGET" checkout "$REF"

# 2. Global npm install. Prefer pnpm if user has it (project uses pnpm-lock).
if command -v pnpm >/dev/null 2>&1; then
  pnpm add -g "cc-quote@$NPM_VER"
elif command -v npm >/dev/null 2>&1; then
  npm i -g "cc-quote@$NPM_VER"
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
