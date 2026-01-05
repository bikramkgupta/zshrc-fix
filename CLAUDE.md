# CLAUDE.md

This file provides guidance to Claude Code (claude.ai/code) when working with code in this repository.

## Overview

**shell-kit** - Modular zsh configuration + Claude Code settings for macOS. Deploys both shell tools and Claude Code configuration.

## Deployment

```bash
./deploy.sh           # Interactive deployment with diff preview and backups
./deploy.sh --force   # Skip confirmations (still creates backups)
```

Creates timestamped backups:
- Zsh: `~/.zsh-backup/YYYYMMDD_HHMMSS/`
- Claude: `~/.claude-backup/YYYYMMDD_HHMMSS/`
- Codex: `~/.codex-backup/YYYYMMDD_HHMMSS/`

After deployment: `source ~/.zshrc`

## Architecture

```
zshrc                    # Loader + Homebrew + completions + starship + zsh plugins
.zsh/
  docker-tools.zsh       # Docker/Compose aliases (dkps, dc, dcu, etc.)
  extras.zsh             # PATH exports, NVM, FZF config, Python venv helpers
  git-tools.zsh          # Git/worktree power-user commands (gwt-*, gbr-*, etc.)
  hunt.zsh               # Unified search using fd/rg/fzf
.claude/
  CLAUDE.md              # Personal defaults for all projects
  settings.json          # Permissions, hooks, statusline config
  statusline.sh          # Custom status bar script
  hooks/                 # Session logging hooks
  commands/              # Custom command definitions (e.g., squash-commits)
  tools/session-analyzer/ # Session analysis tool
.codex/
  config.toml            # Codex CLI settings (model, trust levels)
  tools/session-analyzer/ # Session analysis tool for Codex
```

## Help Commands

- `ghelp` - Git/worktree command reference
- `dkhelp` - Docker command reference
- `hunt -h` - Search command help
- `claude-session-analyzer --help` - Claude session analysis tool
- `codex-session-analyzer --help` - Codex session analysis tool

Most functions also support `--help` flag:
- `gwt-ship --help`, `gwt-new --help`, `gwt-go --help`, `gwt-clone-bare --help`
- `dkexec --help`, `dcsh --help`

## Worktree Layout Convention

Git worktree commands (`gwt-*`) use a bare repository layout:
- `.bare/` directory at repo root contains the actual git data
- `.git` file (not directory) points to `.bare/`
- Worktrees are sibling directories named `{repo}-{branch}` (slashes become `__`)

Example: `gwt-ship myproject main` creates:
```
myproject/
  .bare/           # Bare git repo
  .git             # File containing "gitdir: ./.bare"
  myproject-main/  # Worktree for main branch
```

## Key Functions

**Repo initialization:**
- `gwt-ship <name> <branch>` - Create repo + GitHub remote + push (all-in-one)
- `gwt-clone-bare <url>` - Clone existing repo into bare structure

**Worktree ops:**
- `gwt-new <branch> [base]` - New branch + worktree
- `gwt-go <branch>` - cd to worktree
- `gwf` / `gwt-fzf` - Fuzzy find and switch worktree

**Search:**
- `hunt "*.py"` - Find files by name
- `hunt -c "pattern"` - Search file contents
- `hunt -i "*.tsx"` - Interactive mode with fzf preview

**Claude tools:**
- `claude-session-analyzer --list` - List all sessions
- `claude-session-analyzer --latest --open` - View latest session trace
- `claude-session-analyzer --latest --digest` - Markdown digest for session continuation

**Codex tools:**
- `codex-session-analyzer --list` - List all sessions
- `codex-session-analyzer --latest --open` - View latest session trace
- `codex-session-analyzer --latest --digest` - Markdown digest for session continuation

## Dependencies

Required: `fd`, `rg` (ripgrep)
Optional: `fzf`, `bat`, `eza`, `starship`, `gh` (GitHub CLI for gwt-ship)
