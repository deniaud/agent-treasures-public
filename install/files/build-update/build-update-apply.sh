#!/usr/bin/env bash
# build-update-apply.sh — full re-patch pipeline triggered from build-update-check.sh
# or invoked manually. Six isolated steps, each in its own function. Final report
# is built from STEPS_OK / STEPS_FAIL arrays.
#
# Exit codes:
#   0 — full success (or all steps the user asked for succeeded)
#   1 — critical failure (step 1 / CC update failed; nothing else attempted)
#   2 — partial: ≥1 of steps 2-6 failed, but pipeline ran to the end

set -uo pipefail

# ────────────────────────────────────────────────────────────────────────────
# Config / paths
# ────────────────────────────────────────────────────────────────────────────
TWEAKCC_DIR="$HOME/dev/tweakcc-fixed"
TWEAKCC_CONFIG="$HOME/.tweakcc/config.json"
TWEAKCC_ENTRY="$TWEAKCC_DIR/dist/index.mjs"

CACHE_DIR="$HOME/.claude/cache"
STATUS_FILE="$CACHE_DIR/build-update-status"
LOG_DIR="$HOME/.claude/logs"
LOG_FILE="$LOG_DIR/build-update-$(date +%F).log"

mkdir -p "$LOG_DIR" "$CACHE_DIR"

SKIP_CC_UPDATE=0
LAUNCH_AFTER=1   # whether to exec `command claude` after pipeline
for arg in "$@"; do
  case "$arg" in
    --skip-cc-update)   SKIP_CC_UPDATE=1 ;;
    --no-launch)        LAUNCH_AFTER=0 ;;
    *) ;;
  esac
done

# Load versions.lock so we know the cc-quote pin etc.
# Best-effort — fallback to "latest" if not found.
VERSIONS_LOCK=""
for candidate in \
  "$HOME/dev/agent-treasures/versions.lock" \
  "$HOME/dev/cc-dev/versions.lock"; do
  if [[ -f "$candidate" ]]; then VERSIONS_LOCK="$candidate"; break; fi
