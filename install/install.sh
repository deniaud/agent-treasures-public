#!/usr/bin/env bash
# agent-treasures / install.sh — bootstrap entire Claude Code stack on a new
# machine from this repo. Idempotent: existing files get backed up to
# <name>.pre-install.<TS>.bak before being replaced.
set -euo pipefail

DRY_RUN=0
FRESH_AUTH=0
SKIP_BUILD=0
SKIP_SECRETS=0
SKIP_SYSTEMD=0

while [[ $# -gt 0 ]]; do
  case "$1" in
    --dry-run)              DRY_RUN=1 ;;
    --fresh-auth)           FRESH_AUTH=1 ;;
    --skip-build)           SKIP_BUILD=1 ;;
    --skip-secrets)         SKIP_SECRETS=1 ;;
    --skip-systemd)         SKIP_SYSTEMD=1 ;;
    --skip-services-tooling) SKIP_SERVICES_TOOLING=1 ;;
    -h|--help)
      cat <<H
Usage: install.sh [--dry-run] [--fresh-auth] [--skip-build] [--skip-secrets] [--skip-systemd] [--skip-services-tooling]

  --dry-run                 Print actions, touch nothing.
  --fresh-auth              Don't restore .credentials.json; force \`claude login\`.
  --skip-build              Skip rustup + cargo build of CCometixLine (use prebuilt).
  --skip-secrets            Don't decrypt secrets/secrets.env.gpg.
  --skip-systemd            Don't install/enable systemd user units.
                            (Their source code is NOT in this repo — see docs/services.md.)
H
      exit 0 ;;
    *) echo "Unknown arg: $1" >&2; exit 2 ;;
  esac
  shift
done

REPO_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
LIB="$REPO_DIR/install/lib"
export REPO_DIR LIB DRY_RUN FRESH_AUTH SKIP_BUILD SKIP_SECRETS SKIP_SYSTEMD SKIP_SERVICES_TOOLING

# Detect OS / arch
case "$(uname -s)" in
  Linux*)   export OS=linux ;;
  Darwin*)  export OS=macos ;;
  *) echo "Unsupported OS: $(uname -s). See install/windows/install.ps1." >&2; exit 1 ;;
esac
case "$(uname -m)" in
  x86_64|amd64)  export ARCH=x86_64 ;;
  aarch64|arm64) export ARCH=arm64 ;;
  *) echo "Unsupported arch: $(uname -m)" >&2; exit 1 ;;
esac

echo "==> agent-treasures install"
echo "   repo:    $REPO_DIR"
echo "   target:  $OS-$ARCH"
[[ $DRY_RUN -eq 1 ]] && echo "   DRY RUN — no writes"

# Load versions.lock into RECIPE_* env
while IFS='=' read -r k v; do
  [[ $k =~ ^[[:space:]]*# ]] && continue
  [[ -z "${k// /}" ]] && continue
  k="${k// /}"
  v="${v%%#*}"; v="${v## }"; v="${v%% }"
  [[ -z "$v" ]] && continue
  export "TREASURE_$k=$v"
done < "$REPO_DIR/versions.lock"

step() {
  echo ""
  echo "──────────────────────────────────────────────────────────────"
  echo " [$1] $2"
  echo "──────────────────────────────────────────────────────────────"
}

step 00 "Pre-flight checks";        bash "$LIB/00-preflight.sh"
step 05 "Shell bootstrap (zsh+oh-my-zsh+nvm)"; bash "$LIB/05-shell-bootstrap.sh"
step 10 "Install Claude Code";      bash "$LIB/10-claude-code.sh"
step 20 "Install cc-switch";        bash "$LIB/20-cc-switch.sh"
step 30 "Clone+build tweakcc-fixed";bash "$LIB/30-tweakcc-fixed.sh"
step 40 "Clone lobotomized-cc";     bash "$LIB/40-lobotomized.sh"

if [[ $SKIP_BUILD -eq 0 ]]; then
  step 50 "Build CCometixLine";     bash "$LIB/50-ccometixline.sh"
fi

step 55 "Clone cc-prompt-rewriter"; bash "$LIB/55-cc-prompt-rewriter.sh"
step 57 "Install cc-quote";          bash "$LIB/57-cc-quote.sh"

step 60 "Direnv setup";              bash "$LIB/60-direnv.sh"
step 70 "MCP packages (npm ci)";     bash "$LIB/70-mcp-packages.sh"
step 80 "Apply home/ → \$HOME";      bash "$LIB/80-apply-home.sh"
step 85 "Skill symlinks";            bash "$LIB/85-skill-symlinks.sh"
step 87 "Build-update watcher";      bash "$LIB/87-build-update-watcher.sh"

if [[ $SKIP_SYSTEMD -eq 0 ]]; then
  step 90 "Systemd user units";     bash "$LIB/90-systemd.sh"
fi

if [[ $SKIP_SECRETS -eq 0 ]]; then
  step 95 "Decrypt + place secrets";bash "$LIB/95-secrets.sh"
fi

step 97 "Apply tweakcc patches";     bash "$LIB/97-tweakcc-apply.sh"
step 98 "Verify post-install invariants"; bash "$LIB/98-verify.sh" || echo "    (see ~/.claude/last-install.json + docs/troubleshooting.md)"
step 99 "Post-install hints";        bash "$LIB/99-post-install.sh"

echo ""
echo "[✓] agent-treasures bootstrap complete."
[[ $DRY_RUN -eq 1 ]] && echo "    (dry run — nothing actually changed)"
