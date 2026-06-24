---
name: write-a-skill
description: "Create new agent skills with proper structure, progressive disclosure, and bundled resources. Use when: designing a skill, writing SKILL.md, building a skill template, or formalizing a recurring workflow into a reusable skill."
argument-hint: "What skill do you want to build?"
disable-model-invocation: true
stage: proving
---

Goal: Generate structured agent skills via a strict 4-phase interactive process.

**Skip if:** one-off script, project-specific convention, or an existing skill already covers the domain.

# Phase 0: Prior-art
- **Scan:** Check `~/.claude/skills/` for skills covering the same domain. If one exists — offer to extend it instead of duplicating.

# Phase 1: Gather Requirements
- **Ask User:** Clarify domain, specific use cases, need for scripts vs. pure instructions, and reference materials.
- **Pick type:** workflow (phased process) / reference (lookup material) / capability (single bounded action). Type changes SKILL.md shape.
- **Pick visibility:** agent-only (model auto-invokes, hidden from `/` menu) → `user-invocable: false`; user-only (manual `/` only, no auto-invoke) → `disable-model-invocation: true`; universal (both) → omit both. Ask the user.

# Phase 2: Draft
- **Core:** Create `SKILL.md` (Max 100 lines). Insert the visibility flag chosen in Phase 1 into the frontmatter (omit for universal).
- **Description rule:** written from Claude's POV — "when would I know to invoke this?" Include 2-3 alt-phrasings + file types/keywords.
- **Split Files:** Create `REFERENCE.md` or `EXAMPLES.md` ONLY IF content exceeds 100 lines or has distinct domains.
- **Utility Scripts:** Create `scripts/helper.ext` ONLY IF operations are deterministic (validation/formatting) or require explicit error handling.

# Phase 3: Review
- **Ask User:** Present draft. Ask to verify use case coverage and identify missing parts.

# Phase 4: Trigger test & finalize
- **Verify trigger:** Formulate a realistic user request that should activate the new skill. Confirm the description would match it. If not → return to Phase 2 and refine description, not body.
- **Acceptance checklist:** description triggers on the intended phrase; skill type declared and matches SKILL.md shape; file split justified per Phase 2 rules; ≤100 lines; quick-start example actually works.

# File Generation Rules

## SKILL.md Content Template
```md
---
name: [skill-name]
description: [Capability summary]. Use when [specific triggers/keywords/file types].
stage: [raw|drafted|proving|ready]
# visibility — pick one in Phase 1: user-invocable: false (agent-only) | disable-model-invocation: true (user-only) | omit (universal)
---
# [Skill Name]
## Quick start
[Minimal working example]
## Workflows
[Step-by-step processes with checklists]
## Advanced features
[Link to separate files: See [REFERENCE.md](REFERENCE.md)]
```
