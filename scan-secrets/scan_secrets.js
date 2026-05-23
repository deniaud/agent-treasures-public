#!/usr/bin/env node
/*
 * Scan Claude Code session transcripts for leaked API keys / secrets.
 *
 * Detection engine: gitleaks (community-maintained, ~80 providers, entropy
 * checks). On first run the script downloads a portable, version-pinned
 * gitleaks binary into ~/.claude/scan-secrets/bin/ (no sudo, ~5MB,
 * checksum-verified against the GitHub release). Optionally also runs
 * trufflehog if it's already on PATH.
 *
 * What this wrapper adds on top of gitleaks:
 *   • Claude Code-aware default: only counts findings inside JSONL records
 *     the LLM actually received (user/assistant/system/attachment). Pass
 *     --full to scan all on-disk content (snapshots, metadata, etc.).
 *   • Per-conversation grouping with project paths and ai-title at the top
 *     of the report.
 *   • Group by unique secret value (one real key seen N times across
 *     transcript replays = 1 leak, not N).
 *   • --summary mode safe for agent runs (no tokens, no paths, no lines).
 *
 * Cross-platform: requires Node.js only (which Claude Code itself depends on
 * — so anyone running CC already has it). Identical on Ubuntu/macOS/Windows.
 *
 * Usage:
 *   node scan_secrets.js                       # context-only (what an LLM saw)
 *   node scan_secrets.js --full                # on-disk risk (everything)
 *   node scan_secrets.js --summary             # safe-for-agent aggregate
 *   node scan_secrets.js --with-trufflehog     # add trufflehog if installed
 *   node scan_secrets.js --show                # full values in detail output
 *   node scan_secrets.js --no-install          # refuse to auto-download
 *   node scan_secrets.js --help                # all flags
 *
 * Exit codes: 0 = clean, 1 = findings, 2 = error.
 */

'use strict';

const fs = require('fs');
const path = require('path');
const os = require('os');
const crypto = require('crypto');
const { spawnSync } = require('child_process');

// === Gitleaks pinning ===
const GITLEAKS_VERSION = '8.21.2';
const GITLEAKS_CHECKSUMS = {
  linux_x64:    '5bc41815076e6ed6ef8fbecc9d9b75bcae31f39029ceb55da08086315316e3ba',
  linux_arm64:  '654c935542c89f565aabe7bf7c6c500830f116c114f0aeb509d2460c1ac2e6da',
  darwin_x64:   '5b42c6e4b1fd693eaeb2b5b7faa5f17a1434299d4deb2de63d4b2efd7c753128',
  darwin_arm64: 'cad3de5dc9a4d5447d967a70a4d49499c557f04db028274cc324f9ff983f6502',
  windows_x64:  'f238c85e5f47e18fac779ce71ee11091cf70a0a8fb4415f165efba2800eef133',
};

const SCAN_HOME    = path.join(os.homedir(), '.claude', 'scan-secrets');
const BIN_DIR      = path.join(SCAN_HOME, 'bin');
const CONFIG_PATH  = path.join(SCAN_HOME, 'gitleaks.toml');

// JSONL record types whose content was actually sent to an LLM during the
// session. Other types are harness metadata or local-only snapshots the
// model never received.
const CONTEXT_RECORD_TYPES = new Set(['user', 'assistant', 'system', 'attachment']);

// Documentation placeholders to ignore even if a rule matches them.
const PLACEHOLDERS = new Set([
  'sk-ant-api03-xxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxx-xxxxxxAA',
]);

// === Helpers ===

function mask(secret) {
  if (!secret) return '(no value)';
  if (secret.length <= 12) return secret.slice(0, 4) + '***';
  return `${secret.slice(0, 6)}...${secret.slice(-4)} (len=${secret.length})`;
}

function normPath(p) {
  return p.split(path.sep).join('/');
}

// Lossy decoder for ~/.claude/projects/-foo-bar-baz/ → /foo/bar/baz
function decodeProjectFolder(name) {
  if (!name || !name.startsWith('-')) return name || '';
  return '/' + name.slice(1).replace(/-/g, '/');
}

