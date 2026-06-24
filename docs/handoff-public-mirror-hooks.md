# Handoff: hooks не все выгружаются в public mirror

Контекст для следующей сессии. Эта запись сделана прямо перед `/clear`, до того как контекст обнулится.

## Что устроено сейчас

Сокровищница состоит из двух remote-репо:
- **private** `origin = git@github.com:deniaud/agent-treasures.git` — full snapshot, ежечасно через `claude-snapshot.timer`.
- **public mirror** `public-mirror = git@github.com:deniaud/agent-treasures-public.git` — orphan-коммит, force-push после каждого успешного push в private. Один коммит, generic author `agent-treasures-bot <bot@users.noreply.github.com>` UTC, message `"Snapshot"`. Никаких metadata, истории, scrub-list или main SHA.

Скрипт публикации — функция `publish_to_public_mirror()` в `~/.claude/scripts/snapshot-recipe.sh` (после `push_with_retry`). Делает чистый git plumbing:

```
git read-tree HEAD               → TMP_INDEX
git rm --cached -r -- <path>     для каждого пути из SENSITIVE_FOR_PUBLIC
cat-file | grep -Ev | hash-object для каждой пары из SCRUB_LINES
git write-tree                   → new_tree
git commit-tree                  → orphan commit с generic author/UTC
git push --force public-mirror   → main
```

Два массива конфига scrub'а в начале функции:

- `SENSITIVE_FOR_PUBLIC[]` — pathspec'ы, целиком удаляются из orphan tree.
- `SCRUB_LINES[file]=regex` — drop matching lines внутри файла (через rewriting blob и `update-index --cacheinfo`).

## Задача

Расхождение между источником, private mirror и public mirror в директории `claude/.claude/hooks/`:

| Файл | `~/.claude/hooks/` (источник) | `~/.claude/.git` ls-files | private mirror | public mirror |
|---|---|---|---|---|
| `enhance-prompt.sh` | есть | tracked | есть | **есть** |
| `enhance-prompt.system.md` | есть | tracked | есть | **есть** |
| `enhance-prompt.log` | есть (runtime) | gitignored | нет | нет |
| `guard-secrets.sh` | есть | tracked | есть | **НЕТ** ← bug |
| `guard-secrets.log` | есть (runtime) | gitignored | нет | нет |

Файл `claude/.claude/hooks/guard-secrets.sh` есть в private (зеркалится через `git ls-files` источника), но **не доходит до public** orphan-коммита.

## Гипотезы

1. **Pathspec matching в `git rm --cached -r -- "secrets"`** — массив `SENSITIVE_FOR_PUBLIC` содержит запись `"secrets"` (без слешей) для удаления `secrets/` директории в корне репо. Возможно, git pathspec интерпретирует это шире, чем ожидается, и затрагивает любой path с компонентом `secrets` или substring. Проверить — какой именно pathspec эффект.

2. **GitHub push protection** silently не дропает файлы — он отклоняет весь push, и мы бы видели `repository rule violations` в логе. Последний snapshot прошёл без ошибок. Исключаем.

3. **Что-то в SCRUB_LINES rewriting** — SCRUB_LINES работает per-file через `grep -Ev` и `update-index --cacheinfo`. Если для какого-то pattern `guard-secrets.sh` попадает в `update-index` с **пустым** новым blob (вся файла removed) — git мог бы рассмотреть это как deletion. Но SCRUB_LINES сейчас не содержит этого файла как ключ. Маловероятно — проверить.

4. **Hook guard-secrets.sh сам блокирует bash-команды публикации** — он intercept'ит чтение `.env`/`secrets/`/`credentials.json`. Может мешать каким-то snapshot шагам? Нет — он PreToolUse, действует только в Claude-сессиях, не в systemd service'е, который запускает snapshot. Исключаем.

5. **Symlink/permission issue** — файл `guard-secrets.sh` может быть symlink или иметь spec mode что git хранит особым образом. Проверить `git ls-tree -r HEAD | grep guard-secrets`.

Первая гипотеза самая вероятная. Проверка:

```bash
cd ~/dev/agent-treasures
TMP=$(mktemp)
GIT_INDEX_FILE=$TMP git read-tree HEAD
echo "BEFORE: $(GIT_INDEX_FILE=$TMP git ls-files | wc -l) files"
echo "guard-secrets.sh в индексе: $(GIT_INDEX_FILE=$TMP git ls-files | grep -c guard-secrets || echo 0)"
GIT_INDEX_FILE=$TMP git rm --cached -r --quiet --ignore-unmatch -- "secrets"
echo "AFTER 'secrets' rm: $(GIT_INDEX_FILE=$TMP git ls-files | wc -l) files"
echo "guard-secrets.sh остался: $(GIT_INDEX_FILE=$TMP git ls-files | grep -c guard-secrets || echo 0)"
rm $TMP
```

Если после `git rm --cached -r -- "secrets"` число файлов с guard-secrets обнуляется — гипотеза 1 подтверждается, и `"secrets"` нужно поменять на `:(top)secrets` или `secrets/` чтобы ограничить top-level.

## Полезные пути / команды

- Источник скрипта: `~/.claude/scripts/snapshot-recipe.sh`
- Зеркало скрипта (в репо): `~/dev/agent-treasures/claude/.claude/scripts/snapshot-recipe.sh` — НЕ редактировать, snapshot перепишет с источника.
- Source of truth для `~/.claude/`: его собственный git репо `~/.claude/.git` (фильтрует что зеркалится — see `git ls-files` оттуда).
- Запустить snapshot вручную: `~/.claude/scripts/snapshot-recipe.sh`
- Public URL: https://github.com/deniaud/agent-treasures-public
- Свежий clone public для diff'а:
  ```bash
  AUDIT=/tmp/audit-public; rm -rf $AUDIT
  git clone --quiet https://github.com/deniaud/agent-treasures-public.git $AUDIT
  cd $AUDIT && git ls-tree -r HEAD | grep hooks
  ```

## Что НЕ делать

- Не комитить и не пушить ничего до того как разобрался с причиной — destructive операции на public требуют отдельного подтверждения от пользователя.
- Не отключай claude-snapshot.timer — у пользователя автосинхронизация двух машин.
- Не редактируй `claude/.claude/scripts/snapshot-recipe.sh` в репо напрямую — это зеркало, источник в `~/.claude/scripts/`.

## После фикса

1. Запустить `~/.claude/scripts/snapshot-recipe.sh` вручную.
2. Клонировать public свежий, проверить наличие `claude/.claude/hooks/guard-secrets.sh`.
3. Также проверить что никакие другие нужные файлы не пропали из-за слишком широкого pathspec.
4. Параллельно — пройтись по `git ls-files` источника `~/.claude/` и сверить с git ls-tree public — что-то ещё могло утечь из tracking невзаметно.

## Состояние на момент handoff

- private/main HEAD: см. `git log -1 --format=%H` в `~/dev/agent-treasures`
- public/main HEAD: orphan-коммит `c979033` (Snapshot, agent-treasures-bot, UTC)
- Все 14 категорий leak'ов проверены и удалены (см. предыдущий audit pass).
- Новый GitLab PAT в `~/.envrc` под `GITLAB_TOKEN`, pip.conf через `${GITLAB_TOKEN}` substitution, environment.d удалена. secrets/secrets.env.gpg перешифрован.
