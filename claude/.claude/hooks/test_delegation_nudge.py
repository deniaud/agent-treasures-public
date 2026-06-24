#!/usr/bin/env python3
"""Standalone-тест delegation-nudge.py на синтетических транскриптах.

Запуск: python3 hooks/test_delegation_nudge.py
Проверяет: дешёвый путь молчит, большой одиночный файл молчит, широкое тяжёлое
чтение срабатывает, делегирование глушит, sidechain глушит, повтор хода не дублит.
"""
import json
import os
import subprocess
import sys
import tempfile

HOOK = os.path.join(os.path.dirname(os.path.abspath(__file__)), "delegation-nudge.py")


def uprompt(uuid, text="сделай вещь"):
    return {"type": "user", "uuid": uuid, "message": {"role": "user", "content": text}}


def read_call(tid, path, name="Read"):
    return {"type": "assistant", "uuid": "a" + tid,
            "message": {"role": "assistant",
                        "content": [{"type": "tool_use", "id": tid, "name": name,
                                     "input": {"file_path": path}}]}}


def grep_call(tid, pattern):
    return {"type": "assistant", "uuid": "a" + tid,
            "message": {"role": "assistant",
                        "content": [{"type": "tool_use", "id": tid, "name": "Grep",
                                     "input": {"pattern": pattern}}]}}


def agent_call(tid):
    return {"type": "assistant", "uuid": "a" + tid,
            "message": {"role": "assistant",
                        "content": [{"type": "tool_use", "id": tid, "name": "Agent",
                                     "input": {"description": "explore"}}]}}


def result(tid, nchars):
    return {"type": "user", "uuid": "r" + tid,
            "message": {"role": "user",
                        "content": [{"type": "tool_result", "tool_use_id": tid,
                                     "content": "x" * nchars}]}}


def sidechain_line():
    return {"type": "user", "uuid": "sc1", "isSidechain": True,
            "message": {"role": "user", "content": "subagent work"}}


def run(lines, state_reset=True):
    state = os.path.join(os.path.dirname(HOOK), ".delegation-nudge.state")
    if state_reset and os.path.exists(state):
        os.remove(state)
    with tempfile.NamedTemporaryFile("w", suffix=".jsonl", delete=False) as tf:
        for ln in lines:
            tf.write(json.dumps(ln) + "\n")
        tpath = tf.name
    payload = json.dumps({"transcript_path": tpath, "hook_event_name": "Stop",
                          "session_id": "test"})
    proc = subprocess.run([sys.executable, HOOK], input=payload,
                          capture_output=True, text=True)
    os.unlink(tpath)
    fired = bool(proc.stdout.strip())
    return fired, proc.stdout.strip()


def build_turn(uuid, reads):
    """reads: список (tid, target, nchars[, name])."""
    lines = [uprompt(uuid)]
    for r in reads:
        tid, target, nchars = r[0], r[1], r[2]
        name = r[3] if len(r) > 3 else "Read"
        if name == "Grep":
            lines.append(grep_call(tid, target))
        else:
            lines.append(read_call(tid, target, name))
        lines.append(result(tid, nchars))
    return lines


def main():
    results = []

    # (a) дешёвый путь: 3 однострочных грепа → молчит
    a = [uprompt("u_a")]
    for i in range(3):
        a.append(grep_call(f"t{i}", f"foo{i}"))
        a.append(result(f"t{i}", 80))
    fired, _ = run(a)
    results.append(("(a) дешёвый путь (3 мелких грепа)", fired, False))

    # (b) один большой файл: 1 target, ~200k символов → молчит (breadth=1)
    b = build_turn("u_b", [("t0", "/x/huge.py", 200_000)])
    fired, _ = run(b)
    results.append(("(b) один большой файл (breadth=1)", fired, False))

    # (c) широкое тяжёлое чтение: 10 файлов × 15k символов ≈ 37k токенов → срабатывает
    reads = [(f"t{i}", f"/x/f{i}.py", 15_000) for i in range(10)]
    c = build_turn("u_c", reads)
    fired, out = run(c)
    results.append(("(c) широкое тяжёлое чтение (10 файлов, ~37k tok)", fired, True))
    c_out = out

    # (d) то же + Agent в ходе → молчит (делегирование было)
    d = build_turn("u_d", reads)
    d.insert(1, agent_call("tA"))
    fired, _ = run(d)
    results.append(("(d) широкое чтение + Agent (делегировал)", fired, False))

    # (e) то же + sidechain-ветка → молчит
    e = build_turn("u_e", reads)
    e.insert(1, sidechain_line())
    fired, _ = run(e)
    results.append(("(e) широкое чтение + sidechain", fired, False))

    # (f) per-turn guard: тот же ход (c) дважды подряд без сброса state
    run(c)  # первый раз — fire, пишет state
    fired_again, _ = run(c, state_reset=False)
    results.append(("(f) повтор того же хода → не дублирует", fired_again, False))

    # (g) граница: 7 файлов (< DISTINCT_MIN=8) но большой объём → молчит
    reads7 = [(f"t{i}", f"/x/g{i}.py", 30_000) for i in range(7)]
    g = build_turn("u_g", reads7)
    fired, _ = run(g)
    results.append(("(g) 7 файлов < порога breadth", fired, False))

    print("\n=== delegation-nudge: тесты ===")
    ok = True
    for name, fired, expected in results:
        status = "PASS" if fired == expected else "FAIL"
        if fired != expected:
            ok = False
        print(f"  [{status}] {name}: fired={fired} (ожидалось {expected})")

    if c_out:
        print("\n--- пример нудж-вывода (кейс c) ---")
        print(json.dumps(json.loads(c_out), ensure_ascii=False, indent=2))

    print("\n" + ("ВСЕ ТЕСТЫ ПРОШЛИ" if ok else "ЕСТЬ ПРОВАЛЫ"))
    return 0 if ok else 1


if __name__ == "__main__":
    sys.exit(main())