function extractSessionTitle(jsonlPath) {
  if (!jsonlPath || !jsonlPath.endsWith('.jsonl')) return null;
  let text;
  try { text = fs.readFileSync(jsonlPath, 'utf8'); } catch { return null; }
  const lines = text.split(/\r?\n/);
  const cap = Math.min(lines.length, 2000);
  for (let i = 0; i < cap; i++) {
    const line = lines[i];
    if (!line || line.indexOf('ai-title') === -1) continue;
    try {
      const rec = JSON.parse(line);
      if (rec && rec.type === 'ai-title') return rec.aiTitle || rec.title || null;
    } catch { /* skip */ }
  }
  return null;
}

function projectAndSession(filePath) {
  const norm = normPath(filePath);
  const m = norm.match(/\/projects\/([^/]+)\/([^/]+?)(?:\.jsonl(?:$|\/)|\/)/);
  if (!m) return { projectFolder: null, sessionId: null };
  const sid = m[2].endsWith('.jsonl') ? m[2].slice(0, -6) : m[2];
  return { projectFolder: m[1], sessionId: sid };
}

function sha256OfFile(p) {
  const hash = crypto.createHash('sha256');
  hash.update(fs.readFileSync(p));
  return hash.digest('hex');
}

function defaultRoots() {
  const home = os.homedir();
  return [
    path.join(home, '.claude', 'projects'),
    path.join(home, '.claude', 'jobs'),
  ];
}

// === Platform detection & gitleaks install ===

function getPlatformKey() {
  const platMap = { linux: 'linux', darwin: 'darwin', win32: 'windows' };
  const archMap = { x64: 'x64', arm64: 'arm64' };
  const p = platMap[process.platform];
  const a = archMap[process.arch];
  if (!p || !a) return null;
  return `${p}_${a}`;
}

function binaryAvailable(bin) {
  const res = spawnSync(bin, ['version'], { stdio: 'ignore' });
  return !(res.error && res.error.code === 'ENOENT');
}

function ensureGitleaks(args) {
  // Prefer a system-installed gitleaks if present and recent enough.
  if (binaryAvailable('gitleaks')) {
    const ver = spawnSync('gitleaks', ['version'], { encoding: 'utf8' });
    const out = (ver.stdout || '').trim();
    const m = out.match(/(\d+)\.(\d+)\.(\d+)/);
    if (m && +m[1] >= 8) return 'gitleaks';
    process.stderr.write(`warn: system gitleaks is too old (${out}); using cached portable.\n`);
  }
  const binName = process.platform === 'win32' ? 'gitleaks.exe' : 'gitleaks';
  const cached = path.join(BIN_DIR, binName);
  if (fs.existsSync(cached)) return cached;
  if (args.noInstall) {
    throw new Error(
      'gitleaks is not installed and --no-install was passed.\n' +
      'Install manually: https://github.com/gitleaks/gitleaks/releases\n' +
      `Or place the binary at ${cached}`);
  }
  downloadAndExtractGitleaks();
  return cached;
}

function httpDownload(url, dest) {
  // Try curl, then wget, then PowerShell. One of these is on every modern OS.
  let res = spawnSync('curl', ['-fsSL', '-o', dest, url], { stdio: ['ignore', 'inherit', 'inherit'] });
  if (!res.error && res.status === 0) return;
  res = spawnSync('wget', ['-q', '-O', dest, url], { stdio: ['ignore', 'inherit', 'inherit'] });
  if (!res.error && res.status === 0) return;
  if (process.platform === 'win32') {
    res = spawnSync('powershell', ['-NoProfile', '-Command',
      `Invoke-WebRequest -Uri '${url}' -OutFile '${dest}' -UseBasicParsing`],
      { stdio: ['ignore', 'inherit', 'inherit'] });
    if (!res.error && res.status === 0) return;
  }
  throw new Error('No HTTP downloader found. Install curl or wget (or run on Windows with PowerShell).');
}

function extractArchive(archivePath, destDir) {
  // tar is on macOS, Linux, and Windows 10+. Use it for both tar.gz and zip.
  const args = archivePath.endsWith('.zip')
    ? ['-xf', archivePath, '-C', destDir]
    : ['-xzf', archivePath, '-C', destDir];
  let res = spawnSync('tar', args, { stdio: ['ignore', 'inherit', 'inherit'] });
  if (!res.error && res.status === 0) return;
  // Windows fallback: PowerShell Expand-Archive for .zip
  if (process.platform === 'win32' && archivePath.endsWith('.zip')) {
    res = spawnSync('powershell', ['-NoProfile', '-Command',
      `Expand-Archive -Path '${archivePath}' -DestinationPath '${destDir}' -Force`],
      { stdio: ['ignore', 'inherit', 'inherit'] });
    if (!res.error && res.status === 0) return;
  }
  throw new Error(`Failed to extract ${archivePath}`);
}

