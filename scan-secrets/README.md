# scan-secrets

Audit Claude Code session transcripts for leaked API keys, locally.

The wrapper is Node.js. The detection engine is [gitleaks](https://github.com/gitleaks/gitleaks)
(community-maintained, ~80 providers, entropy checks). On first run the script
downloads a portable, version-pinned gitleaks binary into
`~/.claude/scan-secrets/bin/` (no sudo, ~5 MB, SHA256-verified against the
GitHub release).

Cross-platform: Ubuntu / macOS / Windows. The only requirement is Node.js,
which Claude Code itself depends on — so if you have CC, you have Node.

## Quick start

Linux / macOS:

```bash
curl -fsSL https://raw.githubusercontent.com/deniaud/agent-treasures-public/main/scan-secrets/scan_secrets.js -o /tmp/scan_secrets.js
node /tmp/scan_secrets.js --summary
```

Windows (PowerShell):

```powershell
iwr https://raw.githubusercontent.com/deniaud/agent-treasures-public/main/scan-secrets/scan_secrets.js -OutFile $env:TEMP\scan_secrets.js
node $env:TEMP\scan_secrets.js --summary
```

## Modes

| Mode | Question it answers |
|---|---|
| default (context-only) | Which keys did an LLM actually receive during a session? Filters JSONL records by `type` ∈ {`user`, `assistant`, `system`, `attachment`}. |
| `--full` | Which keys are sitting on disk in plaintext, including file-history-snapshots and harness metadata an agent never saw? |

## Output modes

| Flag | Behaviour |
|---|---|
| (default) | Per-conversation breakdown at top + per-unique-secret listing with masked values (`first6...last4`). |
| `--summary` | Aggregate counts only. No tokens, no paths, no lines. **Safe for sharing and safe for an auditing agent to run.** |
| `--json` | Machine-readable. Combines with `--summary`. |
| `--show` | Include raw key values in detail output. **LOCAL USE ONLY.** Suppressed under `--summary`. |
| `--with-trufflehog` | Also runs `trufflehog` if installed (must be on PATH). |
| `--no-install` | Refuse to auto-download gitleaks; require it on PATH. |

## What gets reported

- **Per-conversation block (context-only, detailed)**: each affected session
  listed by decoded project path + `ai-title` + unique-secret count, sorted
  by leak count.
- **Per-unique-secret block**: one entry per distinct key with masked value,
  occurrence count, files + line numbers. One real key replayed across N
  transcript turns shows as one secret, not N.
- **`--summary`**: just mode, totals, and per-provider counts (unique /
  occurrences).

## Privacy contract

- The script masks tokens before any user-visible output.
- `--summary` never emits tokens, paths, or line numbers — even to JSON.
- The detection engine (gitleaks) runs entirely locally. No data leaves the
  machine; no telemetry.

## Asking an agent to run this for you

See [`agent_prompt.md`](./agent_prompt.md) for a copy-paste prompt that tells
a Claude Code (or any LLM-coding) agent to fetch and run the script with strict
no-leak constraints. The agent only ever sees aggregate counts.

## Exit codes

- `0` — no findings
- `1` — at least one finding
- `2` — error (network, checksum mismatch, missing tool)
