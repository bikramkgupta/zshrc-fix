# shell-kit

Modular zsh configuration + AI coding assistant settings for macOS.

## What's Included

- **Zsh configuration** - Git worktree commands, Docker aliases, unified search with `hunt`
- **Claude Code settings** - Hooks, permissions, session analyzer
- **Codex settings** - Config and session analyzer

## Requirements

- macOS
- `fd`, `rg` (ripgrep)
- Optional: `fzf`, `bat`, `eza`, `starship`, `gh`

## Installation

```bash
git clone https://github.com/bikramkgupta/shell-kit.git
cd shell-kit
./deploy.sh
source ~/.zshrc
```

## Quick Reference

```bash
ghelp                          # Git/worktree commands
dkhelp                         # Docker commands
hunt -h                        # Search commands
claude-session-analyzer --help # Claude session viewer
codex-session-analyzer --help  # Codex session viewer
```

## License

MIT
