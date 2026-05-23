# Agent Restore Runbook

Machine-readable runbook for an AI agent restoring this stack onto a fresh
machine. Minimum prose, maximum commands and tables.

## §0 Contract

**Inputs (operator provides before agent starts):**
- A fresh machine with writable `$HOME`. Linux (preferred) or macOS.
- SSH access to `git@github.com:deniaud/agent-treasures` (key in `~/.ssh/` or `ssh-agent`).
- Passphrase placed at `~/claude-recipe-seal-passphrase.txt` (mode `0600`, one
  line, no trailing data). Delivered through a separate channel (Telegram,
  password manager) — never in the repo, never in this doc.

**Output:**
- Working Claude Code stack. `claude --version` returns a number.
- `~/.claude/last-install.json` with `status == "ok"` (or `"ok"` + non-empty
  `degraded_reasons[]` — usable, but operator-attention items remain).

**Side effects (all under `$HOME`, except apt during step 05):**
- Writes/replaces config files (`~/.zshrc`, `~/.zshenv`, `~/.envrc`).
- Populates `~/.claude/`, `~/.cc-switch/`, `~/.tweakcc/`.
- Clones build deps to `~/dev/{tweakcc-fixed,CCometixLine}/` and
  `~/.tweakcc/lobotomized-claude-code/`.
- Installs apt packages (zsh, oh-my-zsh deps, build-essential) via sudo.
- Enables systemd user timers: `claude-snapshot`, `claude-pull`, `claude-prune`.

**NOT touched:** anything outside `$HOME` and the listed apt installs. No
system-wide configs, no other users' files.

---

## §1 Preconditions (run before install.sh)

| # | Check | Command | If fail |
|---|---|---|---|
| 1 | Git remote reachable | `ssh -T git@github.com 2>&1 \| grep -qi 'success'` | Add SSH key — see `troubleshooting.md#ssh-private` |
| 2 | Passphrase file present, 0600 | `[[ -f ~/claude-recipe-seal-passphrase.txt && "$(stat -c %a ~/claude-recipe-seal-passphrase.txt)" == "600" ]]` | Request passphrase from operator (separate channel); fix with `chmod 600` |
| 3 | Disk space ≥ 2 GB free in `$HOME` | `df -BG "$HOME" \| awk 'NR==2 {gsub("G","",$4); exit !($4 >= 2)}'` | Free space, retry |
| 4 | Internet OK | `curl -sf -o /dev/null -w "%{http_code}" https://github.com \| grep -q '^2'` | Check network — `troubleshooting.md#network` |
| 5 | Not running as root | `[[ "$(id -u)" -ne 0 ]]` | Re-login as target user; install.sh expects non-root `$HOME` |

If any of 1–5 fails: STOP. Don't proceed to install.sh. Report failure with the failing check name and which troubleshooting anchor applies.

---

## §2 Happy path

One command, ~5–15 min on fresh Linux (cargo build is the slowest step):

```
git clone git@github.com:deniaud/agent-treasures.git ~/dev/agent-treasures \
  && bash ~/dev/agent-treasures/install/install.sh
```

Recommended preflight first (no writes, prints plan):

```
bash ~/dev/agent-treasures/install/install.sh --dry-run
```

Flags for less-than-full restore:
- `--fresh-auth` — don't restore Claude credentials; user will `claude login` manually
- `--skip-secrets` — don't decrypt `secrets.env.gpg` (use if no passphrase yet; restore later)
- `--skip-systemd` — for containers without systemd (disables multi-machine sync)

---

## §3 Reading the result

After `install.sh` returns:

```
jq '{status, invariants_failed, degraded_reasons, next_actions}' ~/.claude/last-install.json
```

- File present, `.status == "ok"`, `invariants_failed == []` → install OK.
- File present, `.status == "fail"` → §4 decision tree.
- File absent → install crashed before step 98. Look at install.sh stdout for the
  last `[XX] <step name>` header — that's the failed step.

---

## §4 Decision tree

