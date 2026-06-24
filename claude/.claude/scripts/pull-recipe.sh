#!/usr/bin/env bash
# Pull-recipe: fetch latest agent-treasures snapshot from origin and apply
# whitelisted files into $HOME. Counterpart to snapshot-recipe.sh.
#
# Behavior:
#   - Acquires a local flock so concurrent invocations no-op.
#   - Fast-forwards $TREASURES to origin/main; bails out on divergence.
#   - Applies claude/ + host/ buckets to $HOME via rsync with a blacklist
#     (per-machine secrets, OAuth state, sessions, plugins — never touched).
#   - Pre-pull backups land in ~/.claude/pre-pull-backups/<TS>/ via rsync
#     --backup-dir. To undo: run with --rollback.
#   - Writes ~/.claude/last-pull.json with commit SHA + backup-dir for tools.
#
# Triggered hourly by ~/.config/systemd/user/claude-pull.timer.
# Also wired as the `/pull-treasures` slash command.
#
# Flags:
#   --dry-run            Print rsync plan, do not apply.
#   --rollback           Restore $HOME from most recent pre-pull-backups/<TS>.
#   --force              Skip the "up to date" guard (re-apply current HEAD).
#   --skip-systemd       Don't run `systemctl --user daemon-reload` after apply.

set -euo pipefail

LOG="$HOME/.claude/cleanup.log"
exec > >(tee -a "$LOG") 2>&1

ts() { date -u +%Y-%m-%dT%H:%M:%SZ; }
log() { printf '[%s pull] %s\n' "$(ts)" "$*"; }

DRY_RUN=0
ROLLBACK=0
FORCE=0
SKIP_SYSTEMD=0
while [[ $# -gt 0 ]]; do
  case "$1" in
    --dry-run)      DRY_RUN=1 ;;
    --rollback)     ROLLBACK=1 ;;
    --force)        FORCE=1 ;;
    --skip-systemd) SKIP_SYSTEMD=1 ;;
    -h|--help)
      sed -n '2,/^set -e/p' "$0" | sed 's/^# \{0,1\}//; /^set -e/d'
      exit 0 ;;
    *) echo "Unknown arg: $1" >&2; exit 2 ;;
  esac
  shift
done

TREASURES="$HOME/dev/agent-treasures"
BACKUP_ROOT="$HOME/.claude/pre-pull-backups"
STATE_FILE="$HOME/.claude/last-pull.json"

# Single-instance lock. Silent no-op if another pull is in flight (typical for
# hourly timer overlap on slow networks).
LOCK_FILE="$HOME/.claude/pull.lock"
mkdir -p "$(dirname "$LOCK_FILE")"
exec 9>"$LOCK_FILE"
if ! flock -n 9; then
  log "Another pull is running — exiting."
  exit 0
fi

log "=== START ==="

# --- Rollback path ---
if [[ $ROLLBACK -eq 1 ]]; then
  if [[ ! -d "$BACKUP_ROOT" ]]; then
    log "ERROR: no backup dir found at $BACKUP_ROOT"
    exit 1
  fi
  LATEST="$(ls -1 "$BACKUP_ROOT" | sort | tail -1)"
  if [[ -z "$LATEST" ]]; then
    log "ERROR: no backup snapshots in $BACKUP_ROOT"
    exit 1
  fi
  log "Rolling back from $BACKUP_ROOT/$LATEST"
  for bucket in claude host; do
    [[ -d "$BACKUP_ROOT/$LATEST/$bucket" ]] || continue
    rsync -a "$BACKUP_ROOT/$LATEST/$bucket/" "$HOME/"
  done
  log "Rollback complete. (Backup dir kept at $BACKUP_ROOT/$LATEST)"
  exit 0
fi

# --- Pre-flight ---
if [[ ! -d "$TREASURES/.git" ]]; then
  log "ERROR: $TREASURES is not a git checkout. Run install.sh first."
  exit 1
fi

cd "$TREASURES"

# --- Fetch + fast-forward ---
log "Fetching from origin ..."
if ! git fetch --quiet origin 2>&1; then
  log "ERROR: fetch failed (offline?) — exiting."
  exit 3
fi

