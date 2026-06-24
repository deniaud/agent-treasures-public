#!/usr/bin/env bash
# Mirror current Claude Code stack into ~/dev/claude-treasures (git-native repo).
# Idempotent: re-running just updates what changed and commits the diff.
#
# Triggered hourly by ~/.config/systemd/user/claude-snapshot.timer (at :00 with
# ±5 min jitter); paired with claude-pull.timer at :30 on follower machines.
# Also wired as the `/snapshot` slash command.

set -euo pipefail

LOG="$HOME/.claude/cleanup.log"
exec > >(tee -a "$LOG") 2>&1

ts() { date -u +%Y-%m-%dT%H:%M:%SZ; }
log() { printf '[%s snapshot] %s\n' "$(ts)" "$*"; }
log "=== START ==="

TREASURES="$HOME/dev/agent-treasures"
if [[ ! -d "$TREASURES" ]]; then
  log "ERROR: $TREASURES not found. Clone it first:"
  log "  git clone <url> $TREASURES"
  exit 1
fi
if [[ ! -d "$TREASURES/.git" ]]; then
  log "ERROR: $TREASURES is not a git checkout. Init manually."
  exit 1
fi

SEAL_PP_FILE="$HOME/claude-recipe-seal-passphrase.txt"
if [[ ! -f "$SEAL_PP_FILE" ]]; then
  log "ERROR: $SEAL_PP_FILE missing — can't re-encrypt secrets."
  exit 1
fi

# === Race-safety: sync with origin BEFORE mirroring ===
# Hourly snapshots running on multiple machines will race on push. We mitigate
# by: (a) pulling origin first so our commit lands on top of latest remote
# state; (b) push-with-retry that re-fetches + rebases on each failure.
if git -C "$TREASURES" remote get-url origin >/dev/null 2>&1; then
  log "Syncing with origin before mirror ..."
  if ! git -C "$TREASURES" fetch --quiet origin 2>&1; then
    log "WARN: fetch failed (offline?) — will proceed but push may fail later"
  else
    if ! git -C "$TREASURES" merge-base --is-ancestor HEAD origin/main 2>/dev/null; then
      log "Local commits diverged from origin/main — rebasing ..."
      if ! git -C "$TREASURES" rebase --quiet origin/main; then
        log "ERROR: rebase conflict on origin/main — aborting"
        git -C "$TREASURES" rebase --abort 2>/dev/null || true
        exit 4
      fi
    else
      # Local at-or-behind origin: fast-forward to align.
      git -C "$TREASURES" merge --ff-only --quiet origin/main 2>/dev/null || true
    fi
  fi
fi

# === Noise-reduction helpers ===

# normalize_json: strip volatile fields from a JSON file in place. If jq fails
# (malformed JSON, missing field), the original file is left untouched.
# Reason: hourly snapshots otherwise churn every cycle on auto-updated
# timestamps (MCP marketplace, codex cache, tweakcc state), creating empty
# commits and constant pull conflicts.
normalize_json() {
  local file="$1" jq_expr="$2" tmp
  [[ -f "$file" ]] || return 0
  tmp=$(mktemp)
  if jq "$jq_expr" "$file" > "$tmp" 2>/dev/null; then
    mv "$tmp" "$file"
  else
    rm -f "$tmp"
    log "WARN: jq normalization failed for $file (kept original)"
  fi
}

# seal_if_changed: GPG-encrypts $tmp_plaintext → $out, but only if the plaintext
# hash differs from the side-car ${out}.sha256. Without this, GPG's random IV
# produces a fresh ciphertext on every run even when the input is identical —
# unusable for hourly snapshots.
seal_if_changed() {
  local out="$1" tmp_plaintext="$2"
  local sha_file="$out.sha256" new_sha
  new_sha=$(sha256sum "$tmp_plaintext" | awk '{print $1}')
  if [[ -f "$sha_file" && -f "$out" ]] && [[ "$(cat "$sha_file")" == "$new_sha" ]]; then
    return 0
  fi
  gpg --batch --yes --pinentry-mode loopback \
      --passphrase-file "$SEAL_PP_FILE" \
      --symmetric --cipher-algo AES256 \
      --output "$out" "$tmp_plaintext"
  chmod 600 "$out"
  printf '%s\n' "$new_sha" > "$sha_file"
  chmod 600 "$sha_file"
}

