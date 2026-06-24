# Agent Teams (experimental)

Enabled via `CLAUDE_CODE_EXPERIMENTAL_AGENT_TEAMS=1` + `teammateMode: "tmux"` in `~/.claude/settings.json`. Tools `TeamCreate` / `TeamDelete` / `SendMessage` are deferred — load via `ToolSearch`. State lives in `~/.claude/teams/{name}/` and `~/.claude/tasks/{name}/`; don't edit by hand.

Propose a team when parallel exploration adds real value: competing-angle research, multi-lens review (security/perf/tests), cross-layer work (frontend/backend/tests in parallel), independent new modules. Confirm with the user before spawning. Roles are ad-hoc — pick names that fit the lens (`security`, `perf`, `devil-advocate`, `architect`, etc.). Start with 3–5 teammates; avoid two of them editing the same file; clean up when done.

Don't use for routine single-session edits or sequential tasks — token cost scales linearly with teammates.