function downloadAndExtractGitleaks() {
  const platformKey = getPlatformKey();
  if (!platformKey || !GITLEAKS_CHECKSUMS[platformKey]) {
    throw new Error(
      `Unsupported platform: ${process.platform}/${process.arch}. ` +
      `Install gitleaks manually: https://github.com/gitleaks/gitleaks/releases`);
  }
  fs.mkdirSync(BIN_DIR, { recursive: true });
  const isWin = process.platform === 'win32';
  const ext = isWin ? 'zip' : 'tar.gz';
  const archiveName = `gitleaks_${GITLEAKS_VERSION}_${platformKey}.${ext}`;
  const url = `https://github.com/gitleaks/gitleaks/releases/download/v${GITLEAKS_VERSION}/${archiveName}`;
  const archivePath = path.join(BIN_DIR, archiveName);

  process.stderr.write(
    `info: gitleaks not found — downloading portable v${GITLEAKS_VERSION} (one-time, ~5MB)\n` +
    `      from ${url}\n` +
    `      to   ${BIN_DIR}\n`);
  httpDownload(url, archivePath);

  const expected = GITLEAKS_CHECKSUMS[platformKey];
  const actual = sha256OfFile(archivePath);
  if (actual !== expected) {
    try { fs.unlinkSync(archivePath); } catch {}
    throw new Error(`SHA256 mismatch for ${archiveName}:\n  expected ${expected}\n  got      ${actual}`);
  }
  process.stderr.write(`      sha256 ok (${expected.slice(0, 16)}…)\n`);

  extractArchive(archivePath, BIN_DIR);
  try { fs.unlinkSync(archivePath); } catch {}

  if (!isWin) {
    const binPath = path.join(BIN_DIR, 'gitleaks');
    try { fs.chmodSync(binPath, 0o755); } catch {}
  }
  process.stderr.write('      ready.\n\n');
}

// === Custom gitleaks config (adds internal `ol_` rule on top of defaults) ===

function ensureGitleaksConfig() {
  fs.mkdirSync(SCAN_HOME, { recursive: true });
  if (fs.existsSync(CONFIG_PATH)) return CONFIG_PATH;
  // TOML literal strings (triple single-quoted) take regex verbatim — no
  // backslash escaping. useDefault=true keeps all ~80 built-in gitleaks rules.
  const toml = `# Auto-generated by scan_secrets.js. Safe to edit; will not be overwritten.
title = "scan_secrets.js — Claude Code transcript audit"

[extend]
useDefault = true

[[rules]]
id = "ol-internal"
description = "Internal ol_ token (organisation-specific prefix)"
regex = '''\\bol_[A-Za-z0-9_\\-]{16,}\\b'''
tags = ["api-key", "internal"]
`;
  fs.writeFileSync(CONFIG_PATH, toml);
  return CONFIG_PATH;
}

// === Scan runners ===

function runGitleaks(binPath, roots) {
  const configPath = ensureGitleaksConfig();
  const findings = [];
  for (const root of roots) {
    if (!fs.existsSync(root)) continue;
    const tmpReport = path.join(os.tmpdir(),
      `gl-${process.pid}-${Date.now()}-${Math.random().toString(36).slice(2, 8)}.json`);
    const res = spawnSync(binPath, [
      'detect',
      '--source', root,
      '--no-git',
      '--config', configPath,
      '--report-format', 'json',
      '--report-path', tmpReport,
      '--exit-code', '0',
      '--no-banner',
    ], { encoding: 'utf8', maxBuffer: 128 * 1024 * 1024 });
    if (res.error) {
      process.stderr.write(`warn: gitleaks failed on ${root}: ${res.error.message}\n`);
      try { fs.unlinkSync(tmpReport); } catch {}
      continue;
    }
    if (fs.existsSync(tmpReport)) {
      try {
        const data = fs.readFileSync(tmpReport, 'utf8');
        if (data.trim()) {
          const arr = JSON.parse(data);
          for (const r of arr) {
            findings.push({
              provider: r.RuleID || 'unknown',
              path: r.File || 'unknown',
              line: r.StartLine || 0,
              token: r.Secret || r.Match || '',
            });
          }
        }
      } catch (e) {
        process.stderr.write(`warn: failed to parse gitleaks report: ${e.message}\n`);
      }
      try { fs.unlinkSync(tmpReport); } catch {}
    }
  }
  return findings;
}