# seal_pipe: read plaintext from stdin (typical: `tar -cf - dir | seal_pipe out`)
seal_pipe() {
  local out="$1" tmp
  tmp=$(mktemp)
  cat > "$tmp"
  seal_if_changed "$out" "$tmp"
  shred -u "$tmp" 2>/dev/null || rm -f "$tmp"
}

# seal_file: encrypt an existing file (typical: `seal_file out src`)
seal_file() { seal_if_changed "$1" "$2"; }

# gen_symlinks_manifest: enumerate symlinks in $skills_dir and emit
# `name -> target_basename` lines (sorted) to $out_file. Skips non-symlink
# entries (e.g. `.system/` dirs). Consumed by install/lib/85-skill-symlinks.sh
# on the follower to recreate the same symlinks against ~/.cc-switch/skills/.
gen_symlinks_manifest() {
  local skills_dir="$1" out_file="$2"
  [[ -d "$skills_dir" ]] || return 0
  mkdir -p "$(dirname "$out_file")"
  (
    cd "$skills_dir"
    for entry in * .[!.]*; do
      [[ -L "$entry" ]] || continue
      target=$(readlink "$entry")
      printf '%s -> %s\n' "$entry" "$(basename "$target")"
    done | LC_ALL=C sort
  ) > "$out_file"
}

# === Mirror into claude/ + host/ buckets ===
CLAUDE_DST="$TREASURES/claude"
HOST_DST="$TREASURES/host"

# --- claude/ bucket ---
log "Mirroring ~/.claude → claude/.claude (respects ~/.claude/.gitignore) ..."
rm -rf "$CLAUDE_DST/.claude"
mkdir -p "$CLAUDE_DST/.claude"
(
  cd "$HOME/.claude"
  # git ls-files may list paths that were `rm`'d without `git rm` — filter those out.
  git ls-files -z | (
    while IFS= read -r -d '' f; do
      [[ -e "$f" || -L "$f" ]] && printf '%s\0' "$f"
    done
  ) | tar --null --dereference -cf - --files-from=- 2>/dev/null | tar -xf - -C "$CLAUDE_DST/.claude/"
)

# Strip volatile timestamp fields from mirrored ~/.claude JSONs.
# walk(...) recurses into arrays/objects — known_marketplaces.json is an array
# of marketplace entries, each with its own .lastUpdated.
normalize_json "$CLAUDE_DST/.claude/plugins/known_marketplaces.json" \
  'walk(if type == "object" then del(.lastUpdated, .fetchedAt) else . end)'
normalize_json "$CLAUDE_DST/.claude/plugins/blocklist.json"          'del(.fetchedAt)'

log "Generating skills manifest → claude/.claude/skills/_symlinks.txt ..."
gen_symlinks_manifest "$HOME/.claude/skills" "$CLAUDE_DST/.claude/skills/_symlinks.txt"

log "Mirroring ~/.cc-switch → claude/.cc-switch ..."
rm -rf "$CLAUDE_DST/.cc-switch"
mkdir -p "$CLAUDE_DST/.cc-switch/skills"
cp "$HOME/.cc-switch/settings.json" "$CLAUDE_DST/.cc-switch/settings.json" 2>/dev/null || true
cp -a "$HOME/.cc-switch/skills/." "$CLAUDE_DST/.cc-switch/skills/" 2>/dev/null || true

log "Mirroring ~/.tweakcc/config.json → claude/.tweakcc/ ..."
mkdir -p "$CLAUDE_DST/.tweakcc"
cp "$HOME/.tweakcc/config.json" "$CLAUDE_DST/.tweakcc/config.json"
# tweakcc rewrites lastModified/changesApplied on every --apply (which can run
# automatically after `claude update`). ccVersion is kept — it's a real signal.
normalize_json "$CLAUDE_DST/.tweakcc/config.json" 'del(.lastModified, .changesApplied)'

log "Mirroring claude-* systemd units → claude/.config/systemd/user/ ..."
mkdir -p "$CLAUDE_DST/.config/systemd/user"
rm -f "$CLAUDE_DST/.config/systemd/user/"*.service "$CLAUDE_DST/.config/systemd/user/"*.timer 2>/dev/null
for u in claude-snapshot claude-pull claude-prune; do
  for ext in service timer; do
    src="$HOME/.config/systemd/user/$u.$ext"
    [[ -f "$src" ]] && cp "$src" "$CLAUDE_DST/.config/systemd/user/"
  done
done

