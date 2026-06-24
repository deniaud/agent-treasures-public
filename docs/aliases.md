# aliases.md — shell-обвязка для Claude Code

Что добавлено в `host/.zshrc` поверх стока.

## Алиасы профилей MCP

```zsh
alias claude-ui='claude --strict-mcp-config --mcp-config "$HOME/.claude/mcp/playwright.json" "$HOME/.claude/mcp/magic.json" "$HOME/.claude/mcp/context7.json"'
```

- `claude-ui` — запуск Claude Code с минимальным набором MCP для **UI-разработки**: Playwright (для скриншотов/тестов), Magic (UI-генерация компонентов), Context7 (lookup библиотечной документации).

`--strict-mcp-config` отключает MCP из глобального конфига, оставляя только перечисленные явно. Это важно: позволяет иметь "лёгкие" профили без всего навороченного стека.

## Лаунчер `claude-trace` — вьюер трасс сессий

Не zsh-алиас, а исполняемый скрипт `host/.local/bin/claude-trace` (в `~/.local/bin`, уже в PATH) + `.desktop`-ярлык для меню Ubuntu (`host/.local/share/applications/claude-trace.desktop`, имя в меню — **«Claude Trace»**).

```bash
claude-trace        # из консоли
# или: меню приложений → «Claude Trace»
```

- Поднимает Docker-контейнер **claude-code-trace** (образ `claude-code-trace:latest`), монтируя `~/.claude` read-only, и открывает веб-консоль **http://localhost:1421** отдельным app-окном (`google-chrome --app=…`, с откатом на chromium/`xdg-open`).
- Идемпотентен: если контейнер уже запущен — просто открывает; если остановлен (например, после перезагрузки) — стартует; если нет — создаёт. URL/порт зашиты, помнить не нужно.
- Остановить: `docker stop cctrace`. Следующий `claude-trace` поднимет заново.
- Зачем: claude-code-trace ([delexw/claude-code-trace](https://github.com/delexw/claude-code-trace)) — вьюер JSONL-транскриптов сессий Claude Code (диалоги, tool-calls, токены). Образ собирается из его `Dockerfile`; данные читаются only-read.

## Функция `claude()` — авто-reapply tweakcc

```zsh
claude() {
  if [[ "$1" == "update" ]]; then
    command claude "$@" || return $?
    echo "[+] CC updated — re-applying tweakcc..."
    if node "$HOME/dev/tweakcc-fixed/dist/index.mjs" --apply; then
      command claude --version >/dev/null && echo "[ok] tweakcc reapplied + claude smoke-tested"
    else
      echo "[!] tweakcc --apply failed. Minifier may have changed — inspect the patch." >&2
      echo "    Rollback: node $HOME/dev/tweakcc-fixed/dist/index.mjs --restore" >&2
      return 2
    fi
  else
    command claude "$@"
  fi
}
```

Любая команда кроме `claude update` проксируется без изменений. `claude update` бампает CC, и сразу же запускает `tweakcc --apply` против новой минифицированной CC-JS. Если минификатор изменил структуру и патчи не легли — функция выводит инструкцию по откату.

Почему это нужно: `tweakcc-fixed` патчит CC-JS regex'ами против минифицированных форм. Любой Anthropic-обновление CC может сломать паттерн — без авто-reapply ты узнаёшь об этом только когда что-то в CC начинает странно вести себя.

## direnv hook

```zsh
if command -v direnv >/dev/null 2>&1; then
  eval "$(direnv hook zsh)"
fi
```

Подгружает `~/.envrc` каждый раз когда cwd внутри `$HOME`. Все API-keys и токены живут в `.envrc` (0600), `direnv allow ~` авторизует один раз на машину.

## Если пишешь свои алиасы

Добавляй в `host/.zshrc` И коммить в этот репо — иначе следующий снапшот их перезатрёт. Альтернатива: писать в `~/.zshrc.local` и source-нуть из `~/.zshrc`:

```zsh
[ -f "$HOME/.zshrc.local" ] && source "$HOME/.zshrc.local"
```

(сейчас не добавлено — добавь при необходимости).
