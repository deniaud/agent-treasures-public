#!/usr/bin/env bash
set -euo pipefail
# Apply both home-mirror buckets to $HOME:
#   claude/  → ~/   (.claude, .cc-switch, .tweakcc, claude-* systemd units)
#   host/    → ~/   (.zshrc, .zshenv, .envrc.template, tooling systemd units)
#
# With --skip-services-tooling, host/.config/systemd/user/ tooling units are skipped.

TS=$(date -u +%Y%m%dT%H%M%SZ)

apply_bucket() {
  local src="$1"; shift
  local excludes=( "$@" )
  if [[ ${DRY_RUN:-0} -eq 1 ]]; then
    echo "[dry] rsync $src/ → \$HOME (backup → *.pre-install.$TS.bak)"
    rsync -avn --backup --suffix=".pre-install.$TS.bak" "${excludes[@]}" "$src/" "$HOME/" | tail -20
  else
    rsync -av --backup --suffix=".pre-install.$TS.bak" "${excludes[@]}" "$src/" "$HOME/" | tail -20
  fi
}

# --- claude/ — always applied ---
echo "[+] claude/ bucket → \$HOME"
apply_bucket "$REPO_DIR/claude"

# --- host/ — with optional tooling-services exclusion ---
echo ""
echo "[+] host/ bucket → \$HOME"
HOST_EXCLUDES=(
  --exclude=.envrc           # placeholder template only; real values via 95-secrets.sh
  --exclude=.envrc.template  # placed via direct cp below for visibility
)
if [[ ${SKIP_SERVICES_TOOLING:-0} -eq 1 ]]; then
  HOST_EXCLUDES+=(
  )
fi
apply_bucket "$REPO_DIR/host" "${HOST_EXCLUDES[@]}"

# Also drop .envrc.template into $HOME for visibility
if [[ ${DRY_RUN:-0} -eq 0 ]]; then
  cp "$REPO_DIR/host/.envrc.template" "$HOME/.envrc.template"
fi

echo ""
echo "  ok: buckets applied. Existing files preserved as *.pre-install.$TS.bak"
echo "  next: 95-secrets.sh decrypts secrets.env.gpg → ~/.envrc"
