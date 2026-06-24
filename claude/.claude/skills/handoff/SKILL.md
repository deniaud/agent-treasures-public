---
name: handoff
description: Generate conversation handoff document for the next agent session.
argument-hint: "What will the next session be used for?"
disable-model-invocation: true
stage: drafted
---

Goal: Summarize current conversation into a handoff document for a new agent.

# Rules:
- **Target Path:** Save **project-locally** to `<project>/tasks/handoffs/NN-handoff.md`, where `NN` is the next zero-padded sequence number (01, 02, 03, …) **counted within that project's folder**. The folder is anchored to the git repo root (falls back to `pwd` outside a repo), so the handoff lands in `tasks/handoffs/` even when invoked from a subdirectory. Compute it via:
  ```bash
  ROOT=$(git rev-parse --show-toplevel 2>/dev/null || pwd)
  DIR="$ROOT/tasks/handoffs"; mkdir -p "$DIR"
  LAST=$(ls "$DIR" 2>/dev/null | grep -oE '^[0-9]+' | sort -n | tail -1)
  printf '%s/%02d-handoff.md\n' "$DIR" "$((${LAST:-0} + 1))"
  ```
  If the user passed an argument, append a kebab-case slug: `NN-handoff-<slug>.md`. NEVER write to the global `~/.claude/handoffs/` — mixing unrelated projects there is what made the numbering meaningless.
- **Tailor Focus:** If user passes arguments, treat them as the next session's focus and tailor the doc accordingly.
- **No Duplication:** Reference existing artifacts (PRDs, plans, ADRs, issues, commits, diffs) by path/URL. NEVER duplicate their content.
- **Suggest Skills:** Recommend skills for the next session ONLY if applicable.
