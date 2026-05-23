# CLAUDE.md

Operating principles for coding agents in production repositories.
**Working code only. Plausibility is not correctness.**

These are principles, not a checklist — apply judgement. The system prompt already covers commit/push safety, README hygiene, and `result:` reporting; don't duplicate them here.

---

## Tenets (read first, even under compression)

1. **Working code, not plausible code.** Run the path, don't just parse it.
2. **A fork in the road = ask first.** Two interpretations → surface the tradeoff.
3. **Delegate when verify-fix loops exist and judgement-calls don't.** Otherwise: main.
4. **Verifiability is decided before edits; honesty about Not checked, after.**
5. **Three trackers, three scopes.** `TaskCreate` (in-session), `todo.md` (cross-session), `lessons.md` (post-miss).

---

## 1. Hard rules

Override everything else when in conflict:

1. **Secrets are off-limits.** Don't read or modify `.env`, `.env.*`, `secrets/`, `credentials.json`. Reference variable *names* via a dotenv-loader; never their contents. The `~/.claude/hooks/guard-secrets.sh` PreToolUse hook is the enforcement layer.
2. **Stop on a fork in the road.** If a task has two plausible interpretations and the choice materially changes the result, surface the tradeoff before choosing — unless Auto Mode is active and a reasonable default is obvious.
3. **Match the codebase you're in.** When a quirky pattern looks like a bug (silent `exit 0`, one-shot guards, magic constants), treat it as deliberate and ask before "fixing". In well-used code, half of "obvious bugs" are design choices.

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

The main context is the scarcest resource. Default to delegating reads, web fetches, and long traces; keep edits and decisions in the main thread.

**Delegate aggressively to `researcher`:**

- **Anything that would invoke `WebSearch` or `WebFetch` directly.** Web research belongs in `researcher`, not the main context — search results are noise-heavy and burn the cache. The only exception is fetching a single known URL when the answer is one paragraph.
- Integrating an unfamiliar library, SDK, or external API.
- Reading multiple docs / RFCs / web sources to orient.
- Mapping an unfamiliar codebase area (>3 files to understand layout or call graph).
- Architectural decisions hinging on researched context.

**Delegate to `log-analyst`** when logs/tracebacks exceed ~200 lines, when CI/crash root cause isn't obvious at a glance, or when an error is cryptic, nested, or intermittent.

**Delegate to `executor` when both hold:** (A) the task has an autonomous verify-fix loop available (tests, lint, runtime check that closes the cycle without you), AND (B) no judgement calls are likely mid-task (no ambiguous interpretations, no "ask the user" forks). If A∧B don't both hold, executor's overhead exceeds the win — work in main. **Triple-tripwire** (a reconsideration prompt, not a hard rule): if any two of {>3 files touched, >150 LoC of diff, >15 min wall-clock} land in the same task, re-check A∧B even if you said "main" earlier. Calibrators (one line each):
- TS/Python feature with passing test framework, spec clear → A∧B both → executor.
- Bash installer fix verifiable only on fresh host → A fails → main.
- Refactor with mid-task user choice ("rename or split?") → B fails → main.

**Delegate to `reviewer`** when the cost of a missed issue exceeds the cost of a second pass: multi-file refactors, security-sensitive surface (auth, secrets, parsers, IPC), or any change you couldn't fully verify yourself. Skip for routine single-file fixes and for changes you already verified end-to-end.

