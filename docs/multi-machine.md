# Multi-machine sync

Notes on running this stack across several boxes that share configs via the
`agent-treasures` repo.

## Topology

There's no formal leader/follower split. Every machine runs both timers:

| Timer | Frequency | Direction |
|---|---|---|
| `claude-snapshot.timer` | hourly at `:00` (jitter ±5 min) | local → origin |
| `claude-pull.timer` | hourly at `:30` (jitter ±5 min) | origin → local |

The 30-minute stagger means a push from machine A at 14:02 lands on GitHub
before B/C pull at 14:30. `RandomizedDelaySec=300` keeps boxes from hitting
GitHub at the same instant.

## What gets synced vs. what's per-machine

Synced through `claude/` and `host/` buckets:
- `~/.claude/agents/`, `commands/`, `skills/`, `rules/`, `CLAUDE.md`, `mcp/`
- `~/.cc-switch/{settings.json,skills/}`
- `~/.tweakcc/config.json`
- `~/.zshrc`, `~/.zshenv`
- `~/.config/systemd/user/*.service|*.timer`
- `~/.config/Code/User/{settings,keybindings,snippets}.json`
- `~/.codex/{AGENTS.md,config.toml,rules,memories,plugins}`
- `~/.local/bin/` portable scripts (whitelist in `snapshot-recipe.sh`; symlinks/binaries skipped)

Explicitly blacklisted by `pull-recipe.sh`:
- `~/.claude/.credentials.json` — per-machine Claude session
- `~/.claude/plugins/` — OAuth state
- `~/.claude/sessions/`, `projects/`, `__store.db*` — runtime state
- `~/.envrc` — populated only via `95-secrets.sh` from sealed bundle

Sealed secrets (`secrets/*.gpg`) live in the repo but require the passphrase
to apply. `pull-recipe.sh` doesn't decrypt them; rerun `install/lib/95-secrets.sh`
manually after a passphrase rotation.

## Race conditions

Both `snapshot-recipe.sh` and `pull-recipe.sh` are race-aware:

- `snapshot-recipe.sh` does `fetch + rebase` before mirroring and uses a
  `push_with_retry` loop (3 attempts, jittered) that re-rebases each time.
- `pull-recipe.sh` holds a `flock` on `~/.claude/pull.lock` and exits silently
  if another pull is in-flight. It uses `merge --ff-only`; on divergence it
  bails with exit code 4 and points the user at snapshot-first.

If two machines push concurrently and one wins, the loser's next snapshot
will rebase cleanly because we never commit substance-free diffs (the lock's
rotating timestamp alone doesn't trigger a commit).

## Noise reduction

Hourly cadence would normally drown the repo in churn. We strip the worst
offenders before staging:

- `plugins/known_marketplaces.json`: `.lastUpdated` field stripped (jq)
- `plugins/blocklist.json`: `.fetchedAt` stripped
- `~/.tweakcc/config.json`: `.lastModified` + `.changesApplied` stripped
- `~/.codex/models_cache.json`: `.fetched_at` + `.etag` stripped
- `~/.gnupg/random_seed` + agent sockets: excluded from sealed bundle
- GPG-encrypted bundles: skipped entirely if plaintext SHA matches the
  side-car `*.gpg.sha256` (no churn from random IV)
- `versions.lock` timestamp churn: detected, commit skipped if it's the only
  diff

## Rollback

Each `pull-recipe.sh` run writes pre-pull backups to
`~/.claude/pre-pull-backups/<UTC_TS>/`. Last 10 are kept; older ones get
pruned next run.

To undo the most recent pull:
```
~/.claude/scripts/pull-recipe.sh --rollback
```

To undo something older, copy from the backup dir manually:
```
ls ~/.claude/pre-pull-backups/
rsync -a ~/.claude/pre-pull-backups/<TS>/claude/.claude/ ~/.claude/
```

`~/.claude/last-pull.json` records the commit SHA + backup dir from each
successful pull.

## Disabling auto-pull on a machine

If a box should freeze its config and not auto-track origin:
```
systemctl --user disable --now claude-pull.timer
```
Snapshot still runs (so your local edits propagate elsewhere). To freeze
both directions:
```
systemctl --user disable --now claude-pull.timer claude-snapshot.timer
```

## First-time setup on a new follower

`install/install.sh` enables both timers via `90-systemd.sh`. After install:
```
systemctl --user list-timers claude-snapshot.timer claude-pull.timer
```
should show two timers scheduled for the next `:00` / `:30` mark.

If the follower has zero local divergence (just installed), the first pull
will be a no-op ("Up to date with origin").