```
status == "ok" && degraded == false           → DONE. Run `claude --version` as sanity.
status == "ok" && degraded == true            → Usable. Read `.degraded_reasons[]`.
                                                Most common: FRESH_AUTH (user must `claude login`),
                                                Linger=no (run `sudo loginctl enable-linger $USER` if box is headless),
                                                SKIP_SECRETS (run `bash install/lib/95-secrets.sh` later).
status == "fail"                              → For each `.invariants_failed[]`:
                                                  1. Open `docs/troubleshooting.md` at the anchor in `.hint`.
                                                  2. Run the fix command listed there.
                                                  3. After ALL fixes applied: `bash install/lib/98-verify.sh`
                                                  4. Loop until status == "ok" OR max 3 attempts → escalate.
file absent                                   → Last successful step = previous `[XX]` header in stdout.
                                                Identify error category (network / build / npm / gpg / etc.),
                                                jump to matching `docs/troubleshooting.md#<anchor>`.
                                                Re-run `bash install/install.sh` (idempotent).
```

---

## §5 Idempotency

- `install.sh` and every `install/lib/*.sh` are safe to re-run.
- Existing files are backed up to `<name>.pre-install.<UTC_TS>.bak` before each write.
- Backups accumulate — clean old ones with: `find ~ -name '*.pre-install.*.bak' -mtime +30 -delete`.
- Maximum 3 automatic retries on the same step. After that: stop, report failure
  to operator with `last-install.json` contents.

---

## §6 Forbidden actions

The agent **must not**:

- `git push` from the treasures repo — `snapshot-recipe.sh` handles outbound pushes
  on a timer (avoiding two pushes from different processes racing).
- Modify `~/.envrc` directly — it's regenerated from `secrets/secrets.env.gpg` by
  `install/lib/95-secrets.sh`. Hand-editing creates drift that the next pull
  silently overwrites.
- Delete `~/claude-recipe-seal-passphrase.txt` after install — it's still needed
  by `claude-snapshot.timer` for re-encrypting secrets in future snapshots.
- Manually enable/disable systemd timers — install step 90 handles all three
  (`claude-snapshot.timer`, `claude-pull.timer`, `claude-prune.timer`). If a
  timer needs disabling for a specific reason, document why in the report.
- Bypass `--skip-systemd` to "make it work" in a container — disables multi-machine
  sync silently. Only legitimate use: known container-without-systemd environment.
- Run `claude update` as part of restore — version is pinned in `versions.lock`.
  Updates happen on the leader machine and propagate via snapshot+pull.

---

## §7 Multi-machine context

After install, this machine becomes part of the sync mesh:

- `claude-snapshot.timer` fires hourly at `:00` (±5 min jitter) — local config
  state is mirrored, sealed, committed, pushed.
- `claude-pull.timer` fires hourly at `:30` (±5 min jitter) — origin is fetched,
  whitelisted paths applied via rsync with pre-pull backups.
- `~/.claude/pre-pull-backups/<TS>/` holds the last 10 pull-backups for rollback
  via `~/.claude/scripts/pull-recipe.sh --rollback`.

If this machine is the **first** one on the mesh (sole source-of-truth): nothing
special — snapshot just pushes to an empty/uninhabited origin.

If this is a **follower** (joining an existing mesh): the first scheduled pull
will be a no-op since install already applied the latest snapshot. Subsequent
pulls catch up automatically.

See [`multi-machine.md`](multi-machine.md) for topology details, race-safety,
and per-machine sync disable instructions.

---

## §8 Cross-references

- Install step mechanics + flag reference: [`../INSTALL.md`](../INSTALL.md)
- Symptom → fix catalog: [`troubleshooting.md`](troubleshooting.md)
- Multi-machine topology: [`multi-machine.md`](multi-machine.md)
- Service inventory (systemd units, tooling deps): [`services.md`](services.md)
- Aliases and shell wrappers: [`aliases.md`](aliases.md)
- Manual post-install checklist (human-oriented): [`manual-steps.md`](manual-steps.md)
