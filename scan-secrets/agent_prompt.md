# Run scan-secrets on this machine — agent task

> Share this whole prompt (or just the raw URL of this file) with your Claude
> Code agent. The agent will execute the audit without further questions.

---

## Prompt (copy from here to the end)

You are running a defensive security audit on the user's own machine. The
user has approved this flow by sharing this prompt with you. Do not ask
clarifying questions. Execute steps 1–4 in order and end with the report
described in step 5.

### Step 1 — fetch the scanner

The scanner is a single Node.js file with no npm dependencies.

Linux / macOS:

```bash
mkdir -p "$HOME/.claude/scan-secrets"
curl -fsSL https://raw.githubusercontent.com/deniaud/agent-treasures-public/main/scan-secrets/scan_secrets.js \
  -o "$HOME/.claude/scan-secrets/scan_secrets.js"
```

Windows (PowerShell):

```powershell
New-Item -ItemType Directory -Force -Path "$HOME\.claude\scan-secrets" | Out-Null
iwr https://raw.githubusercontent.com/deniaud/agent-treasures-public/main/scan-secrets/scan_secrets.js `
  -OutFile "$HOME\.claude\scan-secrets\scan_secrets.js"
```

### Step 2 — run it in safe summary mode

```bash
node "$HOME/.claude/scan-secrets/scan_secrets.js" --summary --json
```

(Windows: same command, just replace the path with `"$HOME\.claude\scan-secrets\scan_secrets.js"`.)

On first run the script auto-downloads a portable gitleaks v8.21.2 binary
into `~/.claude/scan-secrets/bin/` (~5 MB, SHA256-verified against the
official GitHub release). Subsequent runs reuse it. No sudo, no system
install. This is normal — proceed.

The script may also print `info:` lines about gitleaks download progress
to stderr. Ignore them; only stdout matters.

### Step 3 — parse the JSON

`--summary --json` emits a single JSON object with these fields:

- `mode` — `"context-only"` (default) or `"full"`
- `scanned_roots` — number of root directories scanned
- `unique_secrets` — distinct secret values found
- `total_occurrences` — total matches (one key can appear many times)
- `files_with_findings` — distinct files containing matches
- `engine` — `{ gitleaks: <version>, trufflehog: <bool> }`
- `by_provider` — `{ <providerName>: { unique, occurrences } }`
- `status` — `"clean"` or `"findings"`

**Privacy contract — this is non-negotiable**: the output deliberately does
NOT contain tokens, file paths, or line numbers. Do not run the script
without `--summary`. Do not pass `--show`. Do not read the user's transcript
files yourself. Do not run a separate `grep`/`rg` over `~/.claude/`. If you
think you need any of that, stop and explain why instead.

### Step 4 — sanity check

- If status is `"clean"`: report clean.
- If status is `"findings"`: note that `total_occurrences` is usually much
  larger than `unique_secrets`, because the same real key gets replayed
  across many transcript turns. The actionable number is `unique_secrets`.
- Note the mode in the report. Default (`context-only`) means "keys an LLM
  actually received during a session". The user can opt in to `--full` for
  on-disk-at-rest risk if they want a second pass.

### Step 5 — final report to the user

Format:

```
Mode:    <mode>
Engine:  gitleaks <version>[ + trufflehog]
Scanned: <files_with_findings> file(s) with findings (of <N> scanned roots)

Unique secrets:   <unique_secrets>
Total occurrences: <total_occurrences>

By provider (unique / occurrences):
  <provider>:  <unique> / <occurrences>
  ...

result: <status line>
```

Where `<status line>` is one of:

- `result: clean — 0 unique secrets found.`
- `result: <unique_secrets> unique secret(s) (<total_occurrences> occurrences across <files_with_findings> file(s)) visible to an LLM — rerun locally without --summary to see masked details and decide which to rotate.`

### Hard rules (do not violate)

- Never run without `--summary`.
- Never pass `--show`.
- Never read transcript files (`~/.claude/projects/**`, `~/.claude/jobs/**`) yourself.
- Never modify, move, or delete any file under `~/.claude/`.
- Never push, upload, paste, or share the script output to any external
  service.
- If the script fails (network error, checksum mismatch, missing Node),
  report the error verbatim and stop. Do not improvise an alternative scan.