function runTrufflehog(roots) {
  if (!binaryAvailable('trufflehog')) {
    process.stderr.write(
      'info: --with-trufflehog requested but trufflehog is not on PATH.\n' +
      '  install hints:\n' +
      '    macOS:   brew install trufflehog\n' +
      '    Linux:   curl -sSfL https://raw.githubusercontent.com/trufflesecurity/trufflehog/main/scripts/install.sh | sudo sh -s -- -b /usr/local/bin\n' +
      '    Windows: https://github.com/trufflesecurity/trufflehog/releases\n');
    return [];
  }
  const findings = [];
  for (const root of roots) {
    if (!fs.existsSync(root)) continue;
    const res = spawnSync('trufflehog',
      ['filesystem', root, '--json', '--no-update'],
      { encoding: 'utf8', maxBuffer: 256 * 1024 * 1024 });
    if (res.error) {
      process.stderr.write(`warn: trufflehog failed on ${root}: ${res.error.message}\n`);
      continue;
    }
    for (const line of (res.stdout || '').split('\n')) {
      const s = line.trim();
      if (!s) continue;
      let r;
      try { r = JSON.parse(s); } catch { continue; }
      const fsMeta = r.SourceMetadata && r.SourceMetadata.Data && r.SourceMetadata.Data.Filesystem;
      findings.push({
        provider: `trufflehog:${r.DetectorName || 'unknown'}${r.Verified ? ' (verified)' : ''}`,
        path: (fsMeta && fsMeta.file) || 'unknown',
        line: (fsMeta && fsMeta.line) || 0,
        token: r.Raw || '',
      });
    }
  }
  return findings;
}

// === Context-only post-filter ===

// Drop findings that live inside a JSONL record whose `type` isn't on the
// LLM-visible whitelist. Non-JSONL files (tool-results/*.txt) and any
// finding without a usable file/line are kept.
function filterByContext(findings) {
  const byFile = new Map();
  for (const f of findings) {
    if (!byFile.has(f.path)) byFile.set(f.path, []);
    byFile.get(f.path).push(f);
  }
  const kept = [];
  for (const [file, group] of byFile) {
    if (!file.endsWith('.jsonl')) {
      kept.push(...group);
      continue;
    }
    let lines;
    try { lines = fs.readFileSync(file, 'utf8').split(/\r?\n/); }
    catch { continue; }
    for (const f of group) {
      if (!f.line || f.line < 1 || f.line > lines.length) continue;
      const line = lines[f.line - 1];
      if (!line) continue;
      try {
        const rec = JSON.parse(line);
        if (rec && rec.type && CONTEXT_RECORD_TYPES.has(rec.type)) kept.push(f);
      } catch { /* not JSON; skip in context-only mode */ }
    }
  }
  return kept;
}

// === CLI ===

