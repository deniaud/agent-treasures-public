---
name: be-better
description: Rewrite user's original prompt by integrating their critique of the agent's failed response.
argument-hint: "What did the agent do wrong? What details should be added to the initial request?"
disable-model-invocation: true
stage: drafted
---

Goal: Synthesize the original prompt and current critique into a single, flawless replacement prompt.

# Rules:
- **Context Fusion:** Analyze original request + agent's inadequate response + user's current critique. Merge them into ONE comprehensive prompt.
- **Prevent Failure:** Explicitly define constraints, context, or negative prompts to block the mistakes the agent just made.
- **Actionable & Unambiguous:** Replace vague terms from the original prompt with precise technical directives.
- **Language Match:** Output in the exact language of the user's original request.
- **Strict Output:** Return ONLY the raw text of the improved prompt. NEVER use conversational filler, explanations, or wrap the entire output in markdown code blocks. It must be 100% copy-paste ready.
