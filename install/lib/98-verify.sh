#!/usr/bin/env bash
set -euo pipefail
# Postcondition checks. Accumulates pass/fail (does NOT bail on first failure),
# writes the structured result to ~/.claude/last-install.json. Exit code 0 if
# nothing failed, 1 otherwise. Degraded conditions (e.g. --fresh-auth, linger
# off) are reported but do not fail the verify step — they're for the caller
# (a human or an AI agent) to decide on.

OUT="$HOME/.claude/last-install.json"
mkdir -p "$(dirname "$OUT")"

ts() { date -u +%Y-%m-%dT%H:%M:%SZ; }

PASSED=()
FAILED=()        # entries: "name|description|hint_anchor"
DEGRADED=()      # entries: free-form strings

# check NAME "human description" "shell expression" "hint_anchor"
# The shell expression is run via `bash -c` so quoting in $cmd is local.
check() {
  local name="$1" desc="$2" cmd="$3" hint="$4"
  if bash -c "$cmd" >/dev/null 2>&1; then
    PASSED+=("$name")
  else
    FAILED+=("$name|$desc|$hint")
  fi
}

# degraded REASON — flag a soft condition that doesn't fail verify.
degraded() { DEGRADED+=("$1"); }

# --- DRY_RUN shortcut ---
if [[ ${DRY_RUN:-0} -eq 1 ]]; then
  jq -n \
    --arg ts "$(ts)" --arg host "$(hostname)" \
    '{schema_version:1, written_at:$ts, host:$host, status:"dry-run"}' > "$OUT"
  echo "[dry] wrote stub $OUT (status=dry-run)"
  exit 0
fi

# --- Gather context (best-effort; missing values become "unknown") ---
CC_VER_NOW="$(claude --version 2>&1 | awk '{print $1}' | head -1 || echo unknown)"
HEAD_SHA="$(git -C "${REPO_DIR:-$PWD}" rev-parse HEAD 2>/dev/null || echo unknown)"
PINNED_AT="${TREASURE_snapshot_built_at:-unknown}"
TREASURE_CC="${TREASURE_claude_code:-unknown}"
TREASURE_CCOM_SHA="${TREASURE_ccometixline_ref:-unknown}"
TREASURE_CCOM_SHA256="${TREASURE_ccometixline_sha256:-unknown}"
TREASURE_TW_SHA="${TREASURE_tweakcc_fixed_ref:-unknown}"

# === Invariants — Binaries & versions ===
check claude_binary \
      "claude binary on PATH" \
      'command -v claude' \
      "troubleshooting.md#prereq"

if [[ "$TREASURE_CC" != "unknown" && "$TREASURE_CC" != "latest" ]]; then
  check claude_version_match \
        "claude --version matches versions.lock ($TREASURE_CC)" \
        "[[ \"$CC_VER_NOW\" == \"$TREASURE_CC\" ]]" \
        "troubleshooting.md#drift"
fi

check ccline_binary \
      "~/.claude/ccline/ccline is executable" \
      '[[ -x "$HOME/.claude/ccline/ccline" ]] && "$HOME/.claude/ccline/ccline" --version' \
      "troubleshooting.md#build"

if [[ "$TREASURE_CCOM_SHA256" != "unknown" ]]; then
  check ccline_sha256 \
        "ccline sha256 matches pin" \
        "sha256sum \"\$HOME/.claude/ccline/ccline\" | awk '{print \$1}' | grep -q '^$TREASURE_CCOM_SHA256\$'" \
        "troubleshooting.md#build"
fi

# === Invariants — Files & perms ===
check envrc_exists \
      "~/.envrc exists" \
      '[[ -f "$HOME/.envrc" ]]' \
      "troubleshooting.md#gpg"

# mode_of: portable octal file-mode read. GNU coreutils uses `-c %a`, BSD
# (macOS) uses `-f %A`. Try both, return the first that succeeds.
mode_of() { stat -c %a "$1" 2>/dev/null || stat -f %A "$1" 2>/dev/null; }
export -f mode_of

check envrc_mode_600 \
      "~/.envrc has mode 0600" \
      '[[ "$(mode_of "$HOME/.envrc")" == "600" ]]' \
      "troubleshooting.md#perms"

# .credentials.json: only check when FRESH_AUTH was not requested
if [[ ${FRESH_AUTH:-0} -ne 1 ]]; then
  check credentials_mode_600 \
        "~/.claude/.credentials.json mode 0600" \
        '[[ ! -f "$HOME/.claude/.credentials.json" ]] || [[ "$(mode_of "$HOME/.claude/.credentials.json")" == "600" ]]' \
        "troubleshooting.md#perms"
fi

