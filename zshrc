# ~/.zshrc - Minimal modular loader
# All configs live in ~/.zsh/*.zsh

# ============================================================================
# HOMEBREW (must be first for paths)
# ============================================================================

eval "$(/opt/homebrew/bin/brew shellenv)"

# ============================================================================
# LOAD MODULAR CONFIGS
# ============================================================================

# Load all .zsh files from ~/.zsh/ directory
# Order: docker-tools, extras, git-tools, hunt (alphabetical)
for config in ~/.zsh/*.zsh(N); do
  source "$config"
done

# ============================================================================
# COMPLETIONS
# ============================================================================

# Initialize completion system
autoload -Uz compinit

# Only regenerate compinit cache once per day for faster startup
if [[ -n ~/.zcompdump(#qN.mh+24) ]]; then
  compinit
else
  compinit -C
fi

# ============================================================================
# STARSHIP PROMPT
# ============================================================================

if command -v starship >/dev/null 2>&1; then
  eval "$(starship init zsh)"
fi

# ============================================================================
# ZSH PLUGINS (syntax highlighting must be last)
# ============================================================================

# Autosuggestions (fish-like suggestions)
if [[ -f $(brew --prefix)/share/zsh-autosuggestions/zsh-autosuggestions.zsh ]]; then
  source $(brew --prefix)/share/zsh-autosuggestions/zsh-autosuggestions.zsh
fi

# Syntax highlighting (must be sourced last)
if [[ -f $(brew --prefix)/share/zsh-syntax-highlighting/zsh-syntax-highlighting.zsh ]]; then
  source $(brew --prefix)/share/zsh-syntax-highlighting/zsh-syntax-highlighting.zsh
fi

# ============================================================================
# QUICK REFERENCE
# ============================================================================
# Run these for help:
#   ghelp           - Git/worktree commands
#   ghelp workflows - Common git workflows
#   dkhelp          - Docker commands
#   hunt -h         - File/content search

# ============================================================================
# WELCOME MESSAGE
# ============================================================================

printf "\n  \033[1mghelp\033[0m git/worktree  •  \033[1mdkhelp\033[0m docker  •  \033[1mhunt -h\033[0m search  •  \033[1mclaude-session-analyzer\033[0m sessions\n\n"
