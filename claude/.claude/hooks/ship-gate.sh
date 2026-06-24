#!/usr/bin/env bash
# PreToolUse hook: ship-gate — speed bump перед publish/release/deploy.
# Энфорсит CLAUDE.md §4: непроверенное *изменённое поведение* не идёт в релиз.
# Зелёные build/lint/tsc/dry-run/node --check — НЕ доказательство, что
# поведение работает (см. cc-quote: мёртвый фикс уехал в релиз дважды на
# parse-level зелёном).
#
# Контракт PreToolUse (Claude Code docs):
#   stdin  — JSON с tool_name, tool_input.
#   exit 2 — блокирует tool call, stderr возвращается агенту.
#   exit 0 — пропустить.
#
# Поведение: блокирует распознанные ship-команды с напоминанием прогнать
# реальный путь. Чтобы продолжить, агент переподаёт ту же команду с
# префиксом-аттестацией SHIP_GATE_ACK=1 — осознанный чекпойнт, что поведение
# проверено (или релиз сознательно provisional).
#
# Kill switch: CC_SHIP_GATE_DISABLED=1.

set -uo pipefail
[[ "${CC_SHIP_GATE_DISABLED:-}" == "1" ]] && exit 0

HOOKS_DIR="$(cd "$(dirname "$(readlink -f "$0")")" && pwd)"
LOG="$HOOKS_DIR/ship-gate.log"
log() { printf '[%s] %s\n' "$(date -Iseconds)" "$*" >>"$LOG" 2>/dev/null || true; }

payload=$(cat)
tool=$(printf '%s' "$payload" | jq -r '.tool_name // ""')
[[ "$tool" != "Bash" ]] && exit 0
cmd=$(printf '%s' "$payload" | jq -r '.tool_input.command // ""')
[[ -z "$cmd" ]] && exit 0

# Уже аттестовано → пропустить.
if printf '%s' "$cmd" | grep -qE '(^|[^[:alnum:]_])SHIP_GATE_ACK=1([^[:alnum:]]|$)'; then
  log "ACK allow: $(printf '%s' "$cmd" | head -c 120)"
  exit 0
fi

# Распознанные команды публикации/релиза/деплоя.
ship_re='(^|[^[:alnum:]_./-])(npm|pnpm|yarn|bun)[[:space:]]+publish([^[:alnum:]]|$)'
ship_re+='|(^|[^[:alnum:]_./-])gh[[:space:]]+release[[:space:]]+create([^[:alnum:]]|$)'
ship_re+='|(^|[^[:alnum:]_./-])cargo[[:space:]]+publish([^[:alnum:]]|$)'
ship_re+='|(^|[^[:alnum:]_./-])twine[[:space:]]+upload([^[:alnum:]]|$)'
ship_re+='|(^|[^[:alnum:]_./-])docker[[:space:]]+push([^[:alnum:]]|$)'
ship_re+='|git[[:space:]]+push[[:space:]].*--tags'
ship_re+='|(^|[^[:alnum:]_./-])(vercel|netlify|fly|wrangler)[[:space:]]+(deploy|publish)([^[:alnum:]]|$)'

if ! printf '%s' "$cmd" | grep -qE "$ship_re"; then exit 0; fi

snippet=$(printf '%s' "$cmd" | head -c 200)
log "BLOCK ship cmd: $snippet"

cat >&2 << 'MSG_EOF'
ship-gate: команда публикации/релиза/деплоя приостановлена (CLAUDE.md §4).

Зелёные build / lint / tsc / dry-run / `node --check` — это НЕ доказательство,
что изменённое поведение работает (см. cc-quote: мёртвый фикс уехал в релиз
дважды на parse-level зелёном).

Прежде чем катить, ответь честно:
  • Я ПРОГНАЛ сам изменённый путь (не сборку/линт, а реальное поведение)?
  • Если прогнать может только человек/интерактив (TUI, fresh-host) — он это
    сделал, либо релиз помечается provisional, а не «готово».

Если поведение реально проверено (или релиз сознательно provisional) —
повтори ту же команду с префиксом-аттестацией:
    SHIP_GATE_ACK=1 <твоя-команда>

Полностью отключить гейт: CC_SHIP_GATE_DISABLED=1.
MSG_EOF
exit 2