done
if [[ -n "$VERSIONS_LOCK" ]]; then
  while IFS='=' read -r k v; do
    [[ $k =~ ^[[:space:]]*# ]] && continue
    [[ -z "${k// /}" ]] && continue
    k="${k// /}"; v="${v%%#*}"; v="${v## }"; v="${v%% }"
    [[ -z "$v" ]] && continue
    export "TREASURE_$k=$v"
  done < "$VERSIONS_LOCK"
fi
CC_QUOTE_REPO="${TREASURE_cc_quote_repo:-https://github.com/deniaud/cc-quote}"
CC_QUOTE_REF="${TREASURE_cc_quote_ref:-main}"
CC_REWRITER_REPO="${TREASURE_cc_prompt_rewriter_repo:-https://github.com/deniaud/cc-prompt-rewriter}"
CC_REWRITER_REF="${TREASURE_cc_prompt_rewriter_ref:-main}"
CC_QUOTE_CLONE="$HOME/dev/cc-quote"
CC_REWRITER_CLONE="$HOME/dev/cc-prompt-rewriter"

# ────────────────────────────────────────────────────────────────────────────
# State / reporting
# ────────────────────────────────────────────────────────────────────────────
STEPS_OK=()
STEPS_FAIL=()
STEPS_SKIP=()
declare -A STEP_DETAIL

START_TS=$(date +%s)

CC_BEFORE=""
CC_AFTER=""
TWEAK_SHA_BEFORE=""
TWEAK_SHA_AFTER=""
UPSTREAM_AHEAD_BEFORE=""

cc_version() {
  command claude --version 2>/dev/null | awk 'NR==1 {print $1}'
}

log() {
  local ts; ts=$(date +%T)
  printf '[%s] %s\n' "$ts" "$*" >> "$LOG_FILE"
}

# ok step "detail" / fail step "detail" / skip step "detail"
mark_ok()   { STEPS_OK+=("$1");   STEP_DETAIL["$1"]="${2:-}"; }
mark_fail() { STEPS_FAIL+=("$1"); STEP_DETAIL["$1"]="${2:-}"; }
mark_skip() { STEPS_SKIP+=("$1"); STEP_DETAIL["$1"]="${2:-}"; }

# run_capture "label" cmd...
# Runs cmd, tees stdout+stderr to log, returns the cmd's exit code.
run_capture() {
  local label="$1"; shift
  log "── $label ──"
  log "$ $*"
  { "$@"; } >>"$LOG_FILE" 2>&1
  local rc=$?
  log "[rc=$rc]"
  return $rc
}

banner() {
  echo "" >&2
  echo "──────────────────────────────────────────────────────────────" >&2
  echo " $1" >&2
  echo "──────────────────────────────────────────────────────────────" >&2
}

# ────────────────────────────────────────────────────────────────────────────
# Step 1 — Update Claude Code
# ────────────────────────────────────────────────────────────────────────────
step_1_update_cc() {
  banner "1/6  обновляю claude code"
  CC_BEFORE=$(cc_version)
  log "CC before: $CC_BEFORE"

  if (( SKIP_CC_UPDATE )); then
    CC_AFTER="$CC_BEFORE"
    mark_skip "cc-update" "skipped via --skip-cc-update (текущая $CC_BEFORE)"
    echo "  ↷ пропускаю (--skip-cc-update), текущая $CC_BEFORE" >&2
    return 0
  fi

  if ! run_capture "claude update" command claude update; then
    CC_AFTER=$(cc_version)
    mark_fail "cc-update" "claude update вернул ошибку (см. лог)"
    echo "  ✗ claude update fail — см. $LOG_FILE" >&2
    return 1
  fi

  CC_AFTER=$(cc_version)
  if [[ "$CC_AFTER" == "$CC_BEFORE" ]]; then
    mark_ok "cc-update" "уже latest ($CC_AFTER)"
    echo "  ✓ уже latest ($CC_AFTER)" >&2
  else
    mark_ok "cc-update" "$CC_BEFORE → $CC_AFTER"
    echo "  ✓ $CC_BEFORE → $CC_AFTER" >&2
  fi
  return 0
}

# ────────────────────────────────────────────────────────────────────────────
# Step 2 — Sync fork with upstream
# ────────────────────────────────────────────────────────────────────────────
step_2_sync_fork() {
  banner "2/6  синхронизирую форк tweakcc-fixed с upstream"

  if [[ ! -d "$TWEAKCC_DIR/.git" ]]; then
    mark_fail "fork-sync" "$TWEAKCC_DIR — нет git-репозитория"
    echo "  ✗ нет $TWEAKCC_DIR/.git" >&2
    return 1
  fi

  TWEAK_SHA_BEFORE=$(git -C "$TWEAKCC_DIR" rev-parse HEAD 2>/dev/null || echo "")
  log "tweakcc HEAD before: $TWEAK_SHA_BEFORE"

  if ! run_capture "git fetch upstream" git -C "$TWEAKCC_DIR" fetch upstream --quiet; then
    mark_fail "fork-sync" "git fetch upstream упал"
    echo "  ✗ git fetch upstream fail" >&2
    return 1
  fi

  local local_sha remote_sha
  local_sha=$(git -C "$TWEAKCC_DIR" rev-parse main 2>/dev/null || echo "")
  remote_sha=$(git -C "$TWEAKCC_DIR" rev-parse upstream/main 2>/dev/null || echo "")
  if [[ -z "$remote_sha" ]]; then
    mark_fail "fork-sync" "не могу прочесть upstream/main"
    echo "  ✗ upstream/main недоступен" >&2
    return 1
  fi
  UPSTREAM_AHEAD_BEFORE=$(git -C "$TWEAKCC_DIR" rev-list --count "$local_sha..$remote_sha" 2>/dev/null || echo 0)

  if [[ "$local_sha" == "$remote_sha" ]]; then
    TWEAK_SHA_AFTER="$local_sha"
    mark_ok "fork-sync" "форк уже на ${local_sha:0:7} (с upstream совпадает)"
    echo "  ✓ форк уже на ${local_sha:0:7}" >&2
    return 0
  fi

  # Make sure we're on main before rebasing.
  if ! run_capture "git checkout main" git -C "$TWEAKCC_DIR" checkout main; then
    mark_fail "fork-sync" "git checkout main упал"
    echo "  ✗ checkout main fail" >&2
    return 1
  fi

  if run_capture "git rebase --autostash upstream/main" \
      git -C "$TWEAKCC_DIR" rebase --autostash upstream/main; then
    TWEAK_SHA_AFTER=$(git -C "$TWEAKCC_DIR" rev-parse HEAD)
    # Push to our fork.
    if run_capture "git push --force-with-lease origin main" \
        git -C "$TWEAKCC_DIR" push --force-with-lease origin main; then
      mark_ok "fork-sync" "rebase ok: ${TWEAK_SHA_BEFORE:0:7} → ${TWEAK_SHA_AFTER:0:7} (+$UPSTREAM_AHEAD_BEFORE upstream commits, pushed)"
      echo "  ✓ rebase + push ok (+$UPSTREAM_AHEAD_BEFORE коммитов из upstream)" >&2
      return 0
    else
      mark_fail "fork-sync" "rebase ok, но push в origin упал — локально пайплайн продолжится, но origin отстаёт"
      echo "  ⚠ rebase ok, push fail — продолжаю локально" >&2
      return 0  # not fatal — local work is intact
    fi
  fi

  # Rebase failed → abort and report fork-diverged.
  git -C "$TWEAKCC_DIR" rebase --abort >/dev/null 2>&1 || true
  local local_commits
  local_commits=$(git -C "$TWEAKCC_DIR" log --oneline "upstream/main..HEAD" 2>/dev/null | head -5)
  log "rebase failed; local-only commits:"
  log "$local_commits"
  mark_fail "fork-sync" "форк разошёлся с upstream (есть локальные коммиты, не ff). Разрули вручную в $TWEAKCC_DIR"
  echo "  ✗ rebase conflict — форк разошёлся, разрули вручную" >&2
  return 1
}

# ────────────────────────────────────────────────────────────────────────────
# Step 3 — Rebuild tweakcc-fixed
# ────────────────────────────────────────────────────────────────────────────
step_3_build_tweakcc() {
  banner "3/6  пересобираю tweakcc-fixed"

  if ! run_capture "npm install" \
      bash -c "cd '$TWEAKCC_DIR' && npm install --no-audit --no-fund"; then
    mark_fail "build-tweakcc" "npm install упал"
    echo "  ✗ npm install fail" >&2
    return 1
  fi
  if ! run_capture "npm run build" \
      bash -c "cd '$TWEAKCC_DIR' && npm run build"; then
    mark_fail "build-tweakcc" "npm run build упал"
    echo "  ✗ npm run build fail" >&2
    return 1
  fi
  if [[ ! -f "$TWEAKCC_ENTRY" ]]; then
    mark_fail "build-tweakcc" "$TWEAKCC_ENTRY не появился после build"
    echo "  ✗ dist/index.mjs не появился" >&2
    return 1
  fi

  local size; size=$(stat -c %s "$TWEAKCC_ENTRY")
  mark_ok "build-tweakcc" "dist/index.mjs $(numfmt --to=iec "$size" 2>/dev/null || echo "${size}B")"
  echo "  ✓ собрано (dist/index.mjs $(numfmt --to=iec "$size" 2>/dev/null || echo "${size}B"))" >&2
  return 0
}

# ────────────────────────────────────────────────────────────────────────────
# Step 4 — Apply tweakcc to CC binary
# ────────────────────────────────────────────────────────────────────────────
step_4_apply_tweakcc() {
  banner "4/6  применяю tweakcc к claude code"

  [[ -f "$TWEAKCC_ENTRY" ]] || {
    mark_fail "apply-tweakcc" "$TWEAKCC_ENTRY не найден"
    echo "  ✗ нет $TWEAKCC_ENTRY" >&2
    return 1
  }

  # Reset ccInstallationPath so tweakcc re-detects the (just-updated) CC binary.
  if [[ -f "$TWEAKCC_CONFIG" ]]; then
    python3 - <<PY >>"$LOG_FILE" 2>&1
import json, pathlib
p = pathlib.Path("$TWEAKCC_CONFIG")
d = json.loads(p.read_text())
d['ccInstallationPath'] = None
p.write_text(json.dumps(d, indent=2) + '\n')
PY
  fi

  # Capture stdout/stderr separately to a temp so we can grep for the marker.
  local tmp_out; tmp_out=$(mktemp)
  if node "$TWEAKCC_ENTRY" --apply >"$tmp_out" 2>&1; then
    cat "$tmp_out" >>"$LOG_FILE"
    if grep -q "Customizations applied successfully" "$tmp_out"; then
      mark_ok "apply-tweakcc" "all patches applied"
      echo "  ✓ tweakcc applied" >&2
    elif grep -q "with some failures" "$tmp_out"; then
      local failed; failed=$(grep -oE '\[✗\][^|]*' "$tmp_out" | head -3 | tr '\n' '|' | sed 's/|$//')
      mark_fail "apply-tweakcc" "with some failures: ${failed:-detail см. в логе}"
      echo "  ⚠ tweakcc применился частично — см. лог" >&2
    else
      mark_ok "apply-tweakcc" "applied (no marker text — manual verify)"
      echo "  ✓ tweakcc applied (без явного маркера)" >&2
    fi
  else
    cat "$tmp_out" >>"$LOG_FILE"
    local err; err=$(grep -m1 -E "Cannot|Error|No saved" "$tmp_out" || tail -1 "$tmp_out")
    mark_fail "apply-tweakcc" "node --apply упал: $err"
    echo "  ✗ tweakcc --apply fail: $err" >&2
  fi
  rm -f "$tmp_out"

  return 0  # never fatal — next steps remain useful
}

# sync_local_clone <clone-dir> <repo-url> <ref>
# Ensures the clone exists, is on the right ref, and is built (npm install + run build
# if a build script exists). Idempotent. Returns 0 on success.
sync_local_clone() {
  local dir="$1" repo="$2" ref="$3"
  if [[ ! -d "$dir/.git" ]]; then
    mkdir -p "$(dirname "$dir")"
    if ! run_capture "git clone $repo $dir" git clone "$repo" "$dir"; then
      return 1
    fi
  fi
  run_capture "git fetch origin" git -C "$dir" fetch origin --quiet || true
  if ! run_capture "git checkout $ref" git -C "$dir" checkout "$ref"; then
    return 1
  fi
  if [[ -f "$dir/package.json" ]]; then
    # Prefer pnpm when a pnpm-lock.yaml is present — these repos' lockfiles
    # tickle a peer-dep resolution bug in modern npm. Fall back to npm if
    # no pnpm available.
    local install_cmd
    if [[ -f "$dir/pnpm-lock.yaml" ]] && command -v pnpm >/dev/null 2>&1; then
      install_cmd="pnpm install"
    else
      install_cmd="npm install --no-audit --no-fund"
    fi
    if ! run_capture "$install_cmd (in $dir)" \
        bash -c "cd '$dir' && $install_cmd"; then
      return 1
    fi
    if jq -re '.scripts.build' "$dir/package.json" >/dev/null 2>&1; then
      local build_cmd="npm run build"
      [[ "$install_cmd" == pnpm* ]] && build_cmd="pnpm run build"
      if ! run_capture "$build_cmd (in $dir)" \
          bash -c "cd '$dir' && $build_cmd"; then
        return 1
      fi
    fi
  fi
  return 0
}

# install_global_from_local <pkg-name> <clone-dir>
# Uses `npm link` from inside the clone — this only symlinks the bin into the
# active npm prefix (no full re-install), which sidesteps the npm peer-dep
# resolution bug that breaks `npm i -g <path>` on these repos' lockfiles.
# Assumes node_modules has already been populated by sync_local_clone.
install_global_from_local() {
  local pkg="$1" dir="$2"
  if ! run_capture "npm link (from $dir)" bash -c "cd '$dir' && npm link"; then
    return 1
  fi
  return 0
}

# detect_partial_apply <output-file>
# Looks for the "patch failed — restoring from backup" pattern that both
# cc-prompt-rewriter and cc-quote emit when at least one anchor isn't found.
# Echoes the failed-patch names (comma-separated) or empty string.
detect_partial_apply() {
  local out="$1"
  if grep -qE "patch failed — restoring|Restored\. No changes were written" "$out"; then
    grep -oE '✗ [a-zA-Z][a-zA-Z0-9_-]*' "$out" | sed 's/^✗ //' | sort -u | paste -sd, -
  fi
}

# ────────────────────────────────────────────────────────────────────────────
# Step 5 — cc-prompt-rewriter apply
# ────────────────────────────────────────────────────────────────────────────
step_5_apply_rewriter() {
  banner "5/6  применяю cc-prompt-rewriter"

  if ! sync_local_clone "$CC_REWRITER_CLONE" "$CC_REWRITER_REPO" "$CC_REWRITER_REF"; then
    mark_fail "apply-rewriter" "не удалось синхронизировать $CC_REWRITER_CLONE"
    echo "  ✗ sync cc-prompt-rewriter clone fail" >&2
    return 0
  fi

  if ! command -v cc-prompt-rewriter >/dev/null 2>&1; then
    if ! install_global_from_local "cc-prompt-rewriter" "$CC_REWRITER_CLONE"; then
      mark_fail "apply-rewriter" "global install из локального clone упал"
      echo "  ✗ install cc-prompt-rewriter fail" >&2
      return 0
    fi
    hash -r 2>/dev/null || true
  fi

  if ! command -v cc-prompt-rewriter >/dev/null 2>&1; then
    mark_fail "apply-rewriter" "установка прошла, но бинарь не на PATH (PNPM_HOME / npm prefix не в PATH?)"
    echo "  ✗ cc-prompt-rewriter не на PATH после install" >&2
    return 0
  fi

  local tmp_out; tmp_out=$(mktemp)
  cc-prompt-rewriter apply >"$tmp_out" 2>&1
  local rc=$?
  cat "$tmp_out" >>"$LOG_FILE"
  local failed; failed=$(detect_partial_apply "$tmp_out")
  if [[ -n "$failed" ]]; then
    # Partial-rollback path — package exits non-zero by design, output explains.
    mark_fail "apply-rewriter" "anchor-mismatch ($failed) — пакет targets старую CC, обнови repo"
    echo "  ⚠ cc-prompt-rewriter: anchor mismatch ($failed) — пакет нацелен на старую CC" >&2
  elif (( rc == 0 )); then
    mark_ok "apply-rewriter" "applied"
    echo "  ✓ cc-prompt-rewriter applied" >&2
  else
    local err; err=$(tail -3 "$tmp_out" | head -1)
    mark_fail "apply-rewriter" "cc-prompt-rewriter apply rc=$rc: $err"
    echo "  ✗ cc-prompt-rewriter apply fail (rc=$rc) — см. лог" >&2
  fi
  rm -f "$tmp_out"
  return 0
}

# ────────────────────────────────────────────────────────────────────────────
# Step 6 — cc-quote apply
# ────────────────────────────────────────────────────────────────────────────
step_6_apply_ccquote() {
  banner "6/6  применяю cc-quote"

  if ! sync_local_clone "$CC_QUOTE_CLONE" "$CC_QUOTE_REPO" "$CC_QUOTE_REF"; then
    mark_fail "apply-ccquote" "не удалось синхронизировать $CC_QUOTE_CLONE"
    echo "  ✗ sync cc-quote clone fail" >&2
    return 0
  fi

  if ! command -v cc-quote >/dev/null 2>&1; then
    if ! install_global_from_local "cc-quote" "$CC_QUOTE_CLONE"; then
      mark_fail "apply-ccquote" "global install из локального clone упал"
      echo "  ✗ install cc-quote fail" >&2
      return 0
    fi
    hash -r 2>/dev/null || true
  fi

  if ! command -v cc-quote >/dev/null 2>&1; then
    mark_fail "apply-ccquote" "установка прошла, но бинарь не на PATH (PNPM_HOME / npm prefix не в PATH?)"
    echo "  ✗ cc-quote не на PATH после install" >&2
    return 0
  fi

  local tmp_out; tmp_out=$(mktemp)
  cc-quote apply >"$tmp_out" 2>&1
  local rc=$?
  cat "$tmp_out" >>"$LOG_FILE"
  local failed; failed=$(detect_partial_apply "$tmp_out")
  if [[ -n "$failed" ]]; then
    mark_fail "apply-ccquote" "anchor-mismatch ($failed) — пакет targets старую CC, обнови repo"
    echo "  ⚠ cc-quote: anchor mismatch ($failed) — пакет нацелен на старую CC" >&2
  elif (( rc == 0 )); then
    mark_ok "apply-ccquote" "applied"
    echo "  ✓ cc-quote applied" >&2
  else
    local err; err=$(tail -3 "$tmp_out" | head -1)
    mark_fail "apply-ccquote" "cc-quote apply rc=$rc: $err"
    echo "  ✗ cc-quote apply fail (rc=$rc) — см. лог" >&2
  fi
  rm -f "$tmp_out"
  return 0
}

# ────────────────────────────────────────────────────────────────────────────
# Run pipeline
# ────────────────────────────────────────────────────────────────────────────
echo "" >&2
echo "[build-update] лог: $LOG_FILE" >&2
log "==== pipeline start ===="
log "args: $*"
log "skip-cc-update=$SKIP_CC_UPDATE  launch-after=$LAUNCH_AFTER"
log "versions.lock: ${VERSIONS_LOCK:-<not found>}"

CRITICAL_FAIL=0
if ! step_1_update_cc; then
  CRITICAL_FAIL=1
fi

if (( ! CRITICAL_FAIL )); then
  step_2_sync_fork    || true
  # Build only matters if fork sync didn't outright fail with an unfixable conflict.
  if [[ " ${STEPS_FAIL[*]} " != *" fork-sync "* ]]; then
    step_3_build_tweakcc || true
  else
    mark_skip "build-tweakcc"  "пропущено: fork-sync свалился"
    mark_skip "apply-tweakcc"  "пропущено: fork-sync свалился"
    echo "  ↷ пропускаю build/apply tweakcc (fork-sync свалился)" >&2
  fi
  # Apply tweakcc only if build succeeded.
  if [[ " ${STEPS_OK[*]} " == *" build-tweakcc "* ]]; then
    step_4_apply_tweakcc || true
  elif [[ " ${STEPS_SKIP[*]} " != *" apply-tweakcc "* ]]; then
    mark_skip "apply-tweakcc" "пропущено: build-tweakcc свалился"
    echo "  ↷ пропускаю apply tweakcc (build свалился)" >&2
  fi
  step_5_apply_rewriter || true
  step_6_apply_ccquote  || true
fi

# ────────────────────────────────────────────────────────────────────────────
# Final report
# ────────────────────────────────────────────────────────────────────────────
END_TS=$(date +%s)
ELAPSED=$((END_TS - START_TS))

banner "build-update — итог за ${ELAPSED}s"

print_row() {
  local sym="$1" label="$2" key="$3"
  printf "  %s  %-22s %s\n" "$sym" "$label" "${STEP_DETAIL[$key]:-}" >&2
}

(( CRITICAL_FAIL )) && echo "  ✗ critical fail на шаге 1 — остальные шаги не запускались" >&2

# Maintain pipeline order for readability:
order=(cc-update fork-sync build-tweakcc apply-tweakcc apply-rewriter apply-ccquote)
labels=(
  "CC update"
  "Sync fork"
  "Rebuild tweakcc"
  "Apply tweakcc"
  "Apply rewriter"
  "Apply cc-quote"
)
for i in "${!order[@]}"; do
  key="${order[$i]}"; lbl="${labels[$i]}"
  if [[ " ${STEPS_OK[*]} "   == *" $key "* ]]; then print_row "✓" "$lbl" "$key"; continue; fi
  if [[ " ${STEPS_FAIL[*]} " == *" $key "* ]]; then print_row "✗" "$lbl" "$key"; continue; fi
  if [[ " ${STEPS_SKIP[*]} " == *" $key "* ]]; then print_row "↷" "$lbl" "$key"; continue; fi
done

echo "" >&2
echo "  лог: $LOG_FILE" >&2
if [[ -n "${STEPS_FAIL[*]:-}" ]]; then
  echo "  rollback tweakcc: node $TWEAKCC_ENTRY --restore" >&2
fi

# Decide exit code AND clear/update status cache.
write_status() {
  local tmp="$STATUS_FILE.tmp.$$"
  : > "$tmp"
  for kv in "$@"; do printf '%s\n' "$kv" >> "$tmp"; done
  mv -f "$tmp" "$STATUS_FILE"
}

NOW_TS=$(date +%s)
CC_NOW=$(cc_version)

if (( CRITICAL_FAIL )); then
  EXIT=1
elif (( ${#STEPS_FAIL[@]} > 0 )); then
  EXIT=2
else
  EXIT=0
fi

if (( EXIT == 0 )); then
  write_status "up_to_date=1" "checked_at=$NOW_TS" "cc_version=$CC_NOW" "last_apply_at=$NOW_TS"
else
  write_status "checked_at=$NOW_TS" "cc_version=$CC_NOW" "last_apply_at=$NOW_TS" "last_apply_failed=1"
fi

log "==== pipeline end (exit=$EXIT, elapsed=${ELAPSED}s) ===="

# ────────────────────────────────────────────────────────────────────────────
# Launch CC if asked and we didn't critically fail.
# ────────────────────────────────────────────────────────────────────────────
if (( LAUNCH_AFTER )); then
  if (( CRITICAL_FAIL )); then
    printf "Запустить старый claude (%s) всё равно? [Y/n]: " "$CC_NOW" >&2
    reply=""
    IFS= read -r reply || reply=""
    case "${reply,,}" in
      ""|y|yes|д|да) exec command claude ;;
      *) exit "$EXIT" ;;
    esac
  else
    echo "" >&2
    echo "Запускаю claude…" >&2
    exec command claude
  fi
fi

exit "$EXIT"