HEAD_SHA="$(git rev-parse HEAD)"
ORIGIN_SHA="$(git rev-parse origin/main)"

if [[ "$HEAD_SHA" == "$ORIGIN_SHA" && $FORCE -eq 0 ]]; then
  log "Up to date with origin ($HEAD_SHA) — nothing to apply."
  exit 0
fi

if [[ "$HEAD_SHA" != "$ORIGIN_SHA" ]]; then
  if ! git merge-base --is-ancestor HEAD origin/main 2>/dev/null; then
    log "ERROR: local treasures repo has diverged from origin/main"
    log "       (probably an in-flight local snapshot). Run snapshot-recipe.sh"
    log "       to commit+push your work, then retry pull."
    exit 4
  fi
  log "Fast-forwarding $HEAD_SHA → $ORIGIN_SHA ..."
  if [[ $DRY_RUN -eq 0 ]]; then
    git merge --ff-only --quiet origin/main
  fi
fi

# --- Apply buckets ---
TS=$(date -u +%Y%m%dT%H%M%SZ)
BACKUP_DIR="$BACKUP_ROOT/$TS"

# Files we NEVER pull (per-machine state, OAuth tokens, session DB, secrets).
# Mirrors what's blacklisted from snapshot, but doubly-defensive.
CLAUDE_EXCLUDES=(
  --exclude=.credentials.json
  --exclude=plugins/
  --exclude=sessions/
  --exclude=projects/
  --exclude=__store.db
  --exclude=__store.db-shm
  --exclude=__store.db-wal
  --exclude=statsig/
  --exclude=ide/
  --exclude=todos/
  --exclude=shell-snapshots/
)
HOST_EXCLUDES=(
  --exclude=.envrc           # populated by 95-secrets.sh
  --exclude=.envrc.template
)

apply_bucket() {
  local src="$1" bucket_name="$2"; shift 2
  local excludes=( "$@" )
  local rsync_flags=( -a --backup --backup-dir="$BACKUP_DIR/$bucket_name" "${excludes[@]}" )
  if [[ $DRY_RUN -eq 1 ]]; then
    log "[dry] rsync $src/ → \$HOME (backup → $BACKUP_DIR/$bucket_name/)"
    rsync -n "${rsync_flags[@]}" "$src/" "$HOME/" | tail -30
  else
    rsync "${rsync_flags[@]}" "$src/" "$HOME/" | tail -30
  fi
}

mkdir -p "$BACKUP_DIR"
log "Pre-pull backups → $BACKUP_DIR"
log "Applying claude/ → \$HOME ..."
apply_bucket "$TREASURES/claude" claude "${CLAUDE_EXCLUDES[@]}"
log "Applying host/   → \$HOME ..."
apply_bucket "$TREASURES/host"   host   "${HOST_EXCLUDES[@]}"

# Clean up empty backup dirs (rsync creates them eagerly).
find "$BACKUP_DIR" -type d -empty -delete 2>/dev/null || true
[[ -d "$BACKUP_DIR" ]] || log "No files were overwritten (nothing to backup)."

# --- Post-apply ---
if [[ $DRY_RUN -eq 0 && $SKIP_SYSTEMD -eq 0 ]]; then
  if command -v systemctl >/dev/null && systemctl --user status >/dev/null 2>&1; then
    log "Reloading user systemd units ..."
    systemctl --user daemon-reload || true
  fi
fi

# --- Prune old backups (keep last 10) ---
if [[ -d "$BACKUP_ROOT" ]]; then
  ls -1 "$BACKUP_ROOT" | sort | head -n -10 | while read -r old; do
    [[ -n "$old" ]] || continue
    log "Pruning old backup: $old"
    rm -rf "$BACKUP_ROOT/$old"
  done
fi

# --- Write state ---
if [[ $DRY_RUN -eq 0 ]]; then
  cat > "$STATE_FILE" <<EOF
{
  "timestamp": "$(ts)",
  "commit_sha": "$ORIGIN_SHA",
  "backup_dir": "$BACKUP_DIR",
  "hostname": "$(hostname)"
}
EOF
fi

log "=== END ==="
log "Applied snapshot $ORIGIN_SHA. To revert: $0 --rollback"
