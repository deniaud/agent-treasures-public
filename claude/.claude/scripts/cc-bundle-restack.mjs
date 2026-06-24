#!/usr/bin/env node
// cc-bundle-restack — apply cc-quote + cc-prompt-rewriter bundle patches to
// Claude Code's native binary in a SINGLE repack.
//
// Why: tweakcc's native repack (node-lief) appends a fresh ~150 MB .bun section
// on every writeContent and never reclaims the old one, so stacking patchers
// compounds the file size. Three separate repacks (tweakcc → rewriter → quote)
// climb pristine 234 MB → 409 MB → 677 MB → (the 3rd trips the fork's
// vaddr-gap bloat guard and is refused). This is exactly the problem the
// `cc-stack` project is designed to solve (one pristine + re-derive in one
// repack). This script is the minimal embodiment of that idea for the two
// deniaud patchers: read the (tweakcc-patched) bundle ONCE, apply BOTH tools'
// pure patch sets in deterministic order, and writeContent ONCE.
//
// Order matters: cc-quote (citations, order 10) before cc-prompt-rewriter
// (rewrite mode, order 20) — mirrors cc-stack's recorded patchset order.
//
// Idempotency: in the normal pipeline this runs right after tweakcc, on a
// FRESH (post-`claude update`) binary, so the anchors match an unpatched
// bundle. If the bundle already carries our markers, the per-tool anchors
// would not match the unpatched shape — we detect that and exit 0 (no-op)
// rather than corrupting the binary.
//
// Paths are the pipeline's local clones; override via env if needed.

const HOME = process.env.HOME || '';
const FORK = process.env.TWEAKCC_FORK || `${HOME}/dev/tweakcc-fixed`;
const REWRITER = process.env.CC_REWRITER_DIR || `${HOME}/dev/cc-prompt-rewriter`;
const QUOTE = process.env.CC_QUOTE_DIR || `${HOME}/dev/cc-quote`;

const { tryDetectInstallation, readContent, writeContent, backupFile } =
  await import(`${FORK}/dist/lib/index.mjs`);
const { REWRITE_PATCHES } = await import(`${REWRITER}/dist/index.mjs`);
const { CITATION_PATCHES } = await import(`${QUOTE}/dist/index.mjs`);

// Markers that prove our patches are already present (skip double-apply).
const REWRITE_MARKER = '"~ for rewrite mode"';
const QUOTE_MARKER = 'globalThis.__cc_citations__';

async function main() {
  const inst = await tryDetectInstallation({ interactive: false });
  console.log(`Installation: ${inst.path}`);
  console.log(`Version:      ${inst.version} (${inst.kind})`);

  const { content, clearBytecode } = await readContent(inst);

  if (content.includes(REWRITE_MARKER) || content.includes(QUOTE_MARKER)) {
    console.log(
      'cc-bundle-restack: bundle already carries citation/rewrite markers — ' +
        'nothing to do (run from a fresh/pristine bundle to re-stack).'
    );
    return;
  }

  // Single backup of the pre-restack bundle (whatever tweakcc left).
  const backupPath = `${HOME}/.cc-bundle-restack/backup-${inst.version}.bin`;
  await backupFile(inst.path, backupPath);
  console.log(`Backed up pre-restack bundle to ${backupPath}`);

  // cc-stack order: citations (10) then rewrite mode (20).
  const stages = [
    ['cc-quote', CITATION_PATCHES],
    ['cc-prompt-rewriter', REWRITE_PATCHES],
  ];

  let out = content;
  for (const [tool, patches] of stages) {
    for (const { name, fn } of patches) {
      const next = fn(out);
      if (!next) {
        console.error(`  ✗ ${tool}:${name} — anchor miss; aborting (no write)`);
        process.exit(1);
      }
      out = next;
      console.log(`  ✓ ${tool}:${name}`);
    }
  }

  console.log('Writing patched bundle (single repack) …');
  await writeContent(inst, out, clearBytecode);
  console.log('Done — citations + rewrite mode applied in one repack.');
}

main().catch((err) => {
  console.error(
    `cc-bundle-restack error: ${err instanceof Error ? err.message : String(err)}`
  );
  process.exit(1);
});
