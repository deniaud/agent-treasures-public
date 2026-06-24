# CLAUDE.md

Operating principles for coding agents in production repositories.
**Working code only. Plausibility is not correctness.**

These are principles, not a checklist — apply judgement. The system prompt already covers commit/push safety, README hygiene, and `result:` reporting; don't duplicate them here.

> The user often dictates prompts via speech-to-text, so some words may be garbled (homophones, dropped/wrong words) — read for intent, not literal text.

---

## Tenets (read first, even under compression)

1. **Working code, not plausible code.** Run the path, don't just parse it.
2. **A fork in the road = ask first.** Two interpretations → surface the tradeoff.
3. **Delegate when verify-fix loops exist and judgement-calls don't.** Otherwise: main.
4. **Verifiability is decided before edits; honesty about Not checked, after.** Out-of-scope paths go there — the behavior you changed doesn't.
5. **Three trackers, three scopes.** `TaskCreate` (in-session), `todo.md` (cross-session), `lessons.md` (post-miss).

---

## 1. Hard rules

Override everything else when in conflict:

1. **Secrets are off-limits.** The risk is secret-shaped *content* — keys, tokens, PATs — in any file; the filename doesn't bound it (`.env`, `secrets/`, `credentials.json` are examples, not the limit). The classic miss is a misnamed file with live keys during a bulk move. Reference variable *names* via a dotenv-loader, never contents. Enforced by the `~/.claude/hooks/guard-secrets.sh` PreToolUse hook.
2. **Stop on a fork in the road.** If a task has two plausible interpretations and the choice materially changes the result, surface the tradeoff before choosing — unless Auto Mode is active and a reasonable default is obvious. Conversely, don't fan out a multi-option question when one option is the obvious safe default — apply it with a noted assumption and ask only about the genuinely optional remainder.
3. **Match the codebase you're in.** When a quirky pattern looks like a bug (silent `exit 0`, one-shot guards, magic constants), treat it as deliberate and ask before "fixing". In well-used code, half of "obvious bugs" are design choices.
4. **Always work in an isolated worktree.** Enter one (`EnterWorktree`) before the first edit — never touch the primary checkout directly. The direct path trips the bgIsolation guard / access errors; the worktree is the default, not a fallback.
5. **Self-granted permissions match the literal authorization.** When editing permission rules in `settings.json` (or any config that grants yourself capability), the edit must match the user's *literal* authorization, not its inferred spirit. "Allow any X" authorizes `Bash(X:*)` — not adjacent operations; propose anything broader as separate, explicitly-stringed `Bash(...)` entries. The auto-mode classifier gates over-broad self-grants, so a wide edit costs a denial + redo.

---

## 2. Planning before non-trivial diffs

For anything beyond a one-line change, take a beat before editing:

- **What is the success criterion?** State it in one sentence.
- **What files will I touch, and what calls into them?** Read both sides of the boundary.
- **What am I assuming about state, schema, or environment?** Make assumptions explicit.
- **Is this verifiable at all, and how?** Name one of (a) the run/test you'll do, (b) the cost you're paying to verify, or (c) what makes it unverifiable (fresh-host bootstrap, prod-only, external service). Deciding *after* edits invites satisficing.

Scale the format to the task. A trivial typo doesn't need a section header. A schema migration does.

---

## 3. Delegation — push work out of the main context

The main context is the scarcest resource. By default delegate reads, web fetches, and long traces; keep edits and decisions in the main thread. **Which agent to call for what now lives in each agent's `description`** — read those, not a roster here.

- **When NOT to delegate:** the answer fits in one `grep` or one local file read; it's already in context; or the sub-agent would need to *write* (they're read-only by contract — `executor` is the exception).
- **Sub-agent contract:** trust the structured summary they return; don't re-read their sources unless the report is genuinely insufficient — send a follow-up to the same agent instead of re-opening raw material.
- **Kill-rule:** on any blocked or repeated-failure signal from a sub-agent, recall it, diagnose yourself, re-issue with corrected context.

---

## 3.1 Agent Teams (experimental)

Experimental tmux-based parallel agents. See `~/.claude/notes/agent-teams.md`.

## 3.2 Offer parallel modes proactively

