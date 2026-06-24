#!/usr/bin/env python3
"""Stop hook: ретроспективный нудж о пропущенном делегировании (CLAUDE.md §3).

Идея (из обсуждения с пользователем): главный контекст — самый дефицитный
ресурс. Серийное «прочитаю сам» втягивает в него килобайты выводов, тогда как
широкий поиск — кандидат на Explore/researcher. Pre-call порог по числу вызовов
шумит на дешёвом пути (три `ls`, один греп три раза). Поэтому:

  • метрика — НЕ количество вызовов, а ОБЪЁМ выводов READ-тулов, втянутый в
    контекст за ход, И разброс (distinct targets). Дешёвый путь не копит объём →
    не срабатывает ПО ПОСТРОЕНИЮ, без эвристик «простое/сложное».
  • момент — ретроспективный (Stop), не pre-call: ноль ложных срабатываний в
    полёте, учит между ходами.
  • механизм — hookSpecificOutput.additionalContext (allow-stop, впрыск контекста
    к следующему ходу), НЕ decision:block (тот форсировал бы лишний ход сейчас).
    Allow-stop → нет риска петли.

Срабатывает, только если ВСЕ условия:
  approx_tokens(READ-выводы за ход) >= TOKEN_MIN
  AND distinct_targets >= DISTINCT_MIN
  AND делегирования в ходе НЕ было (нет Agent/Task tool_use и нет sidechain)

Два измерения вместе: один большой нужный файл (1 target) не сработает; пачка
мелких грепов (низкий объём) не сработает; срабатывает только широкое тяжёлое
ручное чтение. Per-turn guard не даёт дублировать на повторных Stop того же хода.

Kill switch: CC_DELEGATION_NUDGE_DISABLED=1.
"""

import json
import os
import sys
from pathlib import Path

# ── Пороги (тюнятся здесь). Старт консервативный — доверие к хуку дороже охвата.
TOKEN_MIN = 30_000        # ≈120k символов выводов READ-тулов за ход
DISTINCT_MIN = 8          # разных файлов/паттернов — это fan-out, не точечный lookup
CHARS_PER_TOKEN = 4       # грубая аппроксимация символы→токены

READ_TOOLS = {"Read", "Grep", "Glob", "NotebookRead"}
DELEGATION_TOOLS = {"Agent", "Task"}

HOOK_DIR = Path(__file__).resolve().parent
STATE_FILE = HOOK_DIR / ".delegation-nudge.state"
LOG_FILE = HOOK_DIR / "delegation-nudge.log"


def log(msg: str) -> None:
    try:
        with LOG_FILE.open("a") as f:
            f.write(msg + "\n")
    except Exception:
        pass


def content_len(content) -> int:
    """Длина текстового тела tool_result (str или список блоков)."""
    if isinstance(content, str):
        return len(content)
    if isinstance(content, list):
        total = 0
        for block in content:
            if isinstance(block, dict):
                t = block.get("text")
                if isinstance(t, str):
                    total += len(t)
                elif isinstance(block.get("content"), (str, list)):
                    total += content_len(block.get("content"))
            elif isinstance(block, str):
                total += len(block)
        return total
    return 0


def is_user_prompt(entry: dict) -> bool:
    """Настоящий промпт пользователя — делимитер начала хода.

    Не sidechain, не meta, type=user, и в content нет tool_result.
    """
    if entry.get("type") != "user":
        return False
    if entry.get("isSidechain") or entry.get("isMeta"):
        return False
    msg = entry.get("message") or {}
    content = msg.get("content")
    if isinstance(content, str):
        return content.strip() != ""
    if isinstance(content, list):
        if not content:
            return False
        for block in content:
            if isinstance(block, dict) and block.get("type") == "tool_result":
                return False
        return True
    return False


