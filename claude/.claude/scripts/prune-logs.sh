#!/usr/bin/env bash
# Weekly cleanup for ~/.claude runtime state.
# Invoked by systemd timer claude-prune.timer.
set -euo pipefail

LOG="$HOME/.claude/cleanup.log"
exec > >(tee -a "$LOG") 2>&1

ts() { date -u +%Y-%m-%dT%H:%M:%SZ; }
log() { printf '[%s prune] %s\n' "$(ts)" "$*"; }
log "=== START ==="

count_before() { find "$1" -type f 2>/dev/null | wc -l; }
size_before() { du -sh "$1" 2>/dev/null | awk '{print $1}'; }

prune_dir() {
  local dir="$1" days="$2"
  [[ -d "$dir" ]] || return 0
  local cb sb
  cb="$(count_before "$dir")"
  sb="$(size_before "$dir")"
  local deleted
  deleted="$(find "$dir" -type f -mtime "+${days}" -delete -print 2>/dev/null | wc -l)"
  log "  $dir: $cb files / $sb → deleted $deleted (mtime +${days}d)"
}

prune_dir "$HOME/.claude/shell-snapshots" 30
prune_dir "$HOME/.claude/file-history"    30
prune_dir "$HOME/.claude/session-env"      7
prune_dir "$HOME/.claude/paste-cache"      7

# history.jsonl: keep last 10k lines
H="$HOME/.claude/history.jsonl"
if [[ -f "$H" ]]; then
  local_lines="$(wc -l < "$H")"
  if (( local_lines > 10000 )); then
    tail -10000 "$H" > "$H.new" && mv "$H.new" "$H"
    log "  history.jsonl: was $local_lines lines, trimmed to 10000"
  else
    log "  history.jsonl: $local_lines lines (no trim)"
  fi
fi

# .claude.json.backup.*: keep only last 10
BACKUPS_DIR="$HOME/.claude/backups"
if [[ -d "$BACKUPS_DIR" ]]; then
  excess="$(ls -t "$BACKUPS_DIR"/.claude.json.backup.* 2>/dev/null | tail -n +11)"
  if [[ -n "$excess" ]]; then
    echo "$excess" | xargs -r rm -v
    log "  .claude.json.backup.*: pruned to last 10"
  fi
fi

log "=== END ==="
