# Fork-merge PLAN — {{repo}}

**Generated:** {{generated_at}}
**Workdir:** `{{workdir}}`
**Base for all feature branches:** `origin/{{my_fork_default}}` (state at clone time: `{{base_sha}}`)

This file is technical: exact commits, order, expected conflicts, cherry-pick strategy. The agent regenerates it after Phase 6 with only the features you `[x]`-marked in `SUMMARY.md`.

---

## Apply order

{{#each features}}
{{@index_1}}. `feature/{{slug}}` — {{name}} (risk: {{integration_risk}})
{{/each}}

---

{{#each features}}
## {{@index_1}}. `feature/{{slug}}`

**Source:** {{source_fork}} (remote `{{remote_name}}`, head `{{remote_name}}/{{fork_default}}`)
**Risk:** {{integration_risk}}{{#if risk_notes}} — {{risk_notes}}{{/if}}
**Files touched:** {{files_touched_count}} files
```
{{files_touched_list}}
```

### Commits to cherry-pick (in this order)

| # | SHA | Subject | Strategy |
|---|---|---|---|
{{#each commits}}| {{@index_1}} | `{{sha_short}}` | {{subject}} | {{strategy}} |
{{/each}}

Strategy codes:
- `pick` — `git cherry-pick <sha>`
- `pick -m 1` — merge commit, mainline = upstream-side (parent 1)
- `pick --skip` — likely already applied via upstream merges; let it skip if empty
- `lfs-confirm` — STOP first, ask user about `git lfs install`

### Expected conflicts

{{#if expected_conflicts}}
{{#each expected_conflicts}}
- `{{file}}` — overlaps with: {{overlap_source}} ({{overlap_reason}})
{{/each}}
{{else}}
None predicted. Researcher saw no overlap with other selected features or with the user's fork divergence from upstream.
{{/if}}

### Conflict resolution policy

1. Try auto-resolve (reading both sides). Apply ONLY when both versions add to non-overlapping logical regions of the same file.
2. Otherwise: `git cherry-pick --abort`, STOP, ask user.
3. Do NOT speculatively rewrite logic to "make conflicts go away".

### Commands (executed by agent)

```bash
cd "$WORKDIR/origin"
git checkout -b feature/{{slug}} origin/{{my_fork_default}}
{{#each commits}}
git cherry-pick {{strategy_flag}}{{sha}}
{{/each}}
# After clean apply, confirm with user, then:
git push origin feature/{{slug}}
gh pr create \
  --base {{my_fork_default}} \
  --head feature/{{slug}} \
  --title "{{name}}" \
  --body "$(cat <<'EOF'
{{pr_body}}
EOF
)"
```

### PR body draft

```
{{pr_body}}
```

---
{{/each}}

## Post-implementation cleanup (Phase 8)

1. Update `SUMMARY.md` with per-feature status (`PUSHED` / `SKIPPED` / `CONFLICT` / `LFS-BLOCKED` / `BAD-OBJECT`).
2. Copy `SUMMARY.md` → `~/.claude/plans/fork-merge-{{repo}}-{{ts}}.md`.
3. `chmod -R +w "$WORKDIR" && rm -rf "$WORKDIR"`.
4. Print Final Report (CHANGES / TESTS / RISKS / NOT CHECKED).