def main() -> int:
    if os.environ.get("CC_DELEGATION_NUDGE_DISABLED") == "1":
        return 0

    try:
        payload = json.load(sys.stdin)
    except Exception:
        return 0

    transcript_path = payload.get("transcript_path")
    if not transcript_path or not os.path.isfile(transcript_path):
        return 0

    try:
        with open(transcript_path) as f:
            lines = [json.loads(ln) for ln in f if ln.strip()]
    except Exception:
        return 0

    if not lines:
        return 0

    # Найти начало текущего хода — индекс последнего настоящего промпта юзера.
    turn_start = None
    turn_key = None
    for i, entry in enumerate(lines):
        if isinstance(entry, dict) and is_user_prompt(entry):
            turn_start = i
            turn_key = entry.get("uuid") or f"idx:{i}:{entry.get('timestamp', '')}"
    if turn_start is None:
        return 0

    turn = lines[turn_start + 1:]

    # id→имя тула из assistant tool_use; объём tool_result по READ-тулам;
    # breadth (distinct targets); признак делегирования.
    id_to_tool = {}
    distinct_targets = set()
    delegated = False

    for entry in turn:
        if not isinstance(entry, dict):
            continue
        if entry.get("isSidechain"):
            delegated = True  # ход породил субагентскую ветку → делегирование было
            continue
        msg = entry.get("message") or {}
        content = msg.get("content")
        if not isinstance(content, list):
            continue
        for block in content:
            if not isinstance(block, dict):
                continue
            btype = block.get("type")
            if btype == "tool_use":
                name = block.get("name", "")
                if name in DELEGATION_TOOLS:
                    delegated = True
                if name in READ_TOOLS:
                    bid = block.get("id")
                    if bid:
                        id_to_tool[bid] = name
                    inp = block.get("input") or {}
                    tgt = (inp.get("file_path") or inp.get("path")
                           or inp.get("pattern") or inp.get("notebook_path"))
                    if tgt:
                        distinct_targets.add(f"{name}:{tgt}")

    if delegated:
        return 0

    read_chars = 0
    for entry in turn:
        if not isinstance(entry, dict) or entry.get("isSidechain"):
            continue
        msg = entry.get("message") or {}
        content = msg.get("content")
        if not isinstance(content, list):
            continue
        for block in content:
            if isinstance(block, dict) and block.get("type") == "tool_result":
                if id_to_tool.get(block.get("tool_use_id")):
                    read_chars += content_len(block.get("content"))

    approx_tokens = read_chars // CHARS_PER_TOKEN
    n_targets = len(distinct_targets)

    if approx_tokens < TOKEN_MIN or n_targets < DISTINCT_MIN:
        return 0

    # Per-turn guard — не дублировать на повторных Stop того же хода.
    try:
        prev = json.loads(STATE_FILE.read_text()) if STATE_FILE.exists() else {}
    except Exception:
        prev = {}
    if prev.get("last_fired_turn_key") == turn_key:
        return 0
    try:
        STATE_FILE.write_text(json.dumps({"last_fired_turn_key": turn_key}))
    except Exception:
        pass

    log(f"FIRE turn={turn_key} ~{approx_tokens}tok targets={n_targets}")

    reason = (
        f"Ретроспектива делегирования (CLAUDE.md §3): этот ход втянул в главный "
        f"контекст ~{approx_tokens // 1000}k токенов выводов READ-тулов по "
        f"{n_targets} разным целям, без делегирования.\n"
        f"Главный контекст — самый дефицитный ресурс. Если это был ОТКРЫТЫЙ "
        f"поиск (что где лежит, как что названо) — в следующий раз это кандидат "
        f"на Explore/researcher: они возвращают вывод, а не дамп файлов.\n"
        f"Если это было НЕОБХОДИМОЕ точечное чтение конкретных файлов под правку "
        f"— игнорируй, всё верно. Решение за тобой; коротко отметь, чем это было.\n"
        f"(Заглушить: CC_DELEGATION_NUDGE_DISABLED=1)"
    )

    out = {
        "hookSpecificOutput": {
            "hookEventName": "Stop",
            "additionalContext": reason,
        }
    }
    print(json.dumps(out))
    return 0


if __name__ == "__main__":
    try:
        sys.exit(main())
    except Exception:
        # Хук НИКОГДА не должен ломать сессию.
        sys.exit(0)
