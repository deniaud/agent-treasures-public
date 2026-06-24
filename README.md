# agent-treasures

> Reproducible Claude Code сетап: один `install.sh` поднимает рабочую станцию с нуля, hourly systemd-таймер держит несколько машин синхронными через GitHub.

Личный source-of-truth моего стека вокруг Claude Code — агенты, skills, slash-команды, hooks, MCP-сервера, кастомные плагины, плюс shell- и host-обвязка. Репо публикуется как референс: можно растащить идеями, отдельными хуками или install-скриптами, но drop-in для чужого `$HOME` не задумывался — пути, пины и passphrase зашиты под мои машины.

## Что здесь есть

- **Полный `~/.claude` снапшот** — агенты, skills, hooks (`guard-secrets`, `enhance-prompt`, и др.), MCP-конфиги, плагины, slash-команды, `CCometixLine` статусбар, `tweakcc` и `cc-switch` настройки.
- **Host-обвязка** — `.zshrc`/`.zshenv`/`.bashrc` (без плейнтекст-секретов), конфиги для соседних CLI-агентов (Codex CLI, opencode), список VSCode-расширений.
- **Идемпотентный installer** — `install/install.sh` (Linux + macOS), 18 нумерованных шагов с pre-flight, verify и структурированным отчётом `~/.claude/last-install.json` (status / invariants_failed / degraded_reasons). Поддерживает `--dry-run`, `--fresh-auth`, и реран без побочных эффектов.
- **Hourly auto-sync через systemd** — пара таймеров `claude-snapshot.timer` (push на `:00`, jitter ±5 мин) и `claude-pull.timer` (pull на `:30`) держит несколько машин синхронными без ручных вмешательств; 30-минутный лаг даёт push дойти до GitHub до того, как остальные машины начнут pull.
- **Зашифрованные secrets** — AES-256-GPG бандл с passphrase, передаваемой отдельным каналом; восстановление через `install/lib/95-secrets.sh`.
- **Hard floor против leak'а API-ключей** — `permissions.deny` в `settings.json` плюс PreToolUse-хук `guard-secrets.sh`, который перехватывает `Read`/`Edit`/`Write`/`NotebookEdit`/`Bash` по `.env*`, `secrets/`, `credentials.json` и возвращает агенту инструкцию использовать dotenv-loader вместо чтения plaintext.

## Структура

```
.
├── README.md
├── INSTALL.md                       ← пошаговая инструкция для новой машины
├── versions.lock                    ← git-SHA пины для tweakcc, lobotomized-cc, CCometixLine
├── claude/                          ← восстанавливается в $HOME
│   ├── .claude/                     ← agents, skills, hooks, MCP, plugins, scripts
│   ├── .cc-switch/                  ← settings + skills bundle
│   ├── .tweakcc/config.json         ← tweakcc выборы
│   └── .config/systemd/user/        ← claude-snapshot + claude-pull + claude-prune (.service + .timer)
├── host/                            ← восстанавливается в $HOME
│   ├── .zshrc, .zshenv, .bashrc     ← shell без секретов, с claude() wrapper и direnv hook
│   ├── .codex/                      ← config, rules, skills для Codex CLI
│   └── .config/opencode/            ← config, skills, agent для opencode
├── install/
│   ├── install.sh                   ← driver (Linux + macOS)
│   └── lib/*.sh                     ← пронумерованные шаги (00-preflight … 99-post-install)
└── docs/
    ├── AGENT_RESTORE.md             ← machine-readable runbook для AI-агента-исполнителя
    ├── multi-machine.md             ← topology, race-safety, conflict rollback
    ├── troubleshooting.md           ← симптом → команда
    └── manual-steps.md              ← пост-установочный чек-лист
```

## Установка

См. [INSTALL.md](INSTALL.md). TL;DR:

```bash
git clone https://github.com/deniaud/agent-treasures.git ~/dev/agent-treasures
cd ~/dev/agent-treasures
./install/install.sh --dry-run     # посмотреть план
./install/install.sh                # выполнить
```

