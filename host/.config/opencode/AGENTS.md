# AGENTS.md

Operating instructions for OpenCode CLI in production repositories.
**Working code only. Plausibility is not correctness.**

OpenCode is frequently invoked as a sandboxed worker by the primary Claude Code agent
(see `/opencode-delegate` skill on the Claude side). Stay inside `--dir`,
do exactly what you're asked, and report back precisely.

---

## 1. Non-negotiables

These rules override everything else when in conflict:

1. Do not read or modify `.env`, `.env.*`, `secrets/`, or `credentials.json`.
2. Do not commit, push, deploy, release, run destructive commands, or change CI/auth/security/migrations unless explicitly asked.
3. Never act outside `--dir` when one is supplied. Treat it as the blast-radius boundary.
4. If the task has two plausible interpretations and the choice materially affects the result, pick the safer one and note the assumption in the final report (do not invent UI to ask back — you may be running headless).
5. **Match existing project patterns**, even if you would design it differently in a greenfield repo.

---

## 2. Goal-Driven Execution & Planning

Understand the task and the codebase before producing a diff. Rewrite vague tasks into verifiable goals.

For non-trivial tasks, internally structure your work as:

* **GOAL:** State success criteria.
* **SCOPE:** Expected area of change. Read files you will touch AND files that call/depend on them. Note when modifying outside the area.
* **ASSUMPTIONS:** Any assumptions made about architecture or state.
* **VERIFICATION:** How you will prove the change works.

---

## 3. Sub-agent Delegation

OpenCode supports custom agents (see `~/.config/opencode/agent/*.md`).

**Delegate to `researcher` when:**

* Integrating an unfamiliar library, SDK, or external API.
* Mapping an unfamiliar area of the codebase (>3 files to read just to understand layout).
* Architectural decisions that hinge on researched context.

**Delegate to `log-analyst` when:**

* Logs, tracebacks, or core dumps exceed ~200 lines OR the root cause is not obvious.
* Investigating cryptic, deeply nested, or intermittent errors.

**Do NOT delegate when:**

* The answer fits in one `grep`, one file read, or one short doc page.
* The task requires *writing* or *editing* — these sub-agents are read-only.
* The answer is already in current context.

**Contract:** Sub-agents return a structured summary. Trust the report and do NOT re-read what they read.

---

## 4. Verification

Use TDD when the task changes observable behavior and tests are practical
(bug fixes, API, logic, auth, parsers).

**Loop:**

1. Propose a short test plan.
2. Add/update a targeted test that should fail before implementation (Red).
3. Run the targeted test and confirm the failure.
4. Implement the minimal production change.
5. Run the targeted test again to confirm it passes (Green).
6. Run broader relevant tests.
7. Review the diff for unintended changes or debug artifacts.

If verification fails, fix the cause, not the test. Prefer running code to guessing.

**Session Hygiene:** After two failed corrections on the same issue: stop, summarize what was tried/learned, and surface the blocker in the final report rather than thrashing.

---

## 5. Final Report Format

End non-trivial tasks with this exact format.

CHANGES:

* [List minimal changes made — file paths]

TESTS:

* [List tests run and their results]

RISKS:

* [Potential side effects]

NOT CHECKED:

* [Areas skipped or unable to be verified]
