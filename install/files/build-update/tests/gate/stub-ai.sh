#!/usr/bin/env bash
# Stub for GATE_AI_CMD. Behaviour controlled by $STUB_MODE:
#   pass   → valid pass JSON      block → valid block JSON
#   badjson→ non-JSON garbage     empty → nothing        fail → exit 1
#   hang   → sleep 999 (timeout test)
# Reads (and ignores) the prompt on argv/stdin so it behaves like `claude -p`.
case "${STUB_MODE:-pass}" in
  pass)    echo '{"verdict":"pass","severity":"none","findings":[],"summary":"ok"}' ;;
  block)   echo '{"verdict":"block","severity":"high","findings":[{"file":"x","kind":"malware","explanation":"bad"}],"summary":"nope"}' ;;
  badjson) echo 'totally not json {{{' ;;
  empty)   : ;;
  fail)    exit 1 ;;
  hang)    sleep 999 ;;
esac
