# Troubleshooting

Как пользоваться:

```bash
jq -r '.invariants_failed[] | .name + " → " + .hint' ~/.claude/last-install.json
```

Каждый `hint` — anchor в этом документе. Прыжок туда, fix-команда, потом
`bash install/lib/98-verify.sh` для повторной проверки.

Если `last-install.json` отсутствует — install крашнулся до step 98. Прочитай
stdout install.sh, определи failed step number (00-97), и пойди в категорию по
**типу** ошибки, не по номеру шага.

---

## #prereq — missing or stale system tools

Симптомы: `command not found` для curl/git/jq/gpg/tar/rsync/python3/node; `node too old; need >= 20`.

| Tool | Install |
|---|---|
| curl, git, jq, gpg, tar, rsync, python3 | `sudo apt install <tool>` (Linux) / `brew install <tool>` (macOS) |
| node ≥ 20 | `curl -o- https://raw.githubusercontent.com/nvm-sh/nvm/v0.40.1/install.sh \| bash && nvm install --lts` |
| rust toolchain (для ccline build) | `curl --proto '=https' --tlsv1.2 -sSf https://sh.rustup.rs \| sh` |
| build-essential (linker для cargo) | `sudo apt install build-essential` / `xcode-select --install` |
| direnv | Step 60 ставит сам; если не отработал — `bash install/lib/60-direnv.sh` |

После — `bash install/lib/00-preflight.sh` для верификации.

---

## #network — fetch / clone failed

Симптомы: `curl: ... could not resolve host`, `git: connection timed out`, npm/cargo registry timeout.

```bash
ping -c 1 github.com
curl -sI https://github.com | head -1
```

Если оффлайн / VPN / firewall: восстанови сеть, перезапусти `install.sh`. Все шаги идемпотентны — продолжит с того же места.

Корпоративные прокси: убедись что `https_proxy` / `http_proxy` экспортированы в shell перед install.

---

## #perms — file/dir mode wrong

Симптомы: `permission denied`, `rsync: failed to set permissions`, секреты sealed как 0644, ssh ключи доступны другим юзерам.

```bash
# secrets — повторный chmod (step 00 это делает, но если пропустил)
chmod 600 ~/dev/agent-treasures/secrets/*.gpg ~/dev/agent-treasures/secrets/files/*.gpg

# ssh / gnupg — корректные права
chmod 700 ~/.ssh ~/.gnupg
chmod 600 ~/.ssh/id_* ~/.ssh/config 2>/dev/null
find ~/.gnupg -type f -exec chmod 600 {} +

# envrc
chmod 600 ~/.envrc
```

Источник проблемы с .gpg: git хранит mode как `100644`, fresh clone оставляет 0644. `install/lib/00-preflight.sh:37-41` исправляет принудительно — если ты запускал шаги вручную мимо install.sh, могло пропуститься.

---

## #gpg — passphrase / key issues

Симптомы: `gpg: bad passphrase`, `gpg: no secret key`, `Decryption failed: bad key`.

```bash
# Проверить что passphrase-файл есть и читаемый
ls -l ~/claude-recipe-seal-passphrase.txt
# Проверить содержимое (passphrase в одну строку, без newline в конце; trailing \n обычно ок)
wc -l ~/claude-recipe-seal-passphrase.txt  # должно быть 1

# Если passphrase утрачен — запросить у operator'а отдельным каналом.
# Перезапустить расшифровку секретов:
bash install/lib/95-secrets.sh
```

Если "no secret key": используется `--symmetric` (AES256), приватных ключей не нужно — но gpg-agent может закэшировать старый result. Сброс:

```bash
gpgconf --kill gpg-agent
```

---

## #ssh-private — clone приватного репо упал

Симптомы: `git clone git@github.com:...: permission denied (publickey)`.

```bash
# Проверка
ssh -T git@github.com  # ожидается "Hi <user>! You've successfully authenticated"

# Если нет ключа — добавить
ssh-add ~/.ssh/id_ed25519       # или другой ключ
# или сгенерировать и закинуть pubkey в GitHub
ssh-keygen -t ed25519 -f ~/.ssh/id_ed25519 -N ""
cat ~/.ssh/id_ed25519.pub
```

agent-treasures сам публичен/приватен по своему remote — но шаги 30/40 могут клонить **приватные** `skrabe/tweakcc-fixed`, `skrabe/lobotomized-claude-code` (зависит от настройки `versions.lock`). Если у тебя нет доступа — запросить.

---

## #npm — npm install / build failures

Симптомы: `npm ERR! ERESOLVE`, `package-lock.json mismatch`, `error TS1234`, `Cannot find module`, отсутствует `dist/index.mjs`.

