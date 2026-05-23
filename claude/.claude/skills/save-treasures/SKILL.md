---
name: save-treasures
description: Зеркалит текущее состояние Claude-сборки в agent-treasures и пушит в origin.
disable-model-invocation: true
stage: proving
---

# Save treasures

Пользователь импрувнул свою агентную сборку и хочет сохранить изменения в
single-source-of-truth репо `~/dev/agent-treasures` и распространить на остальные
машины через ежечасный pull.

Не действуй по памяти — **прочитай `~/dev/agent-treasures/docs/AGENT_SAVE.md`** и
следуй ему. Этот документ обновляется вместе с pipeline и всегда отражает
актуальный процесс. Финальный отчёт — по форме из §6 runbook'а.
