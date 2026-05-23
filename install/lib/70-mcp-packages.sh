#!/usr/bin/env bash
set -euo pipefail
# Install pinned MCP packages with integrity verification.
# Reads ~/.claude/mcp/package.json + package-lock.json (placed by 80-apply-home.sh).
# Run AFTER 80-apply-home.sh so package.json is in place.

PKG_DIR="$HOME/.claude/mcp"
if [[ ! -f "$PKG_DIR/package.json" ]]; then
  echo "  [skip] $PKG_DIR/package.json not yet present (apply-home runs after this step? — re-run install.sh)"
  exit 0
fi
[[ ${DRY_RUN:-0} -eq 1 ]] && { echo "[dry] cd $PKG_DIR && npm ci"; exit 0; }
cd "$PKG_DIR"
if [[ -f package-lock.json ]]; then
  npm ci --no-audit --no-fund
else
  npm install --no-audit --no-fund
fi
echo "  ok: MCP packages installed at pinned versions"
