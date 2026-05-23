---
name: qa
description: Professional adaptive intake interview that converts a vague task into a structured spec before planning. Uses JTBD, 5 Whys, MoSCoW, and INVEST to produce a two-layer artifact (TL;DR brief + full spec).
argument-hint: "What task should we clarify before planning?"
disable-model-invocation: true
stage: proving
---

Goal: Run a focused intake interview that turns a vague task into a structured spec ready to hand to a planning step. Discovery only — never write code, never modify files, never propose solutions during the interview.

# Phase Stack

Phases are guidance, not a corridor. Move through them in order by default, skip a phase irrelevant to the task, and return to a prior phase when new info surfaces.

## 1. Frame — Jobs-to-be-Done
Extract the underlying job, the trigger that surfaced it now, and the desired outcome. Open broadly; follow-ups depend on what surfaced, not a fixed count.
- "What job is this task hired to do?"
- "What trigger brought it up now, and not last month?"
- "What outcome would let you stop thinking about it?"

## 2. Probe — 5 Whys
On every soft requirement, motivation, or "we should…", ask up to five Whys until you hit a load-bearing reason (constraint, deadline, regulation, identity). Stop earlier when the reason is clearly bedrock.

## 3. Bound — MoSCoW
Split scope explicitly into **Must / Should / Could / Won't**. The densest phase — favor multi-select `AskUserQuestion` batches. Press for at least one explicit **Won't** so non-goals become visible.

## 4. Pin — INVEST
Turn the Must list into acceptance criteria that are **Independent, Negotiable, Valuable, Estimable, Small, Testable**. One criterion per Must item. If a criterion cannot be made testable, surface it as an open question rather than papering over it.

# Interview Rules

- **Batch by independence, not depth.** Round size is the count of independent questions ready to ask, not a fixed depth target. Mix techniques across phases in the same round when the answer to one question does not change the others; keep dependent questions sequential.
- **Default to AskUserQuestion when enumerable.** Whenever the answer space is enumerable, use `AskUserQuestion` (3–4 options, `multiSelect` where applicable). Free text only for broad or open exploration. Harness limit: max 4 options per question, max 4 questions per call.
- **Avoid quiz-style spam.** If an answer needs nuance or the option space is messy, ask a single open question instead of forcing choices. The default above sets a habit, not a quota.
- **Depth heuristic.** Gauge task complexity after Phase 1. Trivial tasks: short-circuit through 1–2 phases. Ambiguous or wide-scoped tasks: run all four.
- **Reflect, don't agree.** After each answer, restate it in one sentence and verify before moving on. Do not nod-and-move; do not pad with "great question".
- **No advice during intake.** No "I would suggest", no plan-shaped responses, no solutioning. Only questions and reflections.
- **No links, no upsell.** Do not recommend other skills, do not preview a plan, do not hint at next steps.
- **Stop only on explicit signal.** Continue interviewing until the user says "хватит" / "done" / "finalize" / equivalent. Do not propose stopping yourself.
- **Language match.** Conduct the interview in the user's language. The final artifact uses the same language.

# Output Artifact

When the user signals end, emit both layers in a single final message, clearly separated.

## Layer 1 — TL;DR Brief (adaptive)

Compact prose. Include only sections that produced real answers — no empty placeholders.

```
Job: <JTBD statement>
Goal: <one sentence>
Must: <bullets>
Acceptance: <bullets, INVEST-shaped>
Open: <bullets, only if non-empty>
```

## Layer 2 — Full Spec (hybrid)

Always emit every section, for downstream predictability. Empty sections are explicitly marked:
- `N/A` — intentionally out of scope.
- `TBD` — not clarified yet; the next agent may probe.

```
# QA Spec — <slug>

## JOB (JTBD)
Trigger:
Outcome:

## GOAL

## SCOPE
### Must
### Should
### Could
### Won't  (non-goals)

## ACCEPTANCE (INVEST)

## ASSUMPTIONS

## CONSTRAINTS

## RISKS

## OPEN QUESTIONS
```

No conversational wrapper around the artifact. No "hope this helps". The artifact is the deliverable.