# --- host/ bucket ---
log "Mirroring shell rcs → host/ ..."
cp "$HOME/.zshrc"  "$HOST_DST/.zshrc"
cp "$HOME/.zshenv" "$HOST_DST/.zshenv"
sed -E 's/(export [A-Z_]+=)"[^"]*"/\1"<FILL_FROM_SECRETS>"/' "$HOME/.envrc" > "$HOST_DST/.envrc.template"

log "Mirroring tooling systemd units → host/.config/systemd/user/ ..."
mkdir -p "$HOST_DST/.config/systemd/user"
rm -f "$HOST_DST/.config/systemd/user/"*.service "$HOST_DST/.config/systemd/user/"*.timer 2>/dev/null
for src in "$HOME/.config/systemd/user/"*.service "$HOME/.config/systemd/user/"*.timer; do
  [[ -f "$src" ]] || continue
  name="$(basename "$src")"
  case "$name" in
    claude-snapshot.*|claude-pull.*|claude-prune.*) continue ;;
    *) cp "$src" "$HOST_DST/.config/systemd/user/" ;;
  esac
done

# --- misc dotfiles + .config whitelist ---
log "Mirroring misc dotfiles + ~/.config whitelist → host/ ..."
[[ -f "$HOME/.gitconfig" ]] && cp "$HOME/.gitconfig" "$HOST_DST/.gitconfig"
[[ -f "$HOME/.bashrc"    ]] && cp "$HOME/.bashrc"    "$HOST_DST/.bashrc"

# Portable user scripts in ~/.local/bin/ (whitelist; skip symlinks / binaries).
log "Mirroring portable ~/.local/bin/ scripts → host/.local/bin/ ..."
BIN_DST="$HOST_DST/.local/bin"
mkdir -p "$BIN_DST"
for name in folder; do
  src="$HOME/.local/bin/$name"
  [[ -f "$src" && ! -L "$src" ]] && cp "$src" "$BIN_DST/$name"
done

# Codex configs (filtered)
CODEX_DST="$HOST_DST/.codex"
rm -rf "$CODEX_DST"
mkdir -p "$CODEX_DST"
for f in AGENTS.md config.toml models_cache.json installation_id; do
  [[ -f "$HOME/.codex/$f" ]] && cp "$HOME/.codex/$f" "$CODEX_DST/"
done
for d in rules memories plugins; do
  [[ -d "$HOME/.codex/$d" ]] && cp -a "$HOME/.codex/$d" "$CODEX_DST/"
done
# skills/: only the manifest, not the actual symlinks (those are recreated
# from cc-switch on the follower via install/lib/85-skill-symlinks.sh).
gen_symlinks_manifest "$HOME/.codex/skills" "$CODEX_DST/skills/_symlinks.txt"
# (auth.json, sessions, log, logs_2.sqlite*, history.jsonl, cache, old_skills — NOT mirrored)
# Codex refreshes models_cache.json on every CLI run; the etag/fetched_at fields
# rotate even when the actual model list is unchanged.
normalize_json "$CODEX_DST/models_cache.json" 'del(.fetched_at, .etag)'

# ~/.config whitelist
CFG_DST="$HOST_DST/.config"
mkdir -p "$CFG_DST"
  src="$HOME/.config/$d"
  [[ -d "$src" ]] || continue
  rm -rf "$CFG_DST/$d"
  if [[ "$d" == "opencode" ]]; then
    # opencode: opencode.json + AGENTS.md + agent/*.md + skills manifest
    # (NOT node_modules, NOT the actual skill symlinks — recreated from cc-switch
    # on the follower via install/lib/85-skill-symlinks.sh)
    mkdir -p "$CFG_DST/$d"
    [[ -f "$src/opencode.json" ]] && cp "$src/opencode.json" "$CFG_DST/$d/"
    [[ -f "$src/AGENTS.md"     ]] && cp "$src/AGENTS.md"     "$CFG_DST/$d/"
    if [[ -d "$src/agent" ]]; then
      mkdir -p "$CFG_DST/$d/agent"
      cp -a "$src/agent/." "$CFG_DST/$d/agent/"
    fi
    gen_symlinks_manifest "$src/skills" "$CFG_DST/$d/skills/_symlinks.txt"
  else
    cp -a "$src" "$CFG_DST/$d"
  fi
done

# VS Code User/ (settings, snippets, chatLanguageModels) + extensions.list (NO extensions tree, NO state)
CODE_USER="$CFG_DST/Code/User"
mkdir -p "$CODE_USER"
for f in settings.json keybindings.json chatLanguageModels.json; do
  [[ -f "$HOME/.config/Code/User/$f" ]] && cp "$HOME/.config/Code/User/$f" "$CODE_USER/"
