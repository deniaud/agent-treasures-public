---
name: init-extended
description: Generate a comprehensive CLAUDE.md for the current repository — first runs Anthropic's /init for a baseline, then restructures with an extended standardized template (sections, security flows, anti-patterns, data models, CI/CD, common issues). Use when a repo has no CLAUDE.md or you want to enrich an existing one with extended structure.
argument-hint: "(optional) target repo path; defaults to cwd"
disable-model-invocation: true
stage: proving
---

Goal: Produce a comprehensive `<repo>/CLAUDE.md` in two phases plus a short report.

# Phase 1: Baseline via /init

Invoke the built-in `init` skill via the `Skill` tool. It analyzes the codebase and writes an initial `CLAUDE.md` covering stack, layout, and common commands.

Verify `CLAUDE.md` was created in the repo root before continuing.

# Phase 2: Template enhancement

Read the file `ENHANCE.md` next to this SKILL.md — it holds the full enhancement instructions and the required section template.

Apply those instructions to the existing `CLAUDE.md`:

* Use **exactly** the headings defined in `ENHANCE.md` — no other top-level headings.
* Preserve all content from Phase 1 — reorganize it into the new sections, do not delete information.
* Perform the supplementary research listed in `ENHANCE.md` (security flows, anti-patterns, data models, configs, testing, CI/CD, common issues, external refs).
* Mark gaps that require user knowledge as `TODO`.

# Phase 3: Report

Return a brief summary to the user:

1. What Phase 1 captured automatically.
2. What Phase 2 added or restructured.
3. Suggested improvements — fields where user knowledge is still needed.

Remind the user to review the file and commit `CLAUDE.md`.