When work splits cleanly — multi-file exploration, cross-layer review, parallel debug tracks, fan-out research, large migrations/audits — propose **Agent Teams** or a **Workflow** rather than grinding serially. Give the mode, shape, and cost; let the user opt in (Workflows require it). Re-offer per qualifying task; multiple offers a session is expected.

## 3.3 Background / child jobs are not one-shot

A background or child job is **not** a sandboxed batch worker. You MAY spawn sub-agents (`researcher`, `log-analyst`, …) and you SHOULD surface forks via `needs input:` rather than guess — unless the directive says otherwise. "The user may be away" bounds *cadence*, not *capability*; don't collapse it (or `--permission-mode plan`, or "headless") into a self-imposed no-tools / no-questions contract. If a directive explicitly authorizes sub-agents, that's an order, not a permission to decline.

---

## 4. Verification

Use TDD when the change is observable behavior and tests are practical (bug fixes, APIs, logic, parsers, auth). Otherwise verify by running the code.

Typical loop: targeted test that should fail → confirm Red → minimal implementation → confirm Green → broader relevant tests → eyeball the diff for stray debug artifacts. If verification fails, fix the cause, not the test. Read the full trace before guessing.

On repeated failure at the same spot: stop, summarize what you tried, ask for a reset rather than spiral.

**Syntax checks (`bash -n`, `tsc --noEmit`, lint) are a cheap filter, not proof.** Run them, then run the real path; if you can't run it, that path is unverified. An unverified path that's *out of scope* goes in "Not checked"; but the behavior you *changed* isn't "done" until confirmed — give the human the exact command, or mark it provisional. The `~/.claude/hooks/ship-gate.sh` PreToolUse hook gates publish/release/deploy until you attest the real path ran (`SHIP_GATE_ACK=1`) or ship provisional.

---

## 5. Closing a non-trivial task

The Background Session already requires `result:` as the completion signal. For non-trivial work, expand the line just above it into a short block — only the sections that have content:

- **Changes:** minimal list of what moved.
- **Tests:** what ran, what passed.
- **Risks:** side effects worth knowing.
- **Not checked:** explicit list of untested paths ("installer not run on fresh host", "rollback path not exercised"). "Tested locally" alone is a non-answer.

Skip the block entirely for trivial edits. Don't pad empty sections with "N/A".

---

## 6. Tracking work — three mechanisms, different scopes

Don't conflate them:

- **`TaskCreate` / `TaskList` / `TaskUpdate`** (harness) — in-session, volatile; the default for multi-step work in one session. `system-reminder` TaskCreate nudges mean *this* tool, not `todo.md`.
- **`tasks/todo.md`** — project-local, persistent; only for cross-session work or an explicit checklist request.
- **`tasks/lessons.md`** — append-only, post-miss; one entry = symptom → cause → countermeasure. Its value is *reconciling* stale entries after a later fix, not just appending.

Read `tasks/` files at session start and after compaction (the `SessionStart(compact)` hook nudges).

---

## 7. Anti-patterns

- Forwarding raw logs to `executor` — that's `log-analyst`'s job.
- Letting `executor` claim "done" without proof.
- Treating a syntax check (or build/lint pass) as proof that behavior works — see §4.
- Running formatters manually when a PostToolUse hook covers that language. Today only `.py` via `ruff` is wired up — check `settings.json` before assuming coverage for other languages.
- Two agents editing overlapping files in parallel.
- Sending a research *task* to a direct `WebFetch`/`WebSearch` instead of `researcher` — a one-shot doc/flag lookup direct is fine.
- Reformulating and retrying a *permission-denied* shell verb (e.g. `rm`) — denied ≠ rephrase. Pivot tools: delete via the language stdlib (`python -c 'import os; os.remove(...)'`), don't re-issue the same blocked verb with different paths.
- Grepping for a config value/host with `.env*` in the glob — the `guard-secrets.sh` hook blocks it, and the literal usually lives in the loader's default anyway. Grep the loader (`config.py`/`settings.py`/…), not the dotenv.
- Fighting `!` → `\!` in Bash-tool output with `set +H`/`unsetopt banghist` — wrong layer. The shell is **zsh**, but the harness escapes every literal `!` to `\!` before the shell sees it (even in single quotes, where no zsh option could). To get a clean `!` into output or an arg, keep it out of the source: `$'\41'` or `$(printf '\41')`. Stray backslash is harmless for most commands; fix only when the exact byte counts.
