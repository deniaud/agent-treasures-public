# manual-steps.md — пост-установочный чек-лист

После `install.sh` остаются вещи, которые расовая полу-автоматика не покрывает.

## Обязательное

- [ ] `exec zsh -l` — перезагрузить shell.
- [ ] `direnv allow ~` — авторизовать `~/.envrc`.
- [ ] `claude --version` — должно отвечать.
- [ ] `claude` → проверить что MCP грузятся (`/mcp`).
- [ ] `~/.claude/ccline/ccline --version` → `ccline 1.1.2`.

## Опциональное

### Плагины

Битые в snapshot'е не сохраняются (только `superpowers`). Если нужны другие:

```
/plugin marketplace install anthropics/claude-plugins-official
/plugin install telegram@claude-plugins-official
/plugin install skill-creator@claude-plugins-official
```

### Remote MCPs

Через `/mcp` UI добавить:
- Notion (OAuth)
- Amplitude (OAuth)
- Google Calendar (OAuth)
- (другие по нужде)

Поскольку remote MCP конфигурируются на стороне claude.ai, в этом репо их нет — они привязаны к аккаунту.

### Tooling сервисы

См. [services.md](services.md). Краткий чек-лист по приоритету:

  - Потом: enable все 4 unit'а

### linger (timers без логина)

```
sudo loginctl enable-linger $USER
```

Иначе `claude-snapshot.timer` и `claude-prune.timer` не сработают пока ты не залогинен.

### off-host backup самого treasures-репо

Этот репо сам по себе — single source of truth. Если он живёт только локально + GitHub private — точка отказа = твой GitHub аккаунт. Добавь второй remote:

```
cd ~/dev/agent-treasures
git remote add backup <gitlab-or-other-url>
git push backup main
# и в snapshot-recipe.sh добавить второй push
```

## Чего НЕ делать

- Не редактируй файлы в `~/.claude/`, `~/.cc-switch/` напрямую и долго — следующий снапшот их переносит в репо, и если ты не закоммитил — потеряешь diff-историю. Workflow: правка → `cd ~/dev/agent-treasures && /snapshot` (или дождись воскресенья) → коммит.
- Не пуш реальный `~/.envrc` в репо. `.gitignore` его блокирует, но проверяй `git status` если редактировал руками.
