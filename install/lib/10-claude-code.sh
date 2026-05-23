#!/usr/bin/env bash
set -euo pipefail

if command -v claude >/dev/null 2>&1; then
  echo "  ok: claude already installed ($(claude --version 2>&1 | head -1))"
  exit 0
fi
[[ ${DRY_RUN:-0} -eq 1 ]] && { echo "[dry] curl https://claude.ai/install.sh | bash"; exit 0; }
echo "  running official Claude Code installer..."
curl -fsSL https://claude.ai/install.sh | bash
case ":$PATH:" in
  *":$HOME/.local/bin:"*) ;;
  *) echo "  [!] add to your shell rc:  export PATH=\"\$HOME/.local/bin:\$PATH\"" ;;
esac
