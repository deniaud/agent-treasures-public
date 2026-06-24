---
name: git-workflow
description: Git workflow patterns — branching, committing, rebasing, conflict resolution. Use when working with git operations.
stage: raw
---

# Git Workflow

## Branch Naming
- `feat/short-description` — new feature
- `fix/short-description` — bug fix
- `refactor/short-description` — refactoring
- `chore/short-description` — maintenance, config, deps

## Commit Format
```
type: short description (imperative, English, max 72 chars, no period)
```
Types: `feat`, `fix`, `refactor`, `chore`, `docs`, `test`

## Before Committing
1. `git diff --staged` — review all staged changes
2. Run project tests (if they exist)
3. Formatting is handled by hooks — do not run manually

## Merge Conflicts
1. `git fetch origin`
2. `git rebase origin/<target-branch>`
3. Resolve conflicts file by file
4. `git add <resolved-files>`
5. `git rebase --continue`

## Undo Patterns
- Unstage file: `git reset HEAD <file>`
- Discard working changes: `git checkout -- <file>`
- Amend last commit (not pushed): `git commit --amend`
- Undo last commit (keep changes): `git reset --soft HEAD~1`
- Undo last commit (discard changes): `git reset --hard HEAD~1`

## PR Workflow
1. Create branch from `dev` (or project's default dev branch)
2. Make changes, commit with descriptive messages
3. Push: `git push -u origin <branch-name>`
4. Create PR via `gh pr create`
5. After approval: merge and delete branch
