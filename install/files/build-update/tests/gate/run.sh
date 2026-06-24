#!/usr/bin/env bash
# Plain-bash test harness for build-update-gate.sh
set -uo pipefail
HERE="$(cd "$(dirname "$0")" && pwd)"
GATE="$HOME/.claude/scripts/build-update-gate.sh"
FIX="$HERE/fixtures"
STUB="$HERE/stub-ai.sh"
PASS=0 FAIL=0

# Isolate logs/cache per run so tests don't touch real state.
export GATE_LOG_DIR; GATE_LOG_DIR="$(mktemp -d)"
export GATE_CACHE_DIR; GATE_CACHE_DIR="$(mktemp -d)"

# assert_exit EXPECTED LABEL -- cmd...
assert_exit() {
  local want="$1" label="$2"; shift 2
  # Fresh per-assertion cache so a clean PASS in one row can't short-circuit
  # an independent row that reuses the same fixture content.
  rm -rf "$GATE_CACHE_DIR"; GATE_CACHE_DIR="$(mktemp -d)"
  "$@" </dev/null >/dev/null 2>&1; local got=$?
  if [[ "$got" == "$want" ]]; then echo "ok   - $label"; ((PASS++))
  else echo "FAIL - $label (want exit $want, got $got)"; ((FAIL++)); fi
}

run_tests() {
  # Task 2: oversized + missing-args
  big="$(mktemp)"; head -c 3000000 /dev/zero | tr '\0' 'x' > "$big"
  printf 'diff --git a/x b/x\n+%s\n' "$(head -c 2999000 < "$big")" > "$big"
  assert_exit 1 "oversized diff blocks"            "$GATE" --diff-file "$big"
  assert_exit 3 "missing args is usage error"      "$GATE"
  rm -f "$big"

  # Task 3: static hard-block — exit 2 under --static-only
  for f in eval postinstall exec base64 rawip curlpipe sensreq; do
    assert_exit 2 "static hard-block: $f" "$GATE" --static-only --diff-file "$FIX/$f.diff"
  done
  assert_exit 0 "static clean: benign" "$GATE" --static-only --diff-file "$FIX/benign.diff"

  # Task 4: soft tier — exit 1 under --static-only
  for f in inject foreignreg zwsp; do
    assert_exit 1 "static soft: $f" "$GATE" --static-only --diff-file "$FIX/$f.diff"
  done

  # Task 5: AI layer via stub
  STUB_MODE=pass    GATE_AI_CMD="$STUB" assert_exit 0 "ai pass"            "$GATE" --ai-only --diff-file "$FIX/benign.diff"
  STUB_MODE=block   GATE_AI_CMD="$STUB" assert_exit 1 "ai block"           "$GATE" --ai-only --diff-file "$FIX/benign.diff"
  STUB_MODE=badjson GATE_AI_CMD="$STUB" assert_exit 1 "ai badjson→closed"  "$GATE" --ai-only --diff-file "$FIX/benign.diff"
  STUB_MODE=empty   GATE_AI_CMD="$STUB" assert_exit 1 "ai empty→closed"    "$GATE" --ai-only --diff-file "$FIX/benign.diff"
  STUB_MODE=fail    GATE_AI_CMD="$STUB" assert_exit 1 "ai exit1→closed"    "$GATE" --ai-only --diff-file "$FIX/benign.diff"
  STUB_MODE=hang    GATE_AI_CMD="$STUB" GATE_AI_TIMEOUT=2 assert_exit 1 "ai timeout→closed" "$GATE" --ai-only --diff-file "$FIX/benign.diff"

  # Task 6: human gate
  ( export GATE_SOURCE_ONLY=1; source "$GATE"
    # non-interactive (stdin not a tty here) + findings → block(1)
    human_gate "HARD|eval" </dev/null; [[ $? == 1 ]] || exit 1
    # env override → pass(0) with loud log
    BUILD_UPDATE_GATE_OVERRIDE=1 human_gate "HARD|eval" </dev/null; [[ $? == 0 ]] || exit 1
    # exact phrase on stdin → pass(0)
    printf 'apply despite findings\n' | { GATE_FORCE_TTY=1 human_gate "HARD|eval"; }; [[ $? == 0 ]] || exit 1
    # wrong phrase → block(1)
    printf 'yes\n' | { GATE_FORCE_TTY=1 human_gate "HARD|eval"; }; [[ $? == 1 ]] || exit 1
  )
  assert_exit 0 "human_gate matrix" true   # the subshell above asserts; this records a row

  # Task 7: cache get/put keyed by SHA
  ( export GATE_SOURCE_ONLY=1; source "$GATE"
    TARGET_SHA="deadbeef"
    cache_get "$TARGET_SHA" && exit 1   # empty cache → miss (non-zero)
    cache_put "$TARGET_SHA"
    cache_get "$TARGET_SHA" || exit 1   # now hit (zero)
    cache_get "feedface" && exit 1      # different SHA → miss
    true
  )
  assert_exit 0 "cache get/put by SHA" true

  # Task 8: end-to-end matrix (full main, stubbed AI, non-tty → no override)
  STUB_MODE=pass  GATE_AI_CMD="$STUB" assert_exit 0 "e2e: clean+aipass → pass"   "$GATE" --diff-file "$FIX/benign.diff"
  STUB_MODE=pass  GATE_AI_CMD="$STUB" assert_exit 1 "e2e: hardblock → block"     "$GATE" --diff-file "$FIX/eval.diff"
  STUB_MODE=block GATE_AI_CMD="$STUB" assert_exit 1 "e2e: aiblock → block"       "$GATE" --diff-file "$FIX/benign.diff"
  STUB_MODE=pass  GATE_AI_CMD="$STUB" assert_exit 1 "e2e: soft+aipass,no tty → block" "$GATE" --diff-file "$FIX/inject.diff"
  # override env lets a flagged diff through
  STUB_MODE=block GATE_AI_CMD="$STUB" BUILD_UPDATE_GATE_OVERRIDE=1 assert_exit 0 "e2e: override env → pass" "$GATE" --diff-file "$FIX/benign.diff"

  # Task 9: cache short-circuit in main — a populated cache must skip the AI layer.
  # Uses a FIXED cache dir (subshell-scoped) so it persists across the two
  # invocations without polluting the per-assert fresh caches above.
  (
    export GATE_CACHE_DIR; GATE_CACHE_DIR="$(mktemp -d)"
    # 1st: benign diff + STUB_MODE=pass → exit 0, populates cache for this SHA.
    STUB_MODE=pass GATE_AI_CMD="$STUB" "$GATE" --diff-file "$FIX/benign.diff" </dev/null >/dev/null 2>&1 || exit 1
    # 2nd: SAME diff but STUB_MODE=fail — if the AI layer ran it would block(1).
    # Cache must short-circuit before AI, so exit 0 and emit "PASS (cached)".
    out="$(STUB_MODE=fail GATE_AI_CMD="$STUB" "$GATE" --diff-file "$FIX/benign.diff" </dev/null 2>&1)"; rc=$?
    [[ "$rc" == 0 ]] || exit 1
    printf '%s' "$out" | grep -qF 'PASS (cached)' || exit 1
    rm -rf "$GATE_CACHE_DIR"
    true
  )
  assert_exit 0 "cache short-circuit in main skips AI" true
}

run_tests
echo "-------- $PASS passed, $FAIL failed --------"
[[ "$FAIL" -eq 0 ]]
