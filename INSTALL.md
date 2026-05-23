# INSTALL — развёртывание agent-treasures на новой машине

Цель: за один проход получить рабочий Claude Code стек идентичный source-машине.

## 0. Предусловия

Машина должна быть:

- Linux (Debian/Ubuntu семейство — apt) или macOS;
- Node.js ≥ 20 (рекомендую через nvm — `curl -o- https://raw.githubusercontent.com/nvm-sh/nvm/master/install.sh | bash`);
- `git`, `curl`, `jq`, `gpg`, `tar`, `rsync`, `python3` — обычно есть, иначе `sudo apt install …`;
- Zsh (опционально, но `host/.zshrc` рассчитан на zsh; bash работает с минимальными правками).

Полезно: `sudo loginctl enable-linger $USER` — чтобы systemd user timers крутились без логина.

## 1. Клонировать репо

```bash
git clone <git@github.com:you/agent-treasures.git> ~/dev/agent-treasures
cd ~/dev/agent-treasures
```

## 2. Положить passphrase для секретов

`secrets/secrets.env.gpg` зашифрован отдельным паролем. Получи его другим каналом (1Password / Bitwarden / Telegram-к-себе) и сохрани в файл *одной строкой*:

```bash
echo 'your-passphrase-here' > ~/claude-recipe-seal-passphrase.txt
chmod 600 ~/claude-recipe-seal-passphrase.txt
```

(или вводи интерактивно при запросе gpg — установщик попросит)

## 3. Запустить установщик

Сначала dry-run:
```bash
./install/install.sh --dry-run
```

Изучи план — каждый шаг печатает что бы он сделал. Если устраивает:

```bash
./install/install.sh
```

Что произойдёт по шагам:

| # | Шаг | Что делает |
|---|---|---|
| 00 | preflight | проверяет тулзы |
| 10 | claude-code | `curl claude.ai/install.sh \| bash` если CC не установлен |
| 20 | cc-switch | `sudo apt install` `.deb` из github-релиза |
| 30 | tweakcc-fixed | клонирует `skrabe/tweakcc-fixed` на пин-SHA + `npm install + npm run build` |
| 40 | lobotomized | клонирует `skrabe/lobotomized-claude-code`, создаёт symlinks system-prompts/system-reminders |
| 50 | ccometixline | rustup (если нет) + клон `Haleclipse/CCometixLine` + `cargo build --release` |
| 55 | cc-prompt-rewriter | клон `deniaud/cc-prompt-rewriter` + запуск его `install.sh` (копирует hook, мерджит settings.json, кладёт patch в tweakcc-fixed); ребилдит tweakcc-fixed если patch зарегистрирован в `src/patches/index.ts` |
| 57 | cc-quote | клон `deniaud/cc-quote` + `pnpm/npm i -g cc-quote@<ver>` + `cc-quote apply` (патчит CC binary, бэкап в `~/.cc-quote/`) |
| 60 | direnv | ставит binary release direnv в ~/.local/bin/direnv |
| 70 | mcp-packages | `cd ~/.claude/mcp && npm ci` (после apply-home) |
| 80 | apply-home | `rsync claude/ + host/ ~/` с бэкапом существующих файлов в *.pre-install.<TS>.bak |
| 85 | skill-symlinks | пересоздаёт ~/.claude/skills/* симлинки на ~/.cc-switch/skills/<name> |
| 90 | systemd | `systemctl --user daemon-reload + enable claude-snapshot.timer claude-pull.timer claude-prune.timer` (см. `install/lib/90-systemd.sh:7`) |
| 95 | secrets | gpg decrypt + ~/.envrc + опционально ~/.claude/.credentials.json |
| 97 | tweakcc apply | `node ~/dev/tweakcc-fixed/dist/index.mjs --apply` |
| 98 | verify | 25 постусловных проверок → `~/.claude/last-install.json` (status, invariants_failed[], degraded_reasons[]) |
| 99 | post-install | памятка ручных шагов |

### `~/.claude/last-install.json`

Step 98 пишет структурированный отчёт. Полезные one-liner'ы:

```bash
jq .status ~/.claude/last-install.json                   # "ok" | "fail" | "dry-run"
jq -r '.invariants_failed[] | .name + " → " + .hint' ~/.claude/last-install.json
jq -r '.degraded_reasons[]' ~/.claude/last-install.json
```

`status == "fail"` — exit code 1, но install.sh не валится: см. `docs/troubleshooting.md` за соответствующим anchor'ом из `hint`.

## 4. Ручные шаги (см. install/lib/99-post-install.sh для актуального списка)

1. Открыть свежий zsh: `exec zsh -l`
2. Активировать direnv: `cd ~ && direnv allow .`
3. `claude` — если без `--fresh-auth`, креды уже на месте, иначе залогиниться
4. Re-add optional plugins:
   ```
   /plugin install telegram@claude-plugins-official
   /plugin install skill-creator@claude-plugins-official
   ```
5. Remote MCPs (если нужны) — через `/mcp` UI
   ```
   # и т. д.
   ```

## 5. Опции install.sh

- `--dry-run` — посмотреть план
- `--fresh-auth` — не восстанавливать `.credentials.json`; залогиниться заново
- `--skip-build` — пропустить cargo build (используется только если ccline уже есть)
- `--skip-secrets` — не декриптить secrets
- `--skip-systemd` — не ставить timers (полезно в контейнерах без systemd)

## 6. Откат

`install.sh` бэкапит каждый существующий файл в `*.pre-install.<UTC>.bak` перед перезаписью. Восстановить:

```bash
# Найти бэкапы
find ~ -name '*.pre-install.*.bak' 2>/dev/null
# Откатить конкретный файл
mv ~/.zshrc.pre-install.20260516T080000Z.bak ~/.zshrc
```

## 7. Если что-то упало

1. Прочитай `~/.claude/last-install.json` (или его отсутствие = крах до step 98).
2. Для каждого `invariants_failed[].hint` — открой соответствующий anchor в [`docs/troubleshooting.md`](docs/troubleshooting.md).
3. Исправь, перезапусти конкретный step (`bash install/lib/XX-name.sh`) или весь `install.sh` (идемпотентен).
4. После — `bash install/lib/98-verify.sh` для повторной проверки.

AI-агенту-исполнителю: следуй runbook'у в [`docs/AGENT_RESTORE.md`](docs/AGENT_RESTORE.md) — там decision tree и forbidden actions.