done
[[ -d "$HOME/.config/Code/User/snippets" ]] && cp -a "$HOME/.config/Code/User/snippets" "$CODE_USER/" 2>/dev/null
if command -v code >/dev/null 2>&1; then
  code --list-extensions 2>/dev/null > "$CFG_DST/Code/extensions.list" || true
fi

# --- sealed secret files (re-encrypt only if plaintext changed) ---
# passphrase via --passphrase-file: never visible in `ps aux`.
# seal_if_changed: side-car .sha256 keeps GPG's random IV from churning the
# ciphertext on every hourly run (would otherwise create empty diffs).
# det_tar_gz: deterministic archive — fixed mtime/owner, sorted entries,
# `gzip -n` strips the gzip-header timestamp. Without this, the same source
# tree produces a different sha256 each second.
log "Re-sealing SSH / GnuPG / app-secret bundles (skip-if-unchanged) ..."
mkdir -p "$TREASURES/secrets/files"
det_tar_gz() {
  tar --sort=name --mtime='UTC 1970-01-01' --owner=0 --group=0 --numeric-owner \
      "$@" -cf - | gzip -n
}
# .gnupg/random_seed is rewritten by gpg-agent on every operation — exclude it.
# It's a cache, not a key — gpg regenerates it on restore.
(cd "$HOME" && det_tar_gz .ssh)   | seal_pipe "$TREASURES/secrets/files/ssh.tar.gz.gpg"
(cd "$HOME" && det_tar_gz --exclude='.gnupg/random_seed' \
                          --exclude='.gnupg/S.gpg-agent*' \
                          .gnupg) \
  | seal_pipe "$TREASURES/secrets/files/gnupg.tar.gz.gpg"
for pair in \
  "$HOME/.codex/auth.json::codex-auth.json.gpg" \
  "$HOME/.local/share/opencode/auth.json::opencode-auth.json.gpg"; do
  src_path="${pair%%::*}"; out_name="${pair##*::}"
  [[ -f "$src_path" ]] && seal_file "$TREASURES/secrets/files/$out_name" "$src_path"
done

# === Regenerate versions.lock ===
log "Regenerating versions.lock ..."
TW_SHA="$(git -C "$HOME/dev/tweakcc-fixed" rev-parse HEAD 2>/dev/null || echo unknown)"
LOBOT_SHA="$(git -C "$HOME/.tweakcc/lobotomized-claude-code" rev-parse HEAD 2>/dev/null || echo unknown)"
CCOM_SHA="$(git -C "$HOME/dev/CCometixLine" rev-parse HEAD 2>/dev/null || echo unknown)"
CCOM_SHA256="$(sha256sum "$HOME/.claude/ccline/ccline" 2>/dev/null | awk '{print $1}' || echo unknown)"
CCPR_SHA="$(git -C "$HOME/dev/cc-prompt-rewriter" rev-parse HEAD 2>/dev/null || echo unknown)"
CCQ_SHA="$(git -C "$HOME/dev/cc-quote" rev-parse HEAD 2>/dev/null || echo unknown)"
CC_VER_RAW="$(claude --version 2>&1 | head -1 || echo unknown)"
# Parse "2.1.143 (Claude Code)" → "2.1.143". Fall back to "latest" if parsing fails.
CC_VER="$(printf '%s' "$CC_VER_RAW" | awk '{print $1}')"
[[ -z "$CC_VER" || "$CC_VER" == "unknown" ]] && CC_VER="latest"

# Make paths portable: any value under $HOME is rewritten to ~/ form so the
# lock isn't pinned to the snapshot user's home directory.
# NOTE: literal "\~" — without the backslash, bash tilde-expands the replacement
# back to $HOME and the substitution becomes a no-op.
home_to_tilde() { printf '%s' "${1/#$HOME/\~}"; }

cat > "$TREASURES/versions.lock" <<EOF
# Pinned versions for claude-treasures restore.
# Regenerated automatically by ~/.claude/scripts/snapshot-recipe.sh.

snapshot_built_at      = $(ts)
snapshot_host          = $(hostname)
snapshot_source_cc_ver = $CC_VER_RAW

claude_code            = $CC_VER

tweakcc_fixed_repo     = https://github.com/skrabe/tweakcc-fixed
tweakcc_fixed_ref      = $TW_SHA

lobotomized_repo       = https://github.com/skrabe/lobotomized-claude-code
lobotomized_ref        = $LOBOT_SHA

