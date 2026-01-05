# extras.zsh - PATH exports, tools configuration
# Source this file from ~/.zshrc

# Aliases
alias claude2='claude --dangerously-skip-permissions'
alias gemini2='gemini --yolo'
alias codex2='codex --dangerously-bypass-approvals-and-sandbox'


# ============================================================================
# PATH EXPORTS
# ============================================================================

# VS Code CLI
export PATH="$PATH:/Applications/Visual Studio Code.app/Contents/Resources/app/bin"

# Homebrew libpq (PostgreSQL client tools)
export PATH="/opt/homebrew/opt/libpq/bin:$PATH"

# uv (Python package manager) - installed via pipx
export PATH="$PATH:/Users/bikram/.local/bin"

# Antigravity
export PATH="/Users/bikram/.antigravity/antigravity/bin:$PATH"

# ============================================================================
# NVM (Node Version Manager)
# ============================================================================

export NVM_DIR="$HOME/.nvm"
[ -s "$NVM_DIR/nvm.sh" ] && \. "$NVM_DIR/nvm.sh"  # This loads nvm
[ -s "$NVM_DIR/bash_completion" ] && \. "$NVM_DIR/bash_completion"  # This loads nvm bash_completion

# ============================================================================
# UV (Python) - Optional helpers
# ============================================================================

# Quick venv creation with uv
uvenv() {
  local name="${1:-.venv}"
  uv venv "$name" && source "$name/bin/activate"
}

# Activate venv in current or parent directory
vact() {
  local dir="$PWD"
  while [[ "$dir" != "/" ]]; do
    if [[ -f "$dir/.venv/bin/activate" ]]; then
      source "$dir/.venv/bin/activate"
      echo "Activated: $dir/.venv"
      return 0
    elif [[ -f "$dir/venv/bin/activate" ]]; then
      source "$dir/venv/bin/activate"
      echo "Activated: $dir/venv"
      return 0
    fi
    dir="${dir:h}"
  done
  echo "No venv found in current or parent directories"
  return 1
}

# Deactivate alias
alias vd='deactivate'

# ============================================================================
# FZF Configuration (if installed)
# ============================================================================

if command -v fzf >/dev/null 2>&1; then
  # Use fd for fzf if available (faster than find)
  if command -v fd >/dev/null 2>&1; then
    export FZF_DEFAULT_COMMAND='fd --type f --hidden --follow --exclude .git'
    export FZF_CTRL_T_COMMAND="$FZF_DEFAULT_COMMAND"
    export FZF_ALT_C_COMMAND='fd --type d --hidden --follow --exclude .git'
  fi

  # FZF options
  export FZF_DEFAULT_OPTS='--height=40% --layout=reverse --border --info=inline --bind=ctrl-d:half-page-down,ctrl-u:half-page-up'

  # Load fzf keybindings and completion
  [ -f ~/.fzf.zsh ] && source ~/.fzf.zsh
fi

# ============================================================================
# MISC HELPERS
# ============================================================================

# Quick directory shortcuts
alias ..='cd ..'
alias ...='cd ../..'
alias ....='cd ../../..'

# ls with better defaults (use eza if available, fallback to ls)
if command -v eza >/dev/null 2>&1; then
  alias ls='eza'
  alias ll='eza -la --git'
  alias la='eza -a'
  alias lt='eza --tree --level=2'
else
  alias ll='ls -la'
  alias la='ls -a'
fi

# Make directory and cd into it
mkcd() {
  mkdir -p "$1" && cd "$1"
}

# Quick file preview (uses bat if available)
peek() {
  if command -v bat >/dev/null 2>&1; then
    bat --style=numbers --color=always "$@"
  else
    cat "$@"
  fi
}

# ============================================================================
# DIGITALOCEAN CLEANUP
# ============================================================================

# Delete all DigitalOcean apps matching a pattern
do-app-clean() {
  local pattern="$1"
  if [[ -z "$pattern" ]]; then
    echo "Usage: do-app-clean <pattern>"
    echo "Example: do-app-clean 'validate-*'"
    return 1
  fi

  echo "Finding apps matching: $pattern"
  local matches=$(doctl apps list --format ID,Spec.Name --no-header | grep -E "$pattern")

  if [[ -z "$matches" ]]; then
    echo "No apps found matching: $pattern"
    return 0
  fi

  echo "\nApps to delete:"
  echo "$matches" | while read -r id name; do
    echo "  - $name ($id)"
  done

  echo ""
  read -q "confirm?Delete these apps? [y/N] "
  echo ""

  if [[ "$confirm" == "y" ]]; then
    echo "$matches" | while read -r id name; do
      echo "Deleting: $name..."
      doctl apps delete "$id" --force
    done
    echo "Done!"
  else
    echo "Cancelled."
  fi
}

# Delete all DigitalOcean databases matching a pattern
do-db-clean() {
  local pattern="$1"
  if [[ -z "$pattern" ]]; then
    echo "Usage: do-db-clean <pattern>"
    echo "Example: do-db-clean 'validate-*'"
    return 1
  fi

  echo "Finding databases matching: $pattern"
  local matches=$(doctl database list --format ID,Name --no-header | grep -E "$pattern")

  if [[ -z "$matches" ]]; then
    echo "No databases found matching: $pattern"
    return 0
  fi

  echo "\nDatabases to delete:"
  echo "$matches" | while read -r id name; do
    echo "  - $name ($id)"
  done

  echo ""
  read -q "confirm?Delete these databases? [y/N] "
  echo ""

  if [[ "$confirm" == "y" ]]; then
    echo "$matches" | while read -r id name; do
      echo "Deleting: $name..."
      doctl database delete "$id" --force
    done
    echo "Done!"
  else
    echo "Cancelled."
  fi
}
