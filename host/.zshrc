# Local bin / env
export PATH="$HOME/.local/bin:$PATH"
[ -f "$HOME/.local/bin/env" ] && . "$HOME/.local/bin/env"

# Oh My Zsh
export ZSH="$HOME/.oh-my-zsh"
ZSH_THEME="robbyrussell"
plugins=(git sudo)
source "$ZSH/oh-my-zsh.sh"

# NVM
export NVM_DIR="$HOME/.nvm"
[ -s "$NVM_DIR/nvm.sh" ] && . "$NVM_DIR/nvm.sh"
[ -s "$NVM_DIR/bash_completion" ] && . "$NVM_DIR/bash_completion"

# direnv — loads ~/.envrc (secrets) when cwd is within $HOME
if command -v direnv >/dev/null 2>&1; then
  export DIRENV_LOG_FORMAT=""
  eval "$(direnv hook zsh)"
fi

# Extras
source /usr/share/zsh-autosuggestions/zsh-autosuggestions.zsh
source /usr/share/zsh-syntax-highlighting/zsh-syntax-highlighting.zsh

# Secrets live in ~/.envrc and are loaded by direnv (eval above).
# To rotate or add: edit ~/.envrc then `direnv allow ~`.

# Claude Code MCP profiles
alias claude-ui='claude --strict-mcp-config --mcp-config "$HOME/.claude/profiles/ui/mcp.json"'

# Wrap `claude` so a build-update check fires before the binary launches.
#   - bare `claude` (interactive launch): runs ~/.claude/scripts/build-update-check.sh,
#     which prompts the user if the CC binary drifted past the version we last
#     patched, or if upstream tweakcc-fixed has new commits. On accept it execs
#     into build-update-apply.sh (which patches and then launches CC). On decline
#     or no-update-needed, we fall through to `command claude`.
#   - `claude update`: keeps the old behaviour but routes the post-update repatch
#     through the full pipeline (tweakcc + cc-prompt-rewriter + cc-quote), not
#     just tweakcc alone.
claude() {
  local check="$HOME/.claude/scripts/build-update-check.sh"
  local apply="$HOME/.claude/scripts/build-update-apply.sh"

  if [[ "${1:-}" == "update" ]]; then
    command claude "$@" || return $?
    if [[ -x "$apply" ]]; then
      "$apply" --skip-cc-update --no-launch
    else
      echo "[!] $apply missing — falling back to tweakcc-only repatch" >&2
      node "$HOME/dev/tweakcc-fixed/dist/index.mjs" --apply || {
        echo "    Rollback: node \$HOME/dev/tweakcc-fixed/dist/index.mjs --restore" >&2
        return 2
      }
    fi
    return
  fi

  if [[ $# -eq 0 && -t 0 && -t 1 && -x "$check" ]]; then
    "$check"
  fi

  command claude "$@"
}
