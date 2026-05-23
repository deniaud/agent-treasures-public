#!/usr/bin/env bash
set -euo pipefail
ENTRY="$HOME/dev/tweakcc-fixed/dist/index.mjs"
[[ -f "$ENTRY" ]] || { echo "  [!] $ENTRY missing — did 30-tweakcc-fixed.sh fail?"; exit 1; }
[[ ${DRY_RUN:-0} -eq 1 ]] && { echo "[dry] node $ENTRY --apply"; exit 0; }

# Reset ccInstallationPath so tweakcc re-detects on this host
python3 - <<'PY'
import json, pathlib
p = pathlib.Path.home() / '.tweakcc/config.json'
if p.exists():
    d = json.loads(p.read_text())
    d['ccInstallationPath'] = None
    p.write_text(json.dumps(d, indent=2) + '\n')
PY

echo "  applying tweakcc..."
node "$ENTRY" --apply
echo "  ok: tweakcc applied"