После прохода `~/.claude/last-install.json` содержит структурированный отчёт. Для AI-агента-исполнителя — отдельный machine-readable runbook: [`docs/AGENT_RESTORE.md`](docs/AGENT_RESTORE.md).

## Чего здесь нет (намеренно)

| Не в репо | Почему |
|---|---|
| Claude Code бинарь | Ставится из `https://claude.ai/install.sh`, версия всегда свежая. |
| `ccline` бинарь | Собирается из исходников `Haleclipse/CCometixLine` через cargo. |
| `~/.tweakcc/native-binary.backup`, `native-claudejs-*.js` | Внутренние артефакты tweakcc, регенерируются при `--apply`. |
| `~/.tweakcc/lobotomized-claude-code/` | Клонируется заново при установке. |
| `cc-prompt-rewriter`, `cc-quote` | Отдельные репозитории, ставятся по pin-SHA из `versions.lock` (steps 55/57). |
| Runtime state (`file-history/`, `sessions/`, `shell-snapshots/`, `history.jsonl`, ...) | Per-machine, регенерируется. |
| Plaintext `.credentials.json` | Опционально в зашифрованном secrets bundle; `--fresh-auth` запускает чистый `claude login`. |

## Как это устроено

Источник правды — сам `$HOME`. Hourly systemd-таймер запускает `~/.claude/scripts/snapshot-recipe.sh`, который:

1. `git fetch origin` + rebase на свежий `main` (race-safe для multi-machine).
2. Зеркалит свежее состояние `~/.claude` и host-конфигов в `{claude,host}/` бакеты — с фильтрацией шумовых полей (timestamp'ы MCP marketplace, codex cache, tweakcc state), иначе hourly commit'ы вырождаются в пустые.
3. Регенерирует `versions.lock` и пере-шифрует secrets bundle только если plaintext реально менялся (sha256 side-car).
4. `git commit + push --with-retry` (3 попытки с jitter, rebase на каждой неудаче).

Если изменений нет — commit пропускается, шторма пустых snapshot'ов не возникает. Пара `claude-snapshot.timer` (`:00`) + `claude-pull.timer` (`:30`) на каждой машине даёт 30-минутный лаг для распространения push'а до GitHub до того, как остальные машины начнут pull. Подробности про race-safety и conflict rollback — [`docs/multi-machine.md`](docs/multi-machine.md).

## Безопасность

- Shell rc-файлы очищены от плейнтекст-секретов; всё мигрировано в `~/.envrc` через direnv.
- Secrets bundle шифруется AES-256 симметрично; passphrase передаётся отдельным каналом, не вместе с репо.
- `install/lib/00-preflight.sh` принудительно делает `chmod 600` на encrypted secrets при каждом install (git хранит mode как `100644` — без этого fresh clone оставляет файлы group-readable).
- snapshot-pipeline передаёт passphrase в gpg через `--passphrase-file` (не `--passphrase`), чтобы значение не светилось в `ps aux` на shared-системах.
- `claude/.claude/hooks/guard-secrets.sh` — PreToolUse hook поверх `permissions.deny` в `settings.json`: перехватывает `Read`/`Edit`/`Write`/`NotebookEdit`/`Bash` по `.env*`, `secrets/`, `credentials.json` и возвращает агенту инструкцию использовать dotenv-loader. Файлы-шаблоны (`*.example`, `*.sample`, `*.template`, `*.dist`, `*.tmpl`, `*.default(s)`, `*.placeholder`) пропускаются по basename. Kill switch: `CC_GUARD_SECRETS_DISABLED=1`.

## Замечание

Personal setup, опубликованный как референс. Скрипты завязаны на конкретные пути (`~/dev/agent-treasures`), pin-SHA отдельных тулов и passphrase, которой публично нет. На свою машину запускать `install.sh` без вычитки `INSTALL.md` и подстановки своих ключей не стоит — проще растащить интересные куски (агенты, skills, hooks, snapshot-recipe) поштучно.
