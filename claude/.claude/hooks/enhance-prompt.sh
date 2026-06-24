#!/usr/bin/env bash
# UserPromptSubmit hook: when the user prefixes their request with `~`, rewrite it
# via a fast LLM and return the enhanced version as additionalContext. Without the
# prefix the hook is a no-op. The `~` prefix is stripped before being sent to the
# rewriter (mirroring how single `!` triggers bash mode without going into the command).
#
# Env knobs (all optional):
#   CC_ENHANCE_API_KEY    OpenRouter API key (falls back to OPENROUTER_API_KEY)
#   CC_ENHANCE_MODEL      Model id (default: deepseek/deepseek-v4-flash)
#   CC_ENHANCE_ENDPOINT   Override API endpoint (default: OpenRouter chat completions)
#   CC_ENHANCE_DISABLED   If set to "1", hook is a no-op (kill switch)
#
# Trigger and skips:
#   no `~` prefix                 → bypass (default off)
#   `~` + slash command           → bypass
#   `~` + (len > 200 chars)       → bypass  (measured after stripping `~`)

set -uo pipefail

HOOKS_DIR="$(cd "$(dirname "$(readlink -f "$0")")" && pwd)"
LOG="$HOOKS_DIR/enhance-prompt.log"
SYS_PROMPT_FILE="$HOOKS_DIR/enhance-prompt.system.md"

log() { printf '[%s] %s\n' "$(date -Iseconds)" "$*" >>"$LOG"; }

# --- kill switch ---
if [[ "${CC_ENHANCE_DISABLED:-}" == "1" ]]; then exit 0; fi

# --- read hook payload from stdin ---
payload=$(cat)
prompt=$(printf '%s' "$payload" | jq -r '.prompt // ""')

# Entry trace — fires for EVERY invocation so we can prove the hook ran at all.
log "ENTRY len=${#prompt} first=$(printf '%s' "$prompt" | head -c 3 | sed 's/./[&]/g')"

# --- trigger: only act on prompts starting with `~` ---
[[ -z "$prompt" ]] && exit 0
if [[ "${prompt:0:1}" != "~" ]]; then exit 0; fi

# Strip the `~` marker and one optional leading space.
prompt_clean="${prompt#"~"}"
prompt_clean="${prompt_clean# }"

[[ -z "$prompt_clean" ]] && { log "SKIP empty-after-marker"; exit 0; }
if [[ "$prompt_clean" == /* ]]; then
  log "SKIP slash-after-marker"
  exit 0
fi

len=$(printf '%s' "$prompt_clean" | wc -m)
if (( len > 200 )); then
  log "SKIP len=$len (>200)"
  exit 0
fi

# --- API key ---
api_key="${CC_ENHANCE_API_KEY:-${OPENROUTER_API_KEY:-}}"
if [[ -z "$api_key" ]]; then
  log "SKIP no-api-key (set CC_ENHANCE_API_KEY or OPENROUTER_API_KEY)"
  exit 0
fi

model="${CC_ENHANCE_MODEL:-deepseek/deepseek-v4-flash}"
endpoint="${CC_ENHANCE_ENDPOINT:-https://openrouter.ai/api/v1/chat/completions}"
# Provider routing: prefer cheap, good providers; block heavy-quant deepinfra (fp4)
# and any 4-bit; fall back through the rest by price. Override with CC_ENHANCE_PROVIDER (JSON).
provider_json="${CC_ENHANCE_PROVIDER:-}"
if [[ -z "$provider_json" ]]; then
  provider_json='{"order":["baidu","deepseek","gmicloud","siliconflow","parasail","novita","akashml"],"allow_fallbacks":true,"ignore":["deepinfra"],"quantizations":["bf16","fp16","fp8","int8","fp6","unknown"],"sort":"price","preferred_max_latency":{"p90":5}}'
fi

# --- system prompt file ---
if [[ ! -r "$SYS_PROMPT_FILE" ]]; then
  log "SKIP no-sysprompt-file at $SYS_PROMPT_FILE"
  exit 0
fi
sys_prompt=$(cat "$SYS_PROMPT_FILE")

# --- call LLM ---
start_ms=$(date +%s%3N)
body=$(jq -n \
  --arg model "$model" \
  --arg sys "$sys_prompt" \
  --arg p "$prompt_clean" \
  --argjson prov "$provider_json" \
  '{model:$model, max_tokens:500, temperature:0.2, reasoning:{enabled:false}, provider:$prov,
    messages:[{role:"system",content:$sys},{role:"user",content:$p}]}')

response=$(curl -sS --max-time 3 \
  -H "Authorization: Bearer $api_key" \
  -H "Content-Type: application/json" \
  -H "HTTP-Referer: https://claude.com/claude-code" \
  -H "X-Title: claude-code-enhance-prompt-hook" \
  -d "$body" \
  "$endpoint" 2>>"$LOG")
curl_rc=$?
if (( curl_rc != 0 )); then
  log "FAIL curl rc=$curl_rc (timeout or network)"
  exit 0
fi

enhanced=$(printf '%s' "$response" | jq -r '.choices[0].message.content // ""' 2>/dev/null)
if [[ -z "$enhanced" ]]; then
  err=$(printf '%s' "$response" | jq -r '.error.message // .error.code // .error // "empty"' 2>/dev/null)
  log "FAIL no-text err=$err"
  exit 0
fi

enhanced=$(printf '%s' "$enhanced" | sed -e 's/^[[:space:]]*//' -e 's/[[:space:]]*$//')

# Skip noise when rewrite is identical to the stripped original
if [[ "$enhanced" == "$prompt_clean" ]]; then
  log "SKIP identical"
  exit 0
fi

elapsed_ms=$(( $(date +%s%3N) - start_ms ))
# Truncate rewrite for log so we can SEE what the rewriter produced
enhanced_log=$(printf '%s' "$enhanced" | tr '\n' ' ' | head -c 220)
log "OK len=$len elapsed=${elapsed_ms}ms model=$model rewrite=\"$enhanced_log\""

# --- emit additionalContext ---
ctx=$(printf '<system-reminder>\nThe user prefixed their request with `~` — a control marker that opts in to automated prompt rewriting. The prefix itself is NOT part of the request. A small fast model translated/rewrote the request below for clarity. Treat the rewritten version as the PRIMARY intent.\n\nThe rewriter has NO visibility into project / stack / repo context. So:\n- If it injects specific patterns, libraries, frameworks, or technologies that do not match the visible project context, IGNORE those mentions and defer to the original.\n- If it expands scope or adds requirements the user did not imply, defer to the original.\n- If rewritten and original diverge in a meaningful way you cannot reconcile from context, briefly ask the user to confirm before acting.\n\nOriginal (after stripping `~`): %s\nRewritten: %s\n</system-reminder>' "$prompt_clean" "$enhanced")

model_short="${model##*/}"
# systemMessage shows the rewrite verbatim so the user can verify what was injected.
sys_msg=$(printf '✨ ~rewrite (%s, %dms)\n  → %s' "$model_short" "$elapsed_ms" "$enhanced")
jq -n --arg ctx "$ctx" --arg msg "$sys_msg" \
  '{hookSpecificOutput:{hookEventName:"UserPromptSubmit", additionalContext:$ctx}, systemMessage:$msg}'