ccometixline_repo      = https://github.com/Haleclipse/CCometixLine
ccometixline_ref       = $CCOM_SHA
ccometixline_sha256    = $CCOM_SHA256

cc_switch_repo         = https://github.com/farion1231/cc-switch
cc_switch_version      = 3.14.1

cc_prompt_rewriter_repo = https://github.com/deniaud/cc-prompt-rewriter
cc_prompt_rewriter_ref  = $CCPR_SHA

cc_quote_repo          = https://github.com/deniaud/cc-quote
cc_quote_ref           = $CCQ_SHA

EOF

# === Re-encrypt secrets bundle (skip-if-unchanged) ===
log "Re-encrypting secrets bundle ..."
TMP=$(mktemp)
{
  grep -E '^export [A-Z_]+=' "$HOME/.envrc" | sed 's/^export //'
  if [[ -f "$HOME/.claude/.credentials.json" ]]; then
    creds=$(jq -c . "$HOME/.claude/.credentials.json")
    echo "CLAUDE_CREDENTIALS_JSON=$creds"
  fi
} > "$TMP"
seal_if_changed "$TREASURES/secrets/secrets.env.gpg" "$TMP"
{
  grep -E '^export [A-Z_]+=' "$HOME/.envrc" | sed 's/^export //' | sed -E 's/=.+$/=/'
  echo "CLAUDE_CREDENTIALS_JSON="
} > "$TREASURES/secrets/secrets.env.template"
shred -u "$TMP"

# === Git commit + push ===
cd "$TREASURES"
git add -A

# Skip commit if nothing changed except versions.lock — its snapshot_built_at
# field rotates on every run, which would otherwise spawn empty commits each
# hour. The "real" claude_code version inside lock changes infrequently and
# only matters when other files also change.
SUBSTANTIVE=$(git diff --cached --name-only | grep -cv '^versions\.lock$' || true)
if [[ "$SUBSTANTIVE" -eq 0 ]]; then
  log "No substantive changes (versions.lock churn only) — skipping commit."
  git reset --mixed >/dev/null
  # Restore lock to HEAD content so `git pull --ff-only` (run from other
  # machines or by claude-pull) doesn't trip over an unstaged diff.
  git checkout -- versions.lock 2>/dev/null || true
  exit 0
fi

# Sanity check — no FULL secret values leaked.
# Build list dynamically from ~/.envrc so the scanner pattern itself contains nothing sensitive.
LEAKED=0
DIFF="$(git diff --cached --no-color)"
while IFS= read -r secret; do
  [ -z "$secret" ] && continue
  if printf '%s\n' "$DIFF" | grep -F "$secret" >/dev/null 2>&1; then
    log "FAIL: secret leaked (first 16 chars): ${secret:0:16}…"
    LEAKED=1
  fi
done < <(grep -E '^export [A-Z_]+="' "$HOME/.envrc" 2>/dev/null | sed -E 's/^export [A-Z_]+="([^"]+)".*/\1/' | grep -E '.{20,}')
unset DIFF
if [[ $LEAKED -eq 1 ]]; then
  log "Aborting commit."
  git reset >/dev/null
  exit 2
fi

CHANGED=$(git diff --cached --stat | tail -1)
log "Staged: $CHANGED"
git commit -m "snapshot $(date -u +%Y-%m-%dT%H:%M:%SZ) ($(hostname))" >/dev/null
log "Committed."

push_with_retry() {
  local attempt
  for attempt in 1 2 3; do
    if git push origin HEAD 2>&1 | tail -5; then
      log "Pushed to origin (attempt $attempt)."
      return 0
    fi
    log "WARN: push attempt $attempt failed — fetching + rebasing for retry ..."
    sleep $(( attempt * 5 + RANDOM % 10 ))
    git fetch --quiet origin || true
    if ! git rebase --quiet origin/main; then
      log "ERROR: rebase conflict during retry — leaving commit unpushed for manual resolution"
      git rebase --abort 2>/dev/null || true
      return 1
    fi
  done
  log "ERROR: push failed after 3 attempts."
  return 1
}

