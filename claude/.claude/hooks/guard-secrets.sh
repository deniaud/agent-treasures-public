#!/usr/bin/env bash
# PreToolUse hook: блокирует попытки прочитать/модифицировать файлы с секретами
# (.env, .env*, secrets/, credentials.json) — кроме шаблонов
# (*.example, *.sample, *.template, *.dist, *.tmpl, *.default(s), *.placeholder).
#
# Покрытие:
#   Read / Edit / Write / NotebookEdit — проверка tool_input.file_path.
#   Bash                                — whitespace-split токенов команды,
#                                         для каждого матчящего токена смотрим
#                                         basename и whitelist.
#
# permissions.deny в settings.json остаётся как fail-closed floor для случаев,
# которые regex не покрывает: $(<.env), переменные подстановки, base64-каналы.
#
# Контракт PreToolUse (Claude Code docs):
#   stdin  — JSON с tool_name, tool_input.
#   exit 2 — блокирует tool call, stderr возвращается агенту.
#   exit 0 — пропустить.
#
# Kill switch: CC_GUARD_SECRETS_DISABLED=1.

set -uo pipefail

if [[ "${CC_GUARD_SECRETS_DISABLED:-}" == "1" ]]; then exit 0; fi

HOOKS_DIR="$(cd "$(dirname "$(readlink -f "$0")")" && pwd)"
LOG="$HOOKS_DIR/guard-secrets.log"
log() { printf '[%s] %s\n' "$(date -Iseconds)" "$*" >>"$LOG"; }

payload=$(cat)
tool=$(printf '%s' "$payload" | jq -r '.tool_name // ""')

case "$tool" in
  Read|Edit|Write|NotebookEdit)
    target=$(printf '%s' "$payload" | jq -r '.tool_input.file_path // ""')
    mode="path"
    ;;
  Bash)
    target=$(printf '%s' "$payload" | jq -r '.tool_input.command // ""')
    mode="cmd"
    ;;
  *)
    exit 0
    ;;
esac

[[ -z "$target" ]] && exit 0

# Разделитель компонента для триггера: ^/$ или не-имя-файла символ.
secret_re='(^|[^[:alnum:]_.-])\.env(\.[a-zA-Z0-9_-]+)*($|[^[:alnum:]_.-])|(^|[^[:alnum:]_.-])secrets/|(^|[^[:alnum:]_.-])credentials\.json($|[^[:alnum:]_.-])'
template_re='\.(example|sample|template|tmpl|dist|defaults?|placeholder)$'

if [[ "$mode" == "path" ]]; then
  base=$(basename "$target")
  if [[ "$base" =~ $template_re ]]; then
    exit 0
  fi
  if ! printf '%s' "$target" | grep -qE "$secret_re"; then
    exit 0
  fi
  blocking_token="$target"
else
  blocking_token=""
  IFS_old="$IFS"
  IFS=$' \t\n'
  for tok in $target; do
    [[ -z "$tok" ]] && continue
    if ! printf '%s' "$tok" | grep -qE "$secret_re"; then continue; fi
    bn=$(basename "$tok" 2>/dev/null || printf '%s' "$tok")
    if [[ "$bn" =~ $template_re ]]; then continue; fi
    blocking_token="$tok"
    break
  done
  IFS="$IFS_old"
  [[ -z "$blocking_token" ]] && exit 0
fi

snippet=$(printf '%s' "$target" | head -c 200)
log "BLOCK tool=$tool mode=$mode target=$snippet"

if [[ "$mode" == "path" ]]; then
  cat >&2 << MSG_EOF
guard-secrets: $tool на '$target' заблокирован — это файл с секретами.

Не читай и не модифицируй .env*, secrets/, credentials.json напрямую. Шаблоны
(*.example, *.sample, *.template, *.dist, *.tmpl, *.default(s), *.placeholder)
пропускаются — их можно открывать и править свободно. Чтобы получить значения
переменных в код, используй dotenv-loader языка:
  • Python:  from dotenv import load_dotenv; load_dotenv()
  • Node:    require('dotenv').config()
  • CLI:     dotenv -- <command>
  • direnv:  значения уже в окружении после allow — читай через os.environ /
             process.env.

В deploy/runtime реальные значения уже подставлены платформой — коду достаточно
ссылаться на имена переменных, не на содержимое файла. Если задача требует
*добавить* новую переменную — попроси пользователя дописать строку самому или
объясни, какую именно строку нужно добавить (не вставляй значения сам).
MSG_EOF
else
  cat >&2 << MSG_EOF
guard-secrets: Bash-команда обращается к файлу с секретами — заблокирована.

Команда: $snippet
Блокирующий токен: $blocking_token

Не читай содержимое .env*, secrets/, credentials.json через cat/head/grep/
source и т. п. Шаблоны (*.example, *.sample, *.template, *.dist, *.tmpl,
*.default(s), *.placeholder) пропускаются — их использовать можно.
Чтобы получить значения переменных в процесс, используй стандартный dotenv-
loader языка или утилиту:
  • Python:  from dotenv import load_dotenv; load_dotenv()
  • Node:    require('dotenv').config()
  • CLI:     dotenv -- <your-command>

В deploy/runtime реальные значения уже подставлены платформой — твоему коду
достаточно ссылаться на имена переменных. Если нужно проверить *наличие*
переменной — \${VAR:?missing} или test -n "\$VAR" без вывода значения.
MSG_EOF
fi

exit 2
