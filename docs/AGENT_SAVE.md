# Save Treasures Runbook

Машиночитаемый процесс для зеркалирования текущего Claude-стека этой машины в
`~/dev/agent-treasures`. Вызывается через skill `save-treasures` или напрямую
любым агентом. Симметричен [`AGENT_RESTORE.md`](AGENT_RESTORE.md) (тот — про
fresh install, этот — про инкрементальное сохранение).

## §1 Discover (read-only)

```
git -C ~/.claude status --short
git -C ~/dev/agent-treasures status --short
```

Если оба пустые — выйди с сообщением «нечего сохранять, snapshot уже актуален».

## §2 Stage в ~/.claude

`snapshot-recipe.sh` зеркалит **только** `git ls-files` — untracked не попадает.
`git -C ~/.claude add <path>` для намеренных артефактов:

| Stage | НЕ stage |
|---|---|
| skills/*/, commands/*.md, agents/*.md | pull.lock, pre-pull-backups/ |
| scripts/*.sh, CLAUDE.md, rules/ | sessions/, projects/, file-history/, shell-snapshots/ |
| settings.json, mcp/ configs | __store.db*, *.log, plugins/data/, ccline/.api_usage_cache.json |

Сомневаешься по конкретному файлу — спроси одной строкой.

## §3 Docs gate (по умолчанию **пропускай**)

Правь docs **только** если изменение меняет flow. Whitelist:

| Изменение | Docs touch |
|---|---|
| меняет порядок/состав шагов install.sh | `INSTALL.md` (таблица шагов) |
| добавляет/удаляет systemd-юнит | `docs/services.md` |
| меняет contract pull/snapshot pipeline | `docs/multi-machine.md` |
| failure mode вне существующих anchor'ов в `troubleshooting.md` | добавь секцию |
| меняет invariant в `98-verify.sh` | синхронизируй anchor в `troubleshooting.md` |
| меняет контракт save-операции | этот файл |

Иначе snapshot сам зеркалит изменения, follower'ы получат через pull. **Не
изобретай docs-update'ы про каждый новый skill/agent/script.**

## §4 Snapshot

```
~/.claude/scripts/snapshot-recipe.sh
```

Скрипт владеет всем: rebase + mirror + normalize + seal-if-changed + commit
(skip если только `versions.lock` churn) + push (3 retry с rebase). Покажи
последние ~10 строк output. Если push не прошёл после retry — commit лежит
локально, сообщи пользователю и не пытайся пушить руками.

## §5 Verify

```
bash ~/dev/agent-treasures/install/lib/98-verify.sh
jq '{status, invariants_failed}' ~/.claude/last-install.json
```

Если `status: "fail"` — назови упавшие invariants и их `troubleshooting.md#<anchor>`.
**Не чини автоматически** — это не задача save-операции.

## §6 Report

Финальный ответ в этой форме:

```
- Staged: <paths или '-'>
- Commit: <SHA> (pushed: yes / no / local-only)
- Docs touched: <files или 'нет'>
- Verify: <ok / fail: invariant-name → anchor>
- Manual TODO: <list или '-'>
```

## §7 Forbidden actions

- `~/.envrc` — не редактируй (regen из sealed bundle через `95-secrets.sh`).
- `git push` руками — `snapshot-recipe.sh` владеет push (race-safe retry).
- `git -C ~/.claude commit` — не нужно, snapshot читает index, commit избыточен.
- `97-tweakcc-apply.sh` — даже если verify его flagнул; это отдельный pending action пользователя.