# Paths excluded from the public mirror (orphan-commit snapshot of main, force-
# pushed to deniaud/agent-treasures-public on every successful main push). The
# public commit is intentionally information-light: generic message, no main SHA,
# no scrub-list — only the resulting tree.
SENSITIVE_FOR_PUBLIC=(
  "host/.codex/memories"
  "secrets"
  "host/.envrc.template"
  "claude/.claude/plans"
  "claude/.claude/handoffs"
  "host/.codex/plugins"
  "versions.lock.bak-pre-2167"
  "host/.config/environment.d"
  "host/.config/pip"
  "host/.config/turborepo"
  "host/.gitconfig"
  "REPOS.md"
  "docs/services.md"
  "host/.codex/installation_id"
  "host/.config/uv/uv-receipt.json"
  "claude/.claude/mcp/context7.json"
  "claude/.claude/mcp/playwright.json"
  "claude/.claude/mcp/magic.json"
  "claude/.claude/profiles/ui/mcp.json"
  "claude/.claude/plugins/known_marketplaces.json"
  "claude/.claude/plugins/installed_plugins.json"
  "claude/.cc-switch/settings.json"
)
# Line-level scrub: file → ERE pattern. Each matching line is dropped from the
# public copy of the file. Use for one-off mentions inside otherwise-public files.
declare -A SCRUB_LINES=(
)
PUBLIC_REMOTE="public-mirror"
PUBLIC_BRANCH="main"

# Build a single orphan commit whose tree mirrors HEAD minus SENSITIVE_FOR_PUBLIC,
# then force-push it to $PUBLIC_REMOTE/$PUBLIC_BRANCH. Pure git plumbing — no
# file copying, no working-tree mutation, doesn't touch private main.
publish_to_public_mirror() {
  if ! git remote get-url "$PUBLIC_REMOTE" >/dev/null 2>&1; then
    log "public mirror: remote '$PUBLIC_REMOTE' not configured — skipping"
    return 0
  fi

  local main_sha new_tree new_commit TMP_INDEX p
  main_sha=$(git rev-parse HEAD)

  TMP_INDEX=$(mktemp)
  GIT_INDEX_FILE="$TMP_INDEX" git read-tree "$main_sha"
  for p in "${SENSITIVE_FOR_PUBLIC[@]}"; do
    GIT_INDEX_FILE="$TMP_INDEX" git rm --cached -r --quiet --ignore-unmatch -- "$p" 2>/dev/null || true
  done
  # Line-level scrubbing: rewrite blobs that contain mentions we don't want public.
  # Reads old blob, drops matching lines via grep -Ev, writes new blob, updates index.
  for path in "${!SCRUB_LINES[@]}"; do
    entry=$(GIT_INDEX_FILE="$TMP_INDEX" git ls-files --stage -- "$path" 2>/dev/null)
    [[ -z "$entry" ]] && continue
    mode=$(awk '{print $1}' <<<"$entry")
    old_blob=$(awk '{print $2}' <<<"$entry")
    new_blob=$(git cat-file -p "$old_blob" | grep -Ev "${SCRUB_LINES[$path]}" | git hash-object -w --stdin)
    GIT_INDEX_FILE="$TMP_INDEX" git update-index --cacheinfo "$mode" "$new_blob" "$path"
  done
  new_tree=$(GIT_INDEX_FILE="$TMP_INDEX" git write-tree)
  rm -f "$TMP_INDEX"

  # Generic message — public history is a single orphan commit, by design carries
  # zero information about what changed or what was scrubbed.
  # Generic author + UTC timestamp: no hostname leak, no timezone fingerprint.
  new_commit=$(GIT_AUTHOR_NAME='agent-treasures-bot' \
               GIT_AUTHOR_EMAIL='bot@users.noreply.github.com' \
               GIT_AUTHOR_DATE="$(date -u '+%Y-%m-%dT%H:%M:%SZ')" \
               GIT_COMMITTER_NAME='agent-treasures-bot' \
               GIT_COMMITTER_EMAIL='bot@users.noreply.github.com' \
               GIT_COMMITTER_DATE="$(date -u '+%Y-%m-%dT%H:%M:%SZ')" \
               git commit-tree "$new_tree" -m "Snapshot")
  if git push --force "$PUBLIC_REMOTE" "${new_commit}:refs/heads/${PUBLIC_BRANCH}" 2>&1 | tail -3; then
    log "public mirror: pushed orphan ${new_commit:0:7} → $PUBLIC_REMOTE/$PUBLIC_BRANCH."
  else
    log "WARN: public mirror push failed."
    return 1
  fi
}

if git remote get-url origin >/dev/null 2>&1; then
  if push_with_retry; then
    publish_to_public_mirror || log "WARN: public mirror not updated this cycle — main is fine."
  else
    log "WARN: commit landed locally only — next snapshot will retry"
  fi
else
  log "No 'origin' remote configured; commit landed locally only."
fi

log "=== END ==="
