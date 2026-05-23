---
name: cc-snapshot
description: Rebuild claude-recipe.tar.gz и пушнуть в claude-recipe-snapshots remote
disable-model-invocation: true
stage: proving
---

Запусти `~/.claude/scripts/snapshot-recipe.sh`. Покажи итоговый размер и SHA-256 нового tarball'а. Если push не удался — объясни причину (отсутствует remote? авторизация? отсутствует ~/dev/claude-recipe-snapshots?). Не пробуй чинить молча — отдай решение пользователю.
