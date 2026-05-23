#!/usr/bin/env bash
cat <<'EOM'

╔════════════════════════════════════════════════════════════════════╗
║  Manual follow-ups (agent-treasures install can't automate these) ║
╚════════════════════════════════════════════════════════════════════╝

1. Reload shell / open a new terminal:
       exec zsh -l
   Then activate direnv:
       direnv allow ~

2. Launch Claude Code:
       claude
   If --fresh-auth was used (or .credentials.json absent), follow OAuth.

3. Plugins — only `superpowers` is preserved. To re-add others:
       /plugin marketplace install anthropics/claude-plugins-official
       /plugin install telegram@claude-plugins-official
       /plugin install skill-creator@claude-plugins-official

4. Remote MCPs (Notion/Amplitude/etc.) — manage via /mcp UI in Claude Code
   or claude.ai → Settings → MCPs.

5. cc-switch desktop — launch once so it indexes the skill tree.

   were NOT auto-enabled. See docs/services.md for what each one needs (binary
   source, env files, postgres state, etc.) before:
       systemctl --user enable --now <unit>

7. For timers to fire while you're logged out:
       sudo loginctl enable-linger $USER

EOM
