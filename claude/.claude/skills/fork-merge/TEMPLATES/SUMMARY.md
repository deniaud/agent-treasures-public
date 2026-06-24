# Fork-merge SUMMARY — {{repo}}

**Upstream:** `{{upstream_full_name}}` (default branch: `{{upstream_default}}`)
**Your fork:** `{{my_fork_full_name}}` (default branch: `{{my_fork_default}}`)
**Generated:** {{generated_at}}
**Workdir:** `{{workdir}}`

---

## How to use this file

1. For each feature below, set the checkbox to `[x]` if you want it merged into your fork.
2. Leave `[ ]` for features you want to skip.
3. Reorder features within their section if you want a specific apply order (top-to-bottom is the order used).
4. Save the file, then tell the agent **"continue"**.

The agent will:
- Filter `PLAN.md` to your picks, show you the refined plan.
- For each picked feature: create `feature/<slug>`, cherry-pick commits, ask before pushing.

---

## Forks researched

{{forks_table}}

<!-- Table columns: full_name | ahead | pushed_at | stars | features_found | dropped_in_phase_2_reason -->

---

## Features (ranked by integration_risk asc, then ahead_by desc)

{{#each features}}
### `[ ]` {{name}}

- **Source fork(s):** {{sources}}
- **Risk:** {{integration_risk}}{{#if risk_notes}} — {{risk_notes}}{{/if}}
- **Files touched:** {{files_touched}}
- **Commits:** {{commits_summary}}
- **Why useful:** {{useful_rationale}}
{{#if conflict_potential}}- **Conflict potential:** {{conflict_potential}}{{/if}}
{{#if has_lfs}}- ⚠️ **LFS:** this feature touches LFS-tracked files. You will be asked to confirm `git lfs install` before cherry-pick.{{/if}}
{{#if has_merge_commits}}- ⚠️ **Merge commits:** this feature contains merge commits — applied with `-m 1` (upstream as mainline).{{/if}}

<details><summary>Full description</summary>

{{description}}

</details>

---
{{/each}}

## Final status (filled by agent in Phase 8)

| Feature | Status | Notes |
|---|---|---|
{{#each features}}| {{name}} | _pending_ | |
{{/each}}

Status legend: `PUSHED` (branch + PR), `PUSHED-NO-PR` (branch only, PR failed), `SKIPPED` (user did not check), `CONFLICT` (cherry-pick aborted), `LFS-BLOCKED` (user did not confirm LFS), `BAD-OBJECT` (force-pushed source fork).