check ssh_mode_700 \
      "~/.ssh has mode 0700" \
      '[[ ! -d "$HOME/.ssh" ]] || [[ "$(mode_of "$HOME/.ssh")" == "700" ]]' \
      "troubleshooting.md#perms"

check gnupg_mode_700 \
      "~/.gnupg has mode 0700" \
      '[[ ! -d "$HOME/.gnupg" ]] || [[ "$(mode_of "$HOME/.gnupg")" == "700" ]]' \
      "troubleshooting.md#perms"

check secrets_gpg_mode_600 \
      "all secrets/*.gpg in repo are 0600" \
      "! find \"\${REPO_DIR:-$PWD}/secrets\" -name '*.gpg' -type f \\! -perm 600 2>/dev/null | grep -q ." \
      "troubleshooting.md#perms"

# === Invariants — Symlinks ===
check tweakcc_system_prompts_link \
      "~/.tweakcc/system-prompts symlinked to lobotomized clone" \
      '[[ -L "$HOME/.tweakcc/system-prompts" ]] && readlink "$HOME/.tweakcc/system-prompts" | grep -q lobotomized' \
      "troubleshooting.md#symlinks"

# Skill symlinks — only check if there's at least one to verify
if compgen -G "$HOME/.claude/skills/*" >/dev/null; then
  check skill_symlinks_resolve \
        "every ~/.claude/skills/* symlink resolves" \
        'for s in "$HOME"/.claude/skills/*; do [[ -L "$s" && ! -e "$s" ]] && exit 1; done; true' \
        "troubleshooting.md#symlinks"
fi

# === Invariants — Build artifacts / repo health ===
check tweakcc_dist_present \
      "~/dev/tweakcc-fixed/dist/index.mjs exists" \
      '[[ -f "$HOME/dev/tweakcc-fixed/dist/index.mjs" ]]' \
      "troubleshooting.md#npm"

if [[ "$TREASURE_CCOM_SHA" != "unknown" ]]; then
  check ccometixline_ref_match \
        "~/dev/CCometixLine HEAD matches pin" \
        "[[ \"\$(git -C \$HOME/dev/CCometixLine rev-parse HEAD 2>/dev/null)\" == \"$TREASURE_CCOM_SHA\" ]]" \
        "troubleshooting.md#drift"
fi

if [[ "$TREASURE_TW_SHA" != "unknown" ]]; then
  check tweakcc_fixed_ref_match \
        "~/dev/tweakcc-fixed HEAD matches pin" \
        "[[ \"\$(git -C \$HOME/dev/tweakcc-fixed rev-parse HEAD 2>/dev/null)\" == \"$TREASURE_TW_SHA\" ]]" \
        "troubleshooting.md#drift"
fi

# === Invariants — MCP ===
if [[ -d "$HOME/.claude/mcp" ]]; then
  check mcp_package_json \
        "~/.claude/mcp/package.json is valid JSON" \
        'jq . "$HOME/.claude/mcp/package.json"' \
        "troubleshooting.md#npm"

  check mcp_node_modules_nonempty \
        "~/.claude/mcp/node_modules has contents" \
        '[[ -d "$HOME/.claude/mcp/node_modules" ]] && [[ -n "$(ls -A "$HOME/.claude/mcp/node_modules" 2>/dev/null)" ]]' \
        "troubleshooting.md#npm"
fi

# === Invariants — Systemd timers ===
if [[ ${SKIP_SYSTEMD:-0} -ne 1 ]] && command -v systemctl >/dev/null && systemctl --user status >/dev/null 2>&1; then
  for timer in claude-snapshot claude-pull claude-prune; do
    check "${timer}_timer_active" \
          "${timer}.timer is active" \
          "systemctl --user is-active ${timer}.timer | grep -q '^active\$'" \
          "troubleshooting.md#systemd"
  done

  # Linger: degraded, not fail. systemd user timers stop firing after logout
  # without linger, so this matters for headless boxes specifically.
  if loginctl show-user "$USER" --property=Linger 2>/dev/null | grep -q '^Linger=no$'; then
    degraded "loginctl linger is disabled — timers stop when this user logs out (run: sudo loginctl enable-linger $USER)"
  fi
fi

# === Invariants — Tweakcc state ===
check tweakcc_config_json \
      "~/.tweakcc/config.json is valid JSON" \
      'jq . "$HOME/.tweakcc/config.json"' \
      "troubleshooting.md#tweakcc"

check tweakcc_changes_applied \
      "~/.tweakcc/config.json has changesApplied: true" \
      'jq -e ".changesApplied == true" "$HOME/.tweakcc/config.json"' \
      "troubleshooting.md#tweakcc"

