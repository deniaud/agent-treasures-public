---
name: zoom-out
description: Provide broader context, high-level perspective, or architectural map. Triggered by requests to zoom out, big picture, or unfamiliar code.
argument-hint: "Which file, module, or component do you need the big picture for?"
disable-model-invocation: true
stage: proving
---

Goal: Provide a high-level architectural map and broader context for the specified code area.

# Rules:
- **Abstraction:** Go up a layer of abstraction. NEVER focus on line-by-line implementation details.
- **Mapping:** Map all relevant modules, dependencies, and callers.
- **Vocabulary:** Strictly use the project's established domain glossary and terminology.