function parseArgs(argv) {
  const args = {
    paths: [], show: false, json: false, summary: false,
    trufflehog: false, full: false, noInstall: false,
  };
  for (let i = 0; i < argv.length; i++) {
    const a = argv[i];
    if (a === '--path')             args.paths.push(argv[++i]);
    else if (a === '--show')        args.show = true;
    else if (a === '--json')        args.json = true;
    else if (a === '--summary')     args.summary = true;
    else if (a === '--with-trufflehog') args.trufflehog = true;
    else if (a === '--full')        args.full = true;
    else if (a === '--no-install')  args.noInstall = true;
    else if (a === '-h' || a === '--help') {
      process.stdout.write(
`Usage: node scan_secrets.js [options]

  Default mode is "context-only": only counts secrets inside transcript
  records the LLM actually received (user / assistant / system / attachment).
  Pass --full to also include on-disk content the LLM never received
  (file-history-snapshots, harness metadata, etc.).

  Detection engine is gitleaks v${GITLEAKS_VERSION} — auto-downloaded into
  ${BIN_DIR}
  on first run (checksum-verified, no sudo). Pass --no-install to refuse
  the download and require gitleaks to be on PATH.

  --path <dir>          Additional file or directory to scan (repeatable).
  --full                Scan everything on disk, not just LLM-visible records.
  --summary             Aggregate counts only. Safe for agent runs.
                        No tokens, no file paths, no line numbers. Forces --show off.
  --json                Machine-readable output (works with or without --summary).
  --show                Include raw key values in detailed output. LOCAL USE ONLY.
  --with-trufflehog     Also run local 'trufflehog' (must be installed).
  --no-install          Don't auto-download gitleaks; require it on PATH.
  -h, --help            This message.
`);
      process.exit(0);
    } else {
      process.stderr.write(`unknown arg: ${a}\n`);
      process.exit(2);
    }
  }
  if (args.summary) args.show = false;
  return args;
}

// === Main ===

