#!/usr/bin/env bash
# Clone cc-prompt-rewriter @ pin and run its install.sh.
# Installs: ~/.claude/hooks/enhance-prompt.{sh,system.md} (idempotent — also
# placed by step 80 from claude/), settings.json UserPromptSubmit hook entry,
# and tweakcc-fixed/src/patches/rewriteMode.ts.
#
# Requires step 30 (tweakcc-fixed clone) to have run already.
# REGISTRATION.md describes 3 manual edits to tweakcc-fixed/src/patches/index.ts
# — we detect whether they're present and warn if not, then rebuild tweakcc-fixed
# so the rewrite-mode patch lands in dist/index.mjs before step 97 applies it.
set -euo pipefail

REPO="${TREASURE_cc_prompt_rewriter_repo:-https://github.com/deniaud/cc-prompt-rewriter}"
REF="${TREASURE_cc_prompt_rewriter_ref:-main}"
TARGET="$HOME/dev/cc-prompt-rewriter"
TWEAKCC_DIR="$HOME/dev/tweakcc-fixed"
TWEAKCC_INDEX="$TWEAKCC_DIR/src/patches/index.ts"

[[ ${DRY_RUN:-0} -eq 1 ]] && {
  echo "[dry] clone $REPO @ $REF -> $TARGET && bash $TARGET/install.sh && rebuild tweakcc-fixed"
  exit 0
}

mkdir -p "$(dirname "$TARGET")"
if [[ -d "$TARGET/.git" ]]; then
  git -C "$TARGET" fetch --all --tags
else
  git clone "$REPO" "$TARGET"
fi
git -C "$TARGET" checkout "$REF"

# Run the project's own install.sh — copies hooks/, jq-merges settings.json
# (only adds our entry if not present), and syncs rewriteMode.ts into tweakcc-fixed.
bash "$TARGET/install.sh"

# rewriteMode.ts requires 3 hand edits in tweakcc-fixed/src/patches/index.ts
# (import + PATCH_DEFINITIONS entry + patchImplementations entry). Detect them.
if [[ -f "$TWEAKCC_INDEX" ]] && grep -q "writeRewriteMode" "$TWEAKCC_INDEX" 2>/dev/null; then
  echo "  ok: rewrite-mode registered in $TWEAKCC_INDEX"
  echo "  rebuilding tweakcc-fixed so dist/index.mjs picks up the patch ..."
  ( cd "$TWEAKCC_DIR" && npm run build )
  [[ -f "$TWEAKCC_DIR/dist/index.mjs" ]] || { echo "[!] tweakcc-fixed rebuild missing dist/index.mjs"; exit 1; }
else
  echo "  ! rewrite-mode NOT registered in $TWEAKCC_INDEX"
  echo "    follow the 3 edits in $TARGET/tweakcc-patch/REGISTRATION.md, then:"
  echo "    cd $TWEAKCC_DIR && npm run build"
  echo "    (step 97 won't apply rewrite-mode until the patch is registered + rebuilt)"
fi
