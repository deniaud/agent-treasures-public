# fork-merge — REFERENCE

Concrete commands, jq filters, schemas, and the cherry-pick decision tree. Stays out of SKILL.md so the entry point stays scannable.

---

## §1. Phase 1 commands — discovery

### Rate-limit guard

```bash
gh api rate_limit -q '{remaining: .resources.core.remaining, reset: .resources.core.reset}'
```

STOP threshold: `remaining < (fork_count + 50)`. Convert `reset` (epoch) → human-readable: `date -d @<reset>`.

### List forks (paginated, deduped)

```bash
gh api repos/<UPSTREAM>/forks --paginate \
  -q '.[] | {full_name, default_branch, pushed_at, stargazers_count, node_id}' \
  | jq -s 'unique_by(.node_id)' \
  > "$WORKDIR/forks-raw.json"
```

Always dedup by `node_id`, not `full_name` — protects against rename-and-stale-cache cases.

### Compare each fork to upstream

Inputs per fork: `full_name`, `default_branch`. Upstream's default_branch may differ — query separately if needed:

```bash
UPSTREAM_DEFAULT=$(gh api repos/<UPSTREAM> -q .default_branch)
```

Per-fork compare (note: fork's own `default_branch` is the head):

```bash
gh api "repos/<UPSTREAM>/compare/${UPSTREAM_DEFAULT}...${FORK_OWNER}:${FORK_DEFAULT}" \
  -q '{ahead_by, behind_by, merge_base: .merge_base_commit.sha, commits: [.commits[] | {sha, message: .commit.message, parents: [.parents[].sha]}]}'
```

Batch across all forks with bounded parallelism:

```bash
jq -r '.[] | "\(.full_name)\t\(.default_branch)"' "$WORKDIR/forks-raw.json" \
  | xargs -P 4 -n 1 -I {} bash -c 'compare_one "{}"'
```

Where `compare_one` writes per-fork JSON to `$WORKDIR/compare/<safe-name>.json`. **Never go above `-P 4`** — secondary abuse rate-limit triggers ≥10 concurrent calls to the same resource.

### Final filter

```bash
jq -s '[.[] | select(.ahead_by > 1 and .merge_base != null and .behind_by <= 10000)]' \
  $WORKDIR/compare/*.json > $WORKDIR/forks.json
```

---

## §2. Phase 3 — researcher subagent prompt and REPORT schema

### Prompt skeleton (one per fork)

> You are analyzing fork `<FORK_FULL_NAME>` to find features worth porting back into the user's fork of `<UPSTREAM>`.
>
> Workdir: `<WORKDIR>/origin` (git repo, your fork is `origin`, upstream is `upstream`, target fork is remote `<safe-name>`).
> Base: `upstream/<UPSTREAM_DEFAULT>`. Head: `<safe-name>/<FORK_DEFAULT>`.
> Commits to consider (newest first): `<SHA list from compare>`.
> Upstream project does: `<one-liner about what the project is>`.
>
> For each meaningful feature in the diff, return a YAML block with the schema below. Group related commits under one feature. Skip cosmetic-only changes (whitespace, README typos, dependency bumps without behavior change).
>
> Use `git log --format=fuller <base>..<head>`, `git show <sha>`, `git diff <base>...<head> -- <path>` to inspect. Read `.gitattributes` to detect LFS filters. Read the fork's README/CHANGELOG if present (`git show <safe-name>/<default>:README.md`).
>
> Be skeptical: many forks have personal preferences (renamed configs, hardcoded paths) that look like features but are noise. Mark those as `integration_risk: high` with a note.

### REPORT schema (YAML, one block per feature)

```yaml
fork: <full_name>
features:
  - name: <kebab-case slug, max 5 words>
    description: <one paragraph: what the feature does, why useful>
    commits:                          # in apply order
      - sha: <full sha>
        message: <subject line>
        is_merge_commit: <bool>       # true if commit has >1 parent
    files_touched: [<path>, ...]
    has_lfs: <bool>                   # true if .gitattributes has LFS filters on touched paths
    integration_risk: low | med | high
    risk_notes: <why this risk level>
    conflict_potential:               # other forks/features likely to clash
      - <fork-full-name>             # or [] if none
    useful_rationale: <one sentence justifying inclusion>
```

Main agent merges all reports in Phase 4 and deduplicates by overlapping `files_touched` × similar `name`/`description`.

---

## §3. Phase 7 — cherry-pick decision tree

Run per commit, in the order from PLAN:

```
read commit metadata
├── is_merge_commit == true
│   └── git cherry-pick -m 1 <sha>             # mainline = upstream side (parent 1)
├── has_lfs == true (any file in commit)
│   └── STOP. Tell user: "feature <X> touches LFS files. Ensure `git lfs install` and LFS objects available before continuing."
├── default (plain commit)
│   └── git cherry-pick <sha>
└── on error:
    ├── stderr matches "bad object" or "unknown revision"
    │   └── force-pushed upstream-side. Mark feature SKIPPED. Continue with next feature.
    ├── stderr matches "nothing to commit" / "patch is empty"
    │   └── git cherry-pick --skip ; continue            # already applied upstream
    └── stderr matches "CONFLICT"
        ├── try auto-resolve:
        │   - read both versions (`git show :2:<file>` and `:3:<file>`)
        │   - if intent obvious (additive, non-overlapping logical regions) → write merged result → `git add` → `git cherry-pick --continue`
        │   - if any ambiguity → ABORT
        └── if auto-resolve unsuccessful:
            - git cherry-pick --abort
            - STOP. Show: conflicting files, line ranges, fork SHA being applied, remaining-features queue.
            - Wait for user instruction (resolve manually / skip feature / abort all).
```

Auto-resolve is *deliberately conservative*. Spending tokens on hand-merging cross-cutting logic frequently produces silently wrong code — abort and ask is the safer default.

---

## §4. Per-fork remote management

### safe-name generation

```bash
safe_remote_name() {
  local full_name="$1"   # e.g. alice/CCometixLine
  local base="${full_name//\//-}"   # alice-CCometixLine
  local candidate="$base"
  local n=2
  while git -C "$WORKDIR/origin" remote | grep -qx "$candidate"; do
    candidate="${base}-${n}"
    n=$((n+1))
  done
  echo "$candidate"
}
```

### Adding remotes & fetching (serial)

```bash
git -C $WORKDIR/origin remote add "$SAFE" "https://github.com/${FULL_NAME}.git"
git -C $WORKDIR/origin fetch "$SAFE" "${FORK_DEFAULT}:refs/remotes/${SAFE}/${FORK_DEFAULT}"
```

Fetch sequentially. Parallel fetches into one repo race on `.git/packed-refs` and pack writers. Reads (`git log`, `git show`, `git diff`) by parallel researchers are safe.

---

## §5. Phase 8 — cleanup

```bash
# Annotate SUMMARY.md inline with PUSHED / SKIPPED / CONFLICT / LFS-BLOCKED tags first.

# Preserve SUMMARY only:
cp "$WORKDIR/SUMMARY.md" "$HOME/.claude/plans/fork-merge-${REPO}-${TS}.md"

# Force-writable then delete (some FS make pack files read-only):
chmod -R +w "$WORKDIR"
rm -rf "$WORKDIR"
```

---

## §6. Edge-case quick table

| Case | Detection | Action |
|---|---|---|
| `gh` not installed | `gh --version` exits non-zero | STOP, ask user to install + `gh auth login` (or set `GITHUB_TOKEN`) |
| `gh` not authenticated | `gh api user -q .login` exits non-zero | STOP, ask user to `gh auth login` or set `GITHUB_TOKEN`. Do NOT grep `gh auth status` for scopes — fine-grained PATs have permissions, not scopes; lack of permission surfaces as 403 at use time |
| Permission denied at API call | `gh api ...` returns 403 with "Resource not accessible by personal access token" | STOP, show which permission is needed (Contents/Pull requests/Metadata depending on call), ask user to extend fine-grained PAT or switch to classic token with `repo` scope |
| `$PWD` inside git repo | `git rev-parse --show-toplevel` exits 0 | STOP, ask to `cd ~` |
| Not a fork / parent null | `gh repo view ... -q .parent` → `null` | STOP, diagnose: detached / private parent / URL is upstream |
| Core API rate-limit | `remaining < fork_count + 50` | STOP, show reset time |
| Secondary abuse limit | HTTP 403 with "abuse" or "secondary" in body | reduce `xargs -P` to 1, retry after 60s once; if still fails, STOP |
| Renamed upstream | `node_id` differs across forks pointing at same logical repo | dedup by `node_id` |
| Default branch divergence (fork on `develop`, upstream on `master`) | `default_branch` per fork from forks API | use each fork's own `default_branch` as head in compare |
| Fork diverged independently (no common base) | `merge_base_commit` is `null` OR `behind_by > 10000` | filter out in Phase 1 |
| Merge commit cherry-pick | commit has >1 parent in REPORT | `git cherry-pick -m 1 <sha>` |
| Empty cherry-pick (already applied) | git stderr "nothing to commit" / "patch is empty" | `git cherry-pick --skip` |
| Force-pushed fork, SHA gone | git stderr "bad object" / "unknown revision" | mark feature SKIPPED, continue |
| LFS-tracked file in commit | `has_lfs: true` from researcher | STOP before cherry-pick, warn |
| safe-name collision | existing remote with same name | append `-2`, `-3`, … |
| Push fails (auth/scope) | `git push` non-zero | STOP, show stderr, do not retry blindly |
| Pre-commit hook on user's fork | hook script in `.git/hooks/` runs on push or in PR's CI | not bypassed — hook failures stop the loop, ask user |
