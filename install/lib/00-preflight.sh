#!/usr/bin/env bash
set -euo pipefail

need() {
  if ! command -v "$1" >/dev/null 2>&1; then
    echo "[!] Missing: $1 — $2"; exit 1
  fi
  echo "  ok: $1"
}

need curl    "apt: curl | brew: curl"
need git     "apt: git | brew: git"
need jq      "apt: jq | brew: jq"
need gpg     "apt: gnupg | brew: gnupg"
need tar     "(usually preinstalled)"
need python3 "apt: python3 | brew: python@3"
need rsync   "apt: rsync | brew: rsync"

# direnv — may be in $HOME/.local/bin (installed via the helper below)
if ! command -v direnv >/dev/null 2>&1 && [[ ! -x "$HOME/.local/bin/direnv" ]]; then
  echo "[i] direnv not found — 60-direnv.sh will install a binary release"
fi

# node
if ! command -v node >/dev/null 2>&1; then
  echo "[!] node not found. Install Node.js >= 20 (recommended via nvm)."
  exit 1
fi
NMAJ=$(node -e 'console.log(process.versions.node.split(".")[0])')
[[ ${NMAJ} -lt 20 ]] && { echo "[!] node $NMAJ too old; need >= 20"; exit 1; }
echo "  ok: node $(node --version)"

# Lock down secrets/ permissions. Git stores mode as 100644 regardless of the
# local file's 0600 — a fresh `git clone` lands on 0644 (group/other readable),
# so we re-tighten here on every install run. Cheap, idempotent, defends against
# shared-host snooping while .gpg blobs are sitting on disk.
if [[ -d "$REPO_DIR/secrets" ]]; then
  find "$REPO_DIR/secrets" -type f \( -name '*.gpg' -o -name '*.env.template' \) \
    -exec chmod 600 {} +
  echo "  ok: secrets/ files locked to 0600"
fi
