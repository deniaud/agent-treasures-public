---
name: fork-merge
description: Discover and merge useful features from sibling forks into the user's fork. Invoke only on explicit user request via /fork-merge with a fork URL.
argument-hint: "<my-fork-url> [--limit N]"
disable-model-invocation: true
stage: proving
---

Goal: turn "find useful patches scattered across sibling forks of upstream X" into one interactive pipeline — discover ahead forks → parallel research → SUMMARY → user picks → cherry-pick into per-feature branches → push + open PRs.

# Inputs
- `<my-fork-url>` (required). Parse from args; ask once if missing.
- `--limit N` (optional). Overrides hard caps in Phase 1 (default: unlimited compare calls until rate-limit guard trips).

# Phase 0 — Bootstrap
- Pre-flight, fail-fast STOPs:
  - `gh --version` missing → ask user to `sudo apt install gh` (or `brew install gh`) and `gh auth login` (or set `GITHUB_TOKEN`). Stop.
  - `gh api user -q .login` fails → not authenticated. Ask user to run `gh auth login` or export `GITHUB_TOKEN`. Stop. (Do NOT grep `gh auth status` for scopes — fine-grained PATs don't expose scopes; permission failures surface as 403 at use time and are handled per-operation in Phase 1 / Phase 7.)
  - `git -C $PWD rev-parse --show-toplevel` succeeds → STOP. `$PWD` is inside a git repo; workdir would pollute it. Ask user to `cd ~` (or any non-repo path).
- Create `WORKDIR=$PWD/.fork-merge-<repo>-<unix-ts>/`.
- `git clone <my-fork-url> $WORKDIR/origin`.
- Resolve upstream: `gh repo view <owner>/<repo> --json parent -q .parent.nameWithOwner`. If `null` → STOP with diagnostic of which case fired (not a fork / parent deleted-or-private / URL is upstream itself).
- `git -C $WORKDIR/origin remote add upstream <upstream-url>` + `git fetch upstream`.

# Phase 1 — Discover ahead forks
- Rate-limit guard: `gh api rate_limit -q .resources.core.remaining`. If `< (fork_count + 50)` → STOP, show reset time from `.resources.core.reset`.
- List: `gh api repos/<upstream>/forks --paginate -q '.[] | {full_name, default_branch, pushed_at, stargazers_count, node_id}' > $WORKDIR/forks-raw.json`. Dedup by `node_id`.
- For each fork: `gh api repos/<upstream>/compare/<upstream-default>...<fork-owner>:<fork-default>` → `ahead_by`, `behind_by`, `commits[]`, `merge_base_commit`. **Parallelism: max 4** (`xargs -P 4`) to avoid secondary abuse rate-limit.
- Filter: keep `ahead_by > 1` AND `merge_base_commit != null` AND `behind_by <= 10000`. Save to `$WORKDIR/forks.json`.
- See [REFERENCE.md](REFERENCE.md) §1 for exact commands and jq filters.

# Phase 2 — Manual filtering
- Read `forks.json`. For each fork, judge by: commit messages (first 5), `pushed_at` recency, stars, owner/repo name.
- Drop obvious noise: README translations, typo-only commits, dead forks (>2 years no meaningful commits), i18n-only forks, dependency-bump-only forks.
- Save `$WORKDIR/shortlist.json` with explicit `dropped_reason` for each excluded entry.

# Phase 3 — Parallel research
- For each shortlisted fork:
  - safe-name = `<owner>-<repo>` (sanitize via `tr / -`; on collision append `-2`, `-3`, …).
  - `git remote add <safe-name> <fork-url>` then `git fetch <safe-name>` — **serial fetches** (avoids `.git/packed-refs` races).
- Launch `researcher` subagents **in parallel** (one message, N `Agent` tool calls). Each researcher receives: workdir path, remote name, base (`upstream/<default>`), head (`<safe-name>/<fork-default>`), commit SHAs, brief upstream-project description. Returns structured REPORT (see [REFERENCE.md](REFERENCE.md) §2 for schema).

# Phase 4 — Synthesis
- Aggregate REPORTs, deduplicate features (if 2 forks reimplement the same thing, mark and pick the cleaner source for PLAN).
- Generate `$WORKDIR/SUMMARY.md` from [TEMPLATES/SUMMARY.md](TEMPLATES/SUMMARY.md) — checkboxes `[ ]` per feature with source, risk, one-line rationale.
- Generate `$WORKDIR/PLAN.md` from [TEMPLATES/PLAN.md](TEMPLATES/PLAN.md) — per-feature: commits to pick (with `is_merge_commit`/`has_lfs` flags), apply order, expected conflicts, cherry-pick strategy.

# Phase 5 — User edit
- Tell user: *"Open `<WORKDIR>/SUMMARY.md`, mark `[x]` features you want, then say "continue""*. STOP. Wait for explicit signal.

# Phase 6 — Refine PLAN
- Re-read `SUMMARY.md`, filter PLAN by `[x]`. Show refined PLAN to user. Continue on confirmation.

# Phase 7 — Implementation
- For each selected feature, in PLAN order:
  - `git checkout -b feature/<slug> origin/<default>`.
  - Apply per cherry-pick decision tree ([REFERENCE.md](REFERENCE.md) §3): normal / merge-commit (`-m 1`) / empty (`--skip`) / LFS-flagged (stop & warn) / force-pushed bad-object (skip feature, continue).
  - Conflict: try to resolve by reading both versions and inferring intent. If unresolvable → `git cherry-pick --abort`, STOP, show conflicting files + remaining features list.
- After a clean branch: **confirm with user before each push** (CLAUDE.md §1 non-negotiable). Then `git push origin feature/<slug>` + `gh pr create --base main --head feature/<slug>`. PR body = feature rationale from REPORT.

# Phase 8 — Cleanup
- Annotate `SUMMARY.md` with final per-feature status: `PUSHED` / `SKIPPED` / `CONFLICT` / `LFS-BLOCKED`.
- Copy `$WORKDIR/SUMMARY.md` → `~/.claude/plans/fork-merge-<repo>-<unix-ts>.md`.
- `chmod -R +w $WORKDIR && rm -rf $WORKDIR`.
- End with Final Report (CLAUDE.md §5): CHANGES / TESTS / RISKS / NOT CHECKED.

# Hard rules
- Never push without an explicit user confirmation for THAT push (not blanket).
- Never `rm -rf` workdir before all branches are pushed (or user explicitly aborts).
- Never delegate to a researcher subagent something already in current context.
- Never use `gh pr create` against upstream — always head=user's fork, base=user's fork main.