# === Invariants — Misc ===
check direnv_binary \
      "direnv binary present (PATH or ~/.local/bin)" \
      'command -v direnv || [[ -x "$HOME/.local/bin/direnv" ]]' \
      "troubleshooting.md#prereq"

check zshrc_present \
      "~/.zshrc exists" \
      '[[ -f "$HOME/.zshrc" ]]' \
      "troubleshooting.md#drift"

# === Degraded signals from install flags ===
[[ ${FRESH_AUTH:-0} -eq 1 ]]   && degraded "FRESH_AUTH=1 — Claude credentials not restored; run \`claude\` and login"
[[ ${SKIP_SECRETS:-0} -eq 1 ]] && degraded "SKIP_SECRETS=1 — secrets not decrypted; run \`bash install/lib/95-secrets.sh\` later"
[[ ${SKIP_SYSTEMD:-0} -eq 1 ]] && degraded "SKIP_SYSTEMD=1 — timers not enabled; multi-machine sync is off"

# === Emit JSON ===
TOTAL=$(( ${#PASSED[@]} + ${#FAILED[@]} ))

# Build failed-objects array.
if [[ ${#FAILED[@]} -gt 0 ]]; then
  FAILED_JSON=$(printf '%s\n' "${FAILED[@]}" \
    | jq -R 'split("|") | {name: .[0], description: .[1], hint: .[2]}' \
    | jq -s .)
else
  FAILED_JSON='[]'
fi

# Degraded-reasons array.
if [[ ${#DEGRADED[@]} -gt 0 ]]; then
  DEGRADED_JSON=$(printf '%s\n' "${DEGRADED[@]}" | jq -R . | jq -s .)
else
  DEGRADED_JSON='[]'
fi

STATUS="ok"
[[ ${#FAILED[@]} -gt 0 ]] && STATUS="fail"

# Next-action hint: if anything failed, point to troubleshooting; otherwise to snapshot.
if [[ "$STATUS" == "fail" ]]; then
  NEXT_ACTION="For each invariants_failed[].hint, jump to docs/troubleshooting.md anchor, apply fix, re-run \`bash install/lib/98-verify.sh\`"
else
  NEXT_ACTION="Install complete. Snapshot will fire on next :00 hour boundary."
fi

jq -n \
  --arg ts "$(ts)" \
  --arg host "$(hostname)" \
  --arg os "$(uname -s | tr '[:upper:]' '[:lower:]')" \
  --arg arch "$(uname -m)" \
  --arg repo_dir "${REPO_DIR:-$PWD}" \
  --arg head "$HEAD_SHA" \
  --arg cc_ver "$CC_VER_NOW" \
  --arg pinned_at "$PINNED_AT" \
  --arg status "$STATUS" \
  --argjson total "$TOTAL" \
  --argjson passed "${#PASSED[@]}" \
  --argjson failed_arr "$FAILED_JSON" \
  --argjson degraded_arr "$DEGRADED_JSON" \
  --arg next_action "$NEXT_ACTION" \
  --argjson flags "$(jq -n \
    --argjson dry "${DRY_RUN:-0}" \
    --argjson fresh "${FRESH_AUTH:-0}" \
    --argjson sbuild "${SKIP_BUILD:-0}" \
    --argjson ssec "${SKIP_SECRETS:-0}" \
    --argjson ssys "${SKIP_SYSTEMD:-0}" \
    --argjson stool "${SKIP_SERVICES_TOOLING:-0}" \
    '{dry_run: ($dry==1), fresh_auth: ($fresh==1), skip_build: ($sbuild==1),
      skip_secrets: ($ssec==1), skip_systemd: ($ssys==1), skip_services_tooling: ($stool==1)}')" \
  '{
    schema_version: 1,
    written_at: $ts,
    host: $host,
    os: $os,
    arch: $arch,
    repo_dir: $repo_dir,
    repo_head_sha: $head,
    claude_code_version: $cc_ver,
    snapshot_pinned_at: $pinned_at,
    install_flags: $flags,
    status: $status,
    invariants_total: $total,
    invariants_passed: $passed,
    invariants_failed: $failed_arr,
    degraded: ($degraded_arr | length > 0),
    degraded_reasons: $degraded_arr,
    next_actions: [$next_action]
  }' > "$OUT"

echo ""
echo "  $TOTAL invariants checked: ${#PASSED[@]} passed, ${#FAILED[@]} failed"
[[ ${#DEGRADED[@]} -gt 0 ]] && echo "  degraded signals: ${#DEGRADED[@]}"
echo "  wrote $OUT"

if [[ "$STATUS" == "fail" ]]; then
  echo "  next: jq -r '.invariants_failed[] | .name + \" → \" + .hint' $OUT"
  exit 1
fi
exit 0
