#!/usr/bin/env bash
# build-update-check.sh — runs from the claude() wrapper before CC starts.
# Detects whether (a) CC has updated past the version we last patched, or
# (b) upstream skrabe/tweakcc-fixed has new commits not in our fork's main.
# If either is true, prompts the user; on Y exec's build-update-apply.sh,
# on n caches the decline. Silent and fast on the hot path.
#
# Exit codes:
#   0 — nothing to do, or user declined (caller should `command claude` as normal)
#   exec → build-update-apply.sh (this script does not return)

set -uo pipefail

CACHE_DIR="$HOME/.claude/cache"
STATUS_FILE="$CACHE_DIR/build-update-status"
REMOTE_HEAD_CACHE="$CACHE_DIR/tweakcc-remote-head"
APPLY_SCRIPT="$HOME/.claude/scripts/build-update-apply.sh"
TWEAKCC_DIR="$HOME/dev/tweakcc-fixed"
TWEAKCC_CONFIG="$HOME/.tweakcc/config.json"

THROTTLE_OK_SECS=$((60 * 60))         # 1h: don't re-check if last status said ok
THROTTLE_DECLINED_SECS=$((24 * 3600)) # 24h: don't ask again after user said no
THROTTLE_REMOTE_SECS=$((30 * 60))     # 30m: don't `git fetch upstream` more often
NET_TIMEOUT_SECS=3

mkdir -p "$CACHE_DIR"

# Only prompt in a real interactive terminal. Bail out silently otherwise
# (IDE-launched, scripts, $CI, etc.) — the user can never see the Y/n prompt
# from non-tty input, and we don't want to hang the wrapper.
[[ -t 0 && -t 1 ]] || exit 0

now() { date +%s; }

# read_status_key key — emit value of `key=value` from $STATUS_FILE (or empty)
read_status_key() {
  [[ -f "$STATUS_FILE" ]] || return 0
  awk -F= -v k="$1" '$1==k {print $2; exit}' "$STATUS_FILE"
}

# Returns 0 if the status file is younger than $1 seconds AND has up_to_date=1.
fresh_up_to_date() {
  [[ -f "$STATUS_FILE" ]] || return 1
  local age now_ts mtime
  now_ts=$(now)
  mtime=$(stat -c %Y "$STATUS_FILE" 2>/dev/null || echo 0)
  age=$((now_ts - mtime))
  (( age < $1 )) || return 1
  [[ "$(read_status_key up_to_date)" == "1" ]]
}

# fresh_declined version — true if user declined for the same CC version within window
fresh_declined() {
  [[ -f "$STATUS_FILE" ]] || return 1
  local now_ts declined_at declined_for
  now_ts=$(now)
  declined_at=$(read_status_key declined_at)
  declined_for=$(read_status_key declined_for_version)
  [[ -n "$declined_at" && "$declined_for" == "$1" ]] || return 1
  (( now_ts - declined_at < THROTTLE_DECLINED_SECS ))
}

write_status() {
  # write_status key1=val1 key2=val2 ... — overwrite STATUS_FILE atomically
  local tmp="$STATUS_FILE.tmp.$$"
  : > "$tmp"
  for kv in "$@"; do
    printf '%s\n' "$kv" >> "$tmp"
  done
  mv -f "$tmp" "$STATUS_FILE"
}

cc_version_now() {
  command claude --version 2>/dev/null | awk 'NR==1 {print $1}'
}

cc_version_applied() {
  [[ -f "$TWEAKCC_CONFIG" ]] || { echo ""; return 0; }
  jq -r '.ccVersion // ""' "$TWEAKCC_CONFIG" 2>/dev/null || echo ""
}

