---
name: tweakcc-apply
description: Переапплай tweakcc-fixed после обновления Claude Code
disable-model-invocation: true
stage: raw
---

После того как `claude update` выкатил новую версию CC, минификатор может сломать tweakcc-патчи. Этот workflow:

1. Прогони `node ~/dev/tweakcc-fixed/dist/index.mjs --apply`.
2. Если apply прошёл — `claude --version` для smoke-теста.
3. Если apply упал — собери диагностику:
   - последние 30 строк вывода apply;
   - текущее значение `ccVersion` из `~/.tweakcc/config.json`;
   - `claude --version` (какая CC активна);
   - последний commit `git -C ~/dev/tweakcc-fixed rev-parse HEAD`.

Предложи откат через `--restore`. Не правь патчи сам — это ручная работа с минифицированным CC-JS.
