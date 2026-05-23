#!/usr/bin/env bash
set -euo pipefail
# Reload + enable claude-snapshot + claude-pull + claude-prune timers.
# (their dependencies may not be on the new machine yet).

CLAUDE_TIMERS=(claude-snapshot.timer claude-pull.timer claude-prune.timer)

[[ ${DRY_RUN:-0} -eq 1 ]] && {
  echo "[dry] systemctl --user daemon-reload"
  echo "[dry] systemctl --user enable --now ${CLAUDE_TIMERS[*]}"
  exit 0
}

systemctl --user daemon-reload
systemctl --user enable --now "${CLAUDE_TIMERS[@]}" 2>&1 | sed 's/^/  /'

echo ""
echo "  ok: Claude timers enabled."
echo "  Enable manually:  systemctl --user enable --now <unit>"
echo ""
echo "  Note: for timers to fire when not logged in: sudo loginctl enable-linger $USER"