# upstream_drift — emits N (commits ahead) if upstream is ahead of our origin/main,
# empty if up-to-date or fetch failed.
upstream_drift() {
  [[ -d "$TWEAKCC_DIR/.git" ]] || { echo ""; return 0; }

  # Throttle the network call; cache the (LOCAL,REMOTE) SHAs.
  local now_ts cache_mtime cached_local cached_remote
  now_ts=$(now)
  if [[ -f "$REMOTE_HEAD_CACHE" ]]; then
    cache_mtime=$(stat -c %Y "$REMOTE_HEAD_CACHE" 2>/dev/null || echo 0)
    if (( now_ts - cache_mtime < THROTTLE_REMOTE_SECS )); then
      cached_local=$(awk -F= '$1=="local" {print $2}' "$REMOTE_HEAD_CACHE")
      cached_remote=$(awk -F= '$1=="remote" {print $2}' "$REMOTE_HEAD_CACHE")
      if [[ -n "$cached_local" && -n "$cached_remote" && "$cached_local" != "$cached_remote" ]]; then
        local cached_count
        cached_count=$(awk -F= '$1=="ahead" {print $2}' "$REMOTE_HEAD_CACHE")
        echo "${cached_count:-1}"
      fi
      return 0
    fi
  fi

  # Cold check — needs network. Bail silently on any failure (offline etc.).
  local local_sha remote_sha ahead
  if ! timeout "$NET_TIMEOUT_SECS" git -C "$TWEAKCC_DIR" fetch upstream --quiet 2>/dev/null; then
    return 0
  fi
  local_sha=$(git -C "$TWEAKCC_DIR" rev-parse origin/main 2>/dev/null || \
              git -C "$TWEAKCC_DIR" rev-parse main 2>/dev/null || echo "")
  remote_sha=$(git -C "$TWEAKCC_DIR" rev-parse upstream/main 2>/dev/null || echo "")
  [[ -z "$local_sha" || -z "$remote_sha" ]] && return 0

  ahead=$(git -C "$TWEAKCC_DIR" rev-list --count "$local_sha..$remote_sha" 2>/dev/null || echo 0)

  { echo "local=$local_sha"; echo "remote=$remote_sha"; echo "ahead=$ahead"; } > "$REMOTE_HEAD_CACHE"
  (( ahead > 0 )) && echo "$ahead"
}

# Short-circuit: recent up-to-date cache → exit silent and instant.
if fresh_up_to_date "$THROTTLE_OK_SECS"; then
  exit 0
fi

CC_NOW=$(cc_version_now)
[[ -z "$CC_NOW" ]] && exit 0   # CC not on PATH? Let the wrapper try and fail with a normal error.

# Triggers
TRIGGER_CC=""
TRIGGER_UPSTREAM=""

CC_APPLIED=$(cc_version_applied)
if [[ -n "$CC_APPLIED" && "$CC_NOW" != "$CC_APPLIED" ]]; then
  TRIGGER_CC="$CC_APPLIED → $CC_NOW"
fi

UPSTREAM_AHEAD=$(upstream_drift)
if [[ -n "$UPSTREAM_AHEAD" ]]; then
  TRIGGER_UPSTREAM="$UPSTREAM_AHEAD"
fi

# Nothing to do — record and exit.
if [[ -z "$TRIGGER_CC" && -z "$TRIGGER_UPSTREAM" ]]; then
  write_status "up_to_date=1" "checked_at=$(now)" "cc_version=$CC_NOW"
  exit 0
fi

# Respect a recent decline for THIS CC version.
if fresh_declined "$CC_NOW"; then
  exit 0
fi

# Prompt.
echo "" >&2
echo "[build-update] доступно обновление:" >&2
[[ -n "$TRIGGER_CC"       ]] && echo "  - claude code:    $TRIGGER_CC (пропатчено под $CC_APPLIED)" >&2
[[ -n "$TRIGGER_UPSTREAM" ]] && echo "  - tweakcc-fixed:  upstream впереди на $TRIGGER_UPSTREAM коммит(а)" >&2
echo "" >&2
printf "Запустить обновление сборки? [Y/n]: " >&2

reply=""
IFS= read -r reply || reply=""
case "${reply,,}" in
  ""|y|yes|д|да)
    [[ -x "$APPLY_SCRIPT" ]] || {
      echo "[!] $APPLY_SCRIPT не найден или не исполняемый" >&2
      exit 0
    }
    exec "$APPLY_SCRIPT"
    ;;
  *)
    write_status \
      "declined_at=$(now)" \
      "declined_for_version=$CC_NOW" \
      "declined_upstream_ahead=${TRIGGER_UPSTREAM:-0}"
    echo "  отложено — спрошу снова через сутки или после следующего апдейта CC." >&2
    exit 0
    ;;
esac
