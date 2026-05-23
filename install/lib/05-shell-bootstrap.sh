#!/usr/bin/env bash
# Bootstrap shell prerequisites that host/.zshrc depends on:
#   - zsh + plugins (apt)
#   - oh-my-zsh framework
#   - nvm
# All idempotent — checks first, installs if missing.
set -euo pipefail

[[ ${DRY_RUN:-0} -eq 1 ]] && DRY="echo [dry]" || DRY=""

# --- apt packages (only on Debian/Ubuntu) ---
if [[ "$OS" == "linux" ]] && command -v apt >/dev/null 2>&1; then
  MISSING=()
  for pkg in zsh zsh-autosuggestions zsh-syntax-highlighting fish; do
    if ! dpkg -l "$pkg" 2>/dev/null | grep -q '^ii'; then
      MISSING+=("$pkg")
    fi
  done
  if [[ ${#MISSING[@]} -gt 0 ]]; then
    echo "  apt install needed: ${MISSING[*]}"
    if [[ -z "$DRY" ]]; then
      sudo apt update -qq
      sudo apt install -y "${MISSING[@]}"
    fi
  else
    echo "  ok: zsh + plugins already installed"
  fi
fi

# --- oh-my-zsh (skip if framework dir already present) ---
if [[ ! -d "$HOME/.oh-my-zsh" ]]; then
  echo "  installing oh-my-zsh..."
  $DRY sh -c "$(curl -fsSL https://raw.githubusercontent.com/ohmyzsh/ohmyzsh/master/tools/install.sh)" "" --unattended --keep-zshrc
else
  echo "  ok: ~/.oh-my-zsh already present"
fi

# --- nvm ---
if [[ ! -d "$HOME/.nvm" ]]; then
  echo "  installing nvm..."
  $DRY bash -c "curl -o- https://raw.githubusercontent.com/nvm-sh/nvm/v0.40.1/install.sh | bash"
  echo "  reminder: open new shell, then 'nvm install --lts && nvm use --lts'"
else
  echo "  ok: ~/.nvm already present"
fi

if [[ ${SKIP_SERVICES_TOOLING:-0} -eq 0 ]]; then
  if ! command -v pg_ctl >/dev/null 2>&1 && [[ ! -x "$HOME/.local/bin/pg_ctl" ]]; then
    echo "         apt: sudo apt install postgresql-client postgresql"
    echo "         or build from source into ~/.local/opt/postgresql-XX/"
  fi
fi
