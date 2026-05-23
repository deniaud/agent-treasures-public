---
name: write-a-skill
description: Create new agent skills with proper structure, progressive disclosure, and bundled resources.
argument-hint: "What skill do you want to build?"
disable-model-invocation: true
stage: proving
---

Goal: Generate structured agent skills via a strict 3-phase interactive process.

# Phase 1: Gather Requirements
- **Ask User:** Clarify domain, specific use cases, need for scripts vs. pure instructions, and reference materials.

# Phase 2: Draft
- **Core:** Create `SKILL.md` (Max 100 lines).
- **Split Files:** Create `REFERENCE.md` or `EXAMPLES.md` ONLY IF content exceeds 100 lines or has distinct domains.
- **Utility Scripts:** Create `scripts/helper.ext` ONLY IF operations are deterministic (validation/formatting) or require explicit error handling.

# Phase 3: Review
- **Ask User:** Present draft. Ask to verify use case coverage and identify missing parts.

# File Generation Rules

## SKILL.md Content Template
```md
---
name: [skill-name]
description: [Capability summary]. Use when [specific triggers/keywords/file types].
---
# [Skill Name]
## Quick start
[Minimal working example]
## Workflows
[Step-by-step processes with checklists]
## Advanced features
[Link to separate files: See [REFERENCE.md](REFERENCE.md)]