function main() {
  const args = parseArgs(process.argv.slice(2));
  const roots = defaultRoots().concat(args.paths);

  const binPath = ensureGitleaks(args);

  let findings = runGitleaks(binPath, roots);
  if (args.trufflehog) findings = findings.concat(runTrufflehog(roots));

  // Drop documentation placeholders.
  findings = findings.filter(f => !PLACEHOLDERS.has(f.token));

  // Context-only post-filter (default). --full disables it.
  if (!args.full) findings = filterByContext(findings);

  // Dedup by (path, line, token) — gitleaks may yield duplicates if multiple
  // rules match the same character range.
  const seen = new Set();
  findings = findings.filter(f => {
    const k = `${f.path}\x00${f.line}\x00${f.token}`;
    if (seen.has(k)) return false;
    seen.add(k);
    return true;
  });

  // Group by unique token. One real key replayed across N transcript turns
  // = one secret, not N.
  const byTokenKey = new Map();
  const filesWithFindings = new Set();
  for (const f of findings) {
    filesWithFindings.add(f.path);
    const k = `${f.provider}\x00${f.token}`;
    let grp = byTokenKey.get(k);
    if (!grp) {
      grp = {
        provider: f.provider,
        masked: mask(f.token),
        ...(args.show ? { raw: f.token } : {}),
        token: f.token,
        files: new Map(),
        occurrences: 0,
      };
      byTokenKey.set(k, grp);
    }
    if (!grp.files.has(f.path)) grp.files.set(f.path, []);
    grp.files.get(f.path).push(f.line);
    grp.occurrences += 1;
  }

  const uniqueByProvider = {};
  const occByProvider = {};
  for (const grp of byTokenKey.values()) {
    uniqueByProvider[grp.provider] = (uniqueByProvider[grp.provider] || 0) + 1;
    occByProvider[grp.provider] = (occByProvider[grp.provider] || 0) + grp.occurrences;
  }
  const sortedProviders = Object.entries(uniqueByProvider)
    .sort((a, b) => b[1] - a[1] || (occByProvider[b[0]] - occByProvider[a[0]]))
    .map(([p, n]) => [p, n, occByProvider[p]]);

  const modeLabel = args.full ? 'full (on-disk)' : 'context-only (seen by an LLM)';

  // --- Output ---
  if (args.summary) {
    const summary = {
      mode: args.full ? 'full' : 'context-only',
      scanned_roots: roots.length,
      unique_secrets: byTokenKey.size,
      total_occurrences: findings.length,
      files_with_findings: filesWithFindings.size,
      engine: {
        gitleaks: GITLEAKS_VERSION,
        trufflehog: args.trufflehog,
      },
      by_provider: Object.fromEntries(
        sortedProviders.map(([p, uniq, occ]) => [p, { unique: uniq, occurrences: occ }])
      ),
      status: findings.length ? 'findings' : 'clean',
    };
    if (args.json) {
      process.stdout.write(JSON.stringify(summary, null, 2) + '\n');
    } else {
      console.log(`Mode:   ${modeLabel}`);
      console.log(`Engine: gitleaks v${GITLEAKS_VERSION}` + (args.trufflehog ? ' + trufflehog' : ''));
      if (!findings.length) {
        console.log('Status: clean. No matches.');
      } else {
        console.log(`Status: ${summary.unique_secrets} unique secret(s), `
                  + `${summary.total_occurrences} occurrence(s), `
                  + `${summary.files_with_findings} file(s).`);
        console.log('By provider (unique / occurrences):');
        for (const [p, uniq, occ] of sortedProviders) {
          console.log(`  ${p.padEnd(36)} ${String(uniq).padStart(3)} / ${occ}`);
        }
        if (!args.full) {
          console.log('\nThese are keys an LLM actually saw. Pass --full to also surface');
          console.log('keys sitting on disk in snapshots/metadata that no agent received.');
        }
      }
    }
  } else if (args.json) {
    const out = [];
    for (const grp of byTokenKey.values()) {
      out.push({
        provider: grp.provider,
        masked: grp.masked,
        ...(args.show ? { raw: grp.token } : {}),
        occurrences: grp.occurrences,
        files: Array.from(grp.files.entries()).map(([p, lines]) => ({ path: p, lines })),
      });
    }
    process.stdout.write(JSON.stringify(out, null, 2) + '\n');
  } else {
    console.log(`Mode:   ${modeLabel}`);
    console.log(`Engine: gitleaks v${GITLEAKS_VERSION}` + (args.trufflehog ? ' + trufflehog' : ''));
    if (!findings.length) {
      console.log(`Clean. No matches under ${roots.length} root(s).`);
    } else {
      // Conversations block (context-only only).
      if (!args.full) {
        const sessions = new Map();
        for (const f of findings) {
          const { projectFolder, sessionId } = projectAndSession(f.path);
          if (!projectFolder || !sessionId) continue;
          const k = `${projectFolder}\x00${sessionId}`;
          let s = sessions.get(k);
          if (!s) {
            s = {
              project: decodeProjectFolder(projectFolder),
              sessionId,
              uniqTokens: new Set(),
              filePath: f.path,
              title: null,
            };
            sessions.set(k, s);
          }
          s.uniqTokens.add(f.token);
        }
        for (const s of sessions.values()) {
          const norm = normPath(s.filePath);
          const m = norm.match(/^(.*\/projects\/[^/]+)\//);
          const candidate = m ? `${m[1]}/${s.sessionId}.jsonl` : null;
          s.title = (candidate && extractSessionTitle(candidate))
                 || extractSessionTitle(s.filePath);
        }
        const sorted = Array.from(sessions.values())
          .sort((a, b) => b.uniqTokens.size - a.uniqTokens.size);
        if (sorted.length) {
          console.log(`\nConversations with leaked keys (${sorted.length} session(s) across `
                    + `${new Set(sorted.map(s => s.project)).size} project(s)):`);
          for (const s of sorted) {
            const title = s.title ? `"${s.title}"` : '(untitled)';
            console.log(`  • ${s.project}`);
            console.log(`      ${title}  —  ${s.uniqTokens.size} unique secret(s)  [session ${s.sessionId.slice(0, 8)}]`);
          }
        }
      }

      console.log(`\nFound ${byTokenKey.size} unique secret(s) across ${filesWithFindings.size} file(s), `
                + `${findings.length} total occurrence(s):\n`);
      for (const grp of byTokenKey.values()) {
        const extra = args.show && grp.token ? `  raw=${grp.token}` : '';
        console.log(`  [${grp.provider}]  ${grp.masked}${extra}`);
        console.log(`    ${grp.occurrences} occurrence(s) in ${grp.files.size} file(s):`);
        for (const [p, lines] of grp.files) {
          const linesStr = lines.length > 12
            ? lines.slice(0, 12).join(', ') + `, … (+${lines.length - 12} more)`
            : lines.join(', ');
          console.log(`      ${p}`);
          console.log(`        lines: ${linesStr}`);
        }
        console.log('');
      }
      console.log('Review each unique secret above. If it\'s real:');
      console.log('  1) Rotate it at the provider immediately.');
      console.log('  2) Delete or scrub the offending session JSONL(s).');
      console.log('  3) Audit how it ended up in a prompt (pasted, env-dumped, printed by tool).');
    }
  }

  process.exit(findings.length ? 1 : 0);
}

try { main(); }
catch (err) {
  process.stderr.write(`error: ${err && err.stack || err}\n`);
  process.exit(2);
}
