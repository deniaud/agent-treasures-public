#!/usr/bin/env bash
# cc-fork — fork the current Claude Code session, preserving prompt-cache prefix.
#
# Default mode (--native): prints `claude --resume <id> --fork-session`.
#   Claude Code itself copies the JSONL and reassigns sessionId on resume.
#   This is the cache-safe path — message content stays byte-identical, so the
#   server-side prompt cache hits on the entire prefix.
#
# Manual mode (--copy): physically duplicates the .jsonl with a new UUID and
# rewrites the old sessionId inside the file. Use when you want the new file
# to exist before launching Claude (e.g. to inspect or patch it first).
#
# Usage:
#   cc-fork                       # fork most recently modified session in $PWD
#   cc-fork <sessionId>           # fork a specific session id (must live in $PWD)
#   cc-fork --copy [<sessionId>]  # manual clone instead of --fork-session
#   cc-fork --here                # fork session(s) whose heartbeat cwd == $PWD
#   cc-fork --list                # list sessions for $PWD
#   cc-fork --tmux                # spawn the fork in a new tmux window
#
# Env:
#   CLAUDE_DIR   override ~/.claude

set -euo pipefail

CLAUDE_DIR="${CLAUDE_DIR:-$HOME/.claude}"
PROJECTS_DIR="$CLAUDE_DIR/projects"
SESSIONS_DIR="$CLAUDE_DIR/sessions"

die()  { printf 'cc-fork: %s\n' "$*" >&2; exit 1; }
info() { printf '\033[36m%s\033[0m\n' "$*"; }

encode_cwd() { printf '%s' "$1" | sed 's|[^A-Za-z0-9]|-|g'; }

uuidv4() {
  if command -v uuidgen >/dev/null 2>&1; then
    uuidgen | tr 'A-Z' 'a-z'
  elif command -v python3 >/dev/null 2>&1; then
    python3 -c 'import uuid;print(uuid.uuid4())'
  else
    # cheap fallback
    od -An -N16 -tx1 /dev/urandom | tr -d ' \n' | \
      sed -E 's/^(.{8})(.{4})(.{4})(.{4})(.{12})$/\1-\2-4\3-8\4-\5/'
  fi
}

CWD_DIR="$PROJECTS_DIR/$(encode_cwd "$PWD")"

cmd_list() {
  [ -d "$CWD_DIR" ] || die "no project dir for $PWD (expected $CWD_DIR)"
  printf '%-36s  %12s  %s\n' SESSION_ID SIZE_BYTES MODIFIED
  for f in $(ls -t "$CWD_DIR"/*.jsonl 2>/dev/null); do
    id=$(basename "$f" .jsonl)
    sz=$(stat -c %s "$f")
    mt=$(stat -c %y "$f" | cut -d. -f1)
    live=""
    if grep -l "\"sessionId\":\"$id\"" "$SESSIONS_DIR"/*.json >/dev/null 2>&1; then
      live=" (live)"
    fi
    printf '%-36s  %12s  %s%s\n' "$id" "$sz" "$mt" "$live"
  done
}

pick_session_for_cwd() {
  # 1) prefer a live heartbeat whose cwd matches $PWD
  for hb in "$SESSIONS_DIR"/*.json; do
    [ -f "$hb" ] || continue
    if grep -q "\"cwd\":\"$PWD\"" "$hb" 2>/dev/null; then
      # extract sessionId
      sid=$(sed -n 's/.*"sessionId":"\([^"]*\)".*/\1/p' "$hb" | head -n1)
      [ -n "$sid" ] && [ -f "$CWD_DIR/$sid.jsonl" ] && { echo "$sid"; return; }
    fi
  done
  # 2) otherwise fall back to newest .jsonl in the project dir
  newest=$(ls -t "$CWD_DIR"/*.jsonl 2>/dev/null | head -n1)
  [ -n "$newest" ] && basename "$newest" .jsonl
}

MODE="native"      # native | copy
USE_TMUX=0
HERE_ONLY=0
SRC_ID=""

while [ $# -gt 0 ]; do
  case "$1" in
    --copy)   MODE="copy"; shift ;;
    --native) MODE="native"; shift ;;
    --tmux)   USE_TMUX=1; shift ;;
    --here)   HERE_ONLY=1; shift ;;
    --list)   cmd_list; exit 0 ;;
    -h|--help) sed -n '1,28p' "$0" | sed 's/^# \{0,1\}//'; exit 0 ;;
    --)       shift; break ;;
    -*)       die "unknown flag: $1" ;;
    *)        SRC_ID="$1"; shift ;;
  esac
done

[ -d "$CWD_DIR" ] || die "no project dir for $PWD (expected $CWD_DIR)"

if [ -z "$SRC_ID" ]; then
  SRC_ID=$(pick_session_for_cwd)
  [ -n "$SRC_ID" ] || die "no session found for $PWD"
fi

SRC_FILE="$CWD_DIR/$SRC_ID.jsonl"
[ -f "$SRC_FILE" ] || die "session file not found: $SRC_FILE"

# Sanity: if --here was requested, verify SRC_ID actually belongs to a live
# session in $PWD (avoids forking a stale session from a different terminal).
if [ "$HERE_ONLY" = 1 ]; then
  if ! grep -l "\"sessionId\":\"$SRC_ID\"" "$SESSIONS_DIR"/*.json 2>/dev/null \
       | xargs grep -l "\"cwd\":\"$PWD\"" >/dev/null 2>&1; then
    die "session $SRC_ID has no live heartbeat for $PWD (drop --here to force)"
  fi
fi

NEW_ID=$(uuidv4)
LAUNCH=""

case "$MODE" in
  native)
    # No filesystem mutation. Claude Code will copy the .jsonl on resume
    # and assign a fresh sessionId because of --fork-session.
    info "Native fork (claude handles the copy, prompt cache preserved):"
    LAUNCH="claude --resume $SRC_ID --fork-session"
    ;;
  copy)
    DEST_FILE="$CWD_DIR/$NEW_ID.jsonl"
    # Replace every occurrence of the old sessionId with the new one inside
    # the JSONL. Claude's own --fork-session does the same logical thing
    # but assigns the id at resume-time; here we materialise it up-front.
    sed "s/$SRC_ID/$NEW_ID/g" "$SRC_FILE" > "$DEST_FILE"
    info "Manual clone:"
    printf '  src : %s\n' "$SRC_FILE"
    printf '  dst : %s\n' "$DEST_FILE"
    LAUNCH="claude --resume $NEW_ID"
    ;;
esac

echo
echo "Launch the fork with:"
echo "  $LAUNCH"

if [ "$USE_TMUX" = 1 ]; then
  command -v tmux >/dev/null || die "--tmux requested but tmux not in PATH"
  if [ -n "${TMUX:-}" ]; then
    tmux new-window -c "$PWD" "$LAUNCH"
  else
    tmux new-session -d -s "cc-fork-$NEW_ID" -c "$PWD" "$LAUNCH"
    echo "tmux session: cc-fork-$NEW_ID  (attach: tmux attach -t cc-fork-$NEW_ID)"
  fi
fi
