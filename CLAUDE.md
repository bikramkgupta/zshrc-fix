# CLAUDE.md

This file provides guidance to Claude Code (claude.ai/code) when working with code in this repository.

## Overview

Modular zsh configuration system for macOS. The main `zshrc` sources all `.zsh` files from `~/.zsh/` alphabetically.

## Deployment

```bash
./deploy.sh           # Interactive deployment with diff preview and backups
./deploy.sh --force   # Skip confirmations (still creates backups)
```

Creates timestamped backups in `~/.zsh-backup/`. After deployment: `source ~/.zshrc`

## Architecture

```
zshrc                    # Loader + Homebrew + completions + starship + zsh plugins
.zsh/
  docker-tools.zsh       # Docker/Compose aliases (dkps, dc, dcu, etc.)
  extras.zsh             # PATH exports, NVM, FZF config, Python venv helpers
  git-tools.zsh          # Git/worktree power-user commands (gwt-*, gbr-*, etc.)
  hunt.zsh               # Unified search using fd/rg/fzf
```

## Help Commands

- `ghelp` - Git/worktree command reference
- `dkhelp` - Docker command reference
- `hunt -h` - Search command help

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

## Dependencies

Required: `fd`, `rg` (ripgrep)
Optional: `fzf`, `bat`, `eza`, `starship`, `gh` (GitHub CLI for gwt-ship)