```bash
# Чистый пересбор зависимостей
cd ~/dev/tweakcc-fixed && rm -rf node_modules package-lock.json && npm install && npm run build

# То же для MCP пакетов
cd ~/.claude/mcp && rm -rf node_modules package-lock.json && npm install

# Если ERESOLVE упорствует — legacy peer deps как last resort
npm install --legacy-peer-deps
```

TypeScript build падает с обычно с устаревшим node. Перепроверь: `node --version` ≥ 20.

---

## #build — cargo / rustup compile errors

Симптомы: `linker 'cc' not found`, `cargo: command not found`, `error: cannot find linker`, бинарь с другой архитектурой.

```bash
# rustup отсутствует
curl --proto '=https' --tlsv1.2 -sSf https://sh.rustup.rs | sh
source "$HOME/.cargo/env"

# Linker / build-tools отсутствуют
sudo apt install build-essential        # Linux
xcode-select --install                  # macOS

# Архитектура (бинарь сборан под другую):
uname -m   # сравни с ARCH, которую экспортирует install.sh
# Пересобрать
cd ~/dev/CCometixLine && cargo clean && cargo build --release
```

После — `bash install/lib/50-ccometixline.sh` для деплоя бинаря в `~/.claude/ccline/`.

---

## #systemd — timer not active

Симптомы: `claude-snapshot.timer / claude-pull.timer / claude-prune.timer` не `active` в `systemctl --user is-active`.

```bash
# Перезагрузить unit-файлы и включить
systemctl --user daemon-reload
systemctl --user enable --now claude-snapshot.timer claude-pull.timer claude-prune.timer

# Посмотреть когда сработают
systemctl --user list-timers claude-*

# Журнал конкретного юнита
journalctl --user -u claude-snapshot.service -n 50 --no-pager
```

Если `Linger=no` (degraded, не fail) — таймеры умирают при logout. Для headless:

```bash
sudo loginctl enable-linger $USER
```

Если контейнер без systemd — install с `--skip-systemd`. Тогда snapshot/pull не работают автоматически; нужен внешний планировщик.

---

## #symlinks — skill symlinks broken

Симптомы: `ls -L ~/.claude/skills/<name>: No such file or directory`, `ENOENT: no such file or directory`.

```bash
# Пересоздать все skill symlinks
bash install/lib/85-skill-symlinks.sh

# Проверить конкретный
ls -L ~/.claude/skills/<name>
readlink ~/.claude/skills/<name>
```

Если target в `~/.cc-switch/skills/<name>` отсутствует — он не пришёл с snapshot'а. Запустить `/pull-treasures` чтобы получить свежий state из origin.

`~/.tweakcc/system-prompts` должен быть symlink на `~/.tweakcc/lobotomized-claude-code/system-prompts`. Если нет:

```bash
bash install/lib/40-lobotomized.sh
```

---

## #tweakcc — config не применён

Симптомы: `~/.tweakcc/config.json` имеет `changesApplied: false` или `ccInstallationPath: null`.

```bash
# Применить tweakcc-патчи
bash install/lib/97-tweakcc-apply.sh

# Если падает — посмотреть детали
node ~/dev/tweakcc-fixed/dist/index.mjs --apply

# Откат (если что-то пошло не так)
node ~/dev/tweakcc-fixed/dist/index.mjs --restore
```

Если паттерн в Claude Code изменился (после обновления CC) — нужна свежая версия `tweakcc-fixed`. Проверить `git -C ~/dev/tweakcc-fixed log -5`.

---

## #drift — post-install state changed

Симптомы: 98-verify был OK ранее, теперь `last-install.json` имеет failures (но машина не переустанавливалась).

Возможные причины: claude обновился (`claude update`), tweakcc откатился, файл удалён вручную, права изменены, репо разъехался с пином.

```bash
# Полный re-verify
bash install/lib/98-verify.sh

# Если конкретный invariant — запустить соответствующий step:
bash install/lib/<NN>-<name>.sh

# Полная переустановка идемпотентна
bash install/install.sh
```

После `claude update`: обычно tweakcc откатывается. Решение: `bash install/lib/97-tweakcc-apply.sh`. Wrapper-функция `claude()` в `.zshrc` делает это автоматически.

---

## #pull-conflict — divergence on pull

Симптомы: `pull-recipe.sh` выходит с exit code 4 ("local treasures repo has diverged from origin/main").

Причина: local treasures репо имеет коммиты, которых нет на origin (например предыдущий snapshot не был запушен).

```bash
# 1. Запушить local commits
~/.claude/scripts/snapshot-recipe.sh

# 2. Повторить pull
~/.claude/scripts/pull-recipe.sh
```

Если конфликт rebase (одновременный snapshot с двух машин): snapshot-recipe сам делает retry с rebase. После 3 неудач commit лежит локально (см. `cleanup.log`). Resolve вручную через `git -C ~/dev/agent-treasures rebase origin/main`, потом `git push`.

См. [`multi-machine.md`](multi-machine.md#race-conditions) для деталей.
