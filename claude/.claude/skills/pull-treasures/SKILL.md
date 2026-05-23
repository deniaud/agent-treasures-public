---
name: pull-treasures
description: Pull latest agent-treasures snapshot from origin and apply to $HOME
disable-model-invocation: true
stage: proving
---

# Pull treasures

The user wants to fetch the latest snapshot from `git@github.com:deniaud/agent-treasures` and apply it to this machine.

## Steps

1. Run the pull-recipe in default mode (auto-apply, with pre-pull backup):

   ```
   ~/.claude/scripts/pull-recipe.sh
   ```

2. If the user passes `--dry-run`, forward it to the script so they can preview without writing.

3. After the script finishes, summarize for the user:
   - Whether anything was applied (or "up to date").
   - Where the pre-pull backup landed (line: `Pre-pull backups → ...`).
   - The commit SHA that was applied.
   - If any shell-rc files (`.zshrc`, `.zshenv`) were touched: remind them to run `exec zsh -l` to pick up the changes in the current shell.

## On failure

If the script exits with code 4 ("local treasures repo has diverged"), tell the user:

> Your local treasures repo has uncommitted work that hasn't reached origin. Run `~/.claude/scripts/snapshot-recipe.sh` first to push your work, then retry `/pull-treasures`.

If the script exits with code 3 ("fetch failed"), suggest checking the network and `git -C ~/dev/agent-treasures pull` manually.

## Rollback

If the user reports that something broke after applying, run:

```
~/.claude/scripts/pull-recipe.sh --rollback
```

This restores from the most recent `~/.claude/pre-pull-backups/<TS>/`.
