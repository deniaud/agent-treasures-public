#!/usr/bin/env bash
set -euo pipefail

# Install direnv binary if absent (no sudo)
if ! command -v direnv >/dev/null 2>&1 && [[ ! -x "$HOME/.local/bin/direnv" ]]; then
  [[ ${DRY_RUN:-0} -eq 1 ]] && { echo "[dry] download direnv binary"; exit 0; }
  mkdir -p "$HOME/.local/bin"
  VER=$(curl -fsSL https://api.github.com/repos/direnv/direnv/releases/latest | jq -r '.tag_name')
  case "$OS-$ARCH" in
    linux-x86_64)  asset="direnv.linux-amd64" ;;
    linux-arm64)   asset="direnv.linux-arm64" ;;
    macos-x86_64)  asset="direnv.darwin-amd64" ;;
    macos-arm64)   asset="direnv.darwin-arm64" ;;
    *) echo "[!] unsupported $OS-$ARCH"; exit 1 ;;
  esac
  curl -fsSL "https://github.com/direnv/direnv/releases/download/${VER}/${asset}" -o "$HOME/.local/bin/direnv"
  chmod +x "$HOME/.local/bin/direnv"
fi
echo "  ok: direnv $("$HOME/.local/bin/direnv" --version 2>/dev/null || direnv --version)"

# Reminder: user runs `direnv allow ~` manually after install completes.
echo "  reminder: after install run \`direnv allow ~\` in a fresh zsh session."