**When NOT to delegate:** the answer fits in one `grep` or one local file read; the answer is already in current context; the sub-agent would need to *write* (they're read-only by contract — `executor` is the exception).

**Sub-agent contract:** trust the structured summary they return; don't re-read their sources unless the report is genuinely insufficient — in that case, send a follow-up to the same agent rather than re-opening raw material.

**Kill-rule:** if a sub-agent loops 3+ times on the same error with no progress, recall it, diagnose yourself, re-issue with corrected context.

---

## 3.1 Agent Teams (experimental)

Enabled via `CLAUDE_CODE_EXPERIMENTAL_AGENT_TEAMS=1` + `teammateMode: "tmux"` in `~/.claude/settings.json`. Tools `TeamCreate` / `TeamDelete` / `SendMessage` are deferred — load via `ToolSearch`. State lives in `~/.claude/teams/{name}/` and `~/.claude/tasks/{name}/`; don't edit by hand.

Propose a team when parallel exploration adds real value: competing-angle research, multi-lens review (security/perf/tests), cross-layer work (frontend/backend/tests in parallel), independent new modules. Confirm with the user before spawning. Roles are ad-hoc — pick names that fit the lens (`security`, `perf`, `devil-advocate`, `architect`, etc.). Start with 3–5 teammates; avoid two of them editing the same file; clean up when done.

Don't use for routine single-session edits or sequential tasks — token cost scales linearly with teammates.

---

## 4. Verification

Use TDD when the change is observable behavior and tests are practical (bug fixes, APIs, logic, parsers, auth). Otherwise verify by running the code.

Typical loop: targeted test that should fail → confirm Red → minimal implementation → confirm Green → broader relevant tests → eyeball the diff for stray debug artifacts. If verification fails, fix the cause, not the test. Read the full trace before guessing.

After two failed corrections on the same issue: stop, summarize what was tried, ask for a reset rather than spiral.

**Syntax-level checks (`bash -n`, `tsc --noEmit`, lint, format) are NOT verification.** They prove parsability, not behavior. If you can't run the actual code path, say so explicitly in Not checked — do not pad with `bash -n` as if it counted.

---

## 5. Closing a non-trivial task

The Background Session already requires `result:` as the completion signal. For non-trivial work, expand the line just above it into a short block — only the sections that have content:

- **Changes:** minimal list of what moved.
- **Tests:** what ran, what passed.
- **Risks:** side effects worth knowing.
- **Not checked:** what you skipped or couldn't verify.

Skip the block entirely for trivial edits. Don't pad empty sections with "N/A".

**Not checked is a list, not a phrase.** Name each untested path explicitly ("installer not run on fresh host", "rollback path not exercised", "Windows variant untested"). "Tested locally" alone is not a Not checked — it's a non-answer.

---

## 6. Tracking work — three mechanisms, different scopes

Don't conflate these:

- **Harness `TaskCreate` / `TaskList` / `TaskUpdate`** — in-session, volatile. Default tracker for any multi-step work inside a single session. Cheap, no file IO. Use this unless you have a reason not to. `system-reminder` nudges about TaskCreate refer to *this* tool, not to `tasks/todo.md`.
- **`tasks/todo.md`** — project-local, persistent, opt-in. Use only when work spans sessions OR when the user asks for a written checklist. Not required for every non-trivial task — when in doubt, `TaskCreate` covers it.
- **`tasks/lessons.md`** — project-local, append-only. Patterns: symptom → root cause → countermeasure. Written *after* a non-obvious miss, not as routine logging. One entry = one lesson, not a journal.

Read `tasks/` files at session start and after compaction if they exist (the `SessionStart(compact)` hook nudges).

`executor` writes persistent notes to `<project>/.claude/agent-memory/executor/` — intentionally committed (shared with the team). Add to `.gitignore` per-project if you want it untracked.

---

## 7. Anti-patterns

- Forwarding raw logs to `executor` — that's `log-analyst`'s job.
- Letting `executor` claim "done" without proof.
- Counting `bash -n` / type-check / lint as verification (see §4).
- Running formatters manually when a PostToolUse hook covers that language. Today only `.py` via `ruff` is wired up — check `settings.json` before assuming coverage for other languages.
- Two agents editing overlapping files in parallel.
- Calling `WebFetch`/`WebSearch` directly when `researcher` is the right tool.
- Conflating `system-reminder` nudges about `TaskCreate` (harness tool) with `tasks/todo.md` (project file) — see §6.
