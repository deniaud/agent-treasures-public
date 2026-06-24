#!/usr/bin/env bash
set -euo pipefail

if command -v cc-switch >/dev/null 2>&1 || dpkg -l 2>/dev/null | grep -q '^ii  cc-switch'; then
  echo "  ok: cc-switch already installed"
  exit 0
fi
VER="${TREASURE_cc_switch_version:-3.14.1}"
URL="https://github.com/farion1231/cc-switch/releases/download/v${VER}/CC-Switch-v${VER}-Linux-x86_64.deb"

case "$OS" in
  linux)
    if command -v apt >/dev/null 2>&1; then
      [[ ${DRY_RUN:-0} -eq 1 ]] && { echo "[dry] would: apt install $URL"; exit 0; }
      TMP=$(mktemp -d)
      echo "  downloading $URL ..."
      curl -fsSL "$URL" -o "$TMP/cc-switch.deb"
      echo "  needs sudo for: sudo apt install -y $TMP/cc-switch.deb"
      sudo apt install -y "$TMP/cc-switch.deb"
      rm -rf "$TMP"
    else
      echo "  [!] No apt detected. Manual install: $URL (rpm/AppImage in releases)"; exit 1
    fi
    ;;
  macos) echo "  [!] macOS: download .dmg from https://github.com/farion1231/cc-switch/releases/tag/v${VER}"; exit 0 ;;
esac
