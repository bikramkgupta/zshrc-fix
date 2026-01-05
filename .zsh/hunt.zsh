# hunt.zsh - Fast repository search command
# Requires: fd (required), rg (required for content search)
# Optional: fzf (interactive mode), bat (file preview)

function hunt {
  setopt localoptions noglob 2>/dev/null

  local mode="name"
  local output="files"
  local interactive=0
  local list_only=0

  local EXCLUDES=(
    node_modules .git .venv venv __pycache__
    dist build .next .cache .idea .vscode coverage
    .mypy_cache .pytest_cache .tox .eggs *.egg-info
    .DS_Store Thumbs.db
  )

  while getopts "ncdfilgh" opt; do
    case "$opt" in
      n) mode="name" ;;
      c) mode="content" ;;
      d) output="dirs" ;;
      f) output="files" ;;
      i) interactive=1 ;;
      l) list_only=1 ;;
      g) ;;
      h)
        cat <<'EOF'
hunt - fast repo search

USAGE:
  hunt [flags] <pattern> [filter/path]

FLAGS:
  -n    Name search (default) - find files by name pattern
  -c    Content search - show matching lines with file:line:content
  -l    List mode - only show filenames (for -c), no match content
  -d    Directory mode - show parent directories of matches
  -f    File mode (default) - show matching files
  -i    Interactive - use fzf for selection
  -h    Show this help

EXAMPLES:
  # --- File Name Search ---
  hunt "*.py"              # Find all Python files
  hunt "config*.yaml"      # Find config files
  hunt "*.ts" src          # Find .ts files in src/

  # --- Content Search (shows file:line:match) ---
  hunt -c "API_KEY"        # Find API_KEY with context
  hunt -c "TODO" "*.py"    # Find TODOs in Python files
  hunt -c "SECRET" "*.env" # Search in .env files (hidden/ignored included)

  # --- List Files Only ---
  hunt -c -l "password"    # Just list files containing "password"

  # --- Directory Mode ---
  hunt -d "*.py"           # List folders containing Python files

  # --- Interactive (FZF) ---
  hunt -i "*.tsx"          # Find React components -> select
  hunt -c -i "TODO"        # Find TODOs -> preview matches

NOTE: Hidden and gitignored files are searched by default.
      Common junk dirs (node_modules, .git, etc.) are excluded.

DEPENDENCIES:
  Required: fd (file finder), rg (content search)
  Optional: fzf (interactive), bat (preview highlighting)
EOF
        return
        ;;
    esac
  done
  shift $((OPTIND - 1))

  local pattern="$1"
  local filter="$2"

  [[ -z "$pattern" ]] && echo "Error: Pattern required. Use 'hunt -h' for help." && return 1

  # Check dependencies
  if [[ "$mode" == "name" ]] && ! command -v fd >/dev/null; then
    echo "Error: 'fd' is required for name search. Install with: brew install fd"
    return 1
  fi
  if [[ "$mode" == "content" ]] && ! command -v rg >/dev/null; then
    echo "Error: 'rg' (ripgrep) is required for content search. Install with: brew install ripgrep"
    return 1
  fi
  if [[ "$interactive" -eq 1 ]] && ! command -v fzf >/dev/null; then
    echo "Warning: 'fzf' not found. Install with: brew install fzf"
    echo "Falling back to non-interactive mode..."
    interactive=0
  fi

  local cmd=()

  # ---------- NAME SEARCH ----------
  if [[ "$mode" == "name" ]]; then
    cmd=(fd -g "$pattern" --no-ignore --hidden)
    for e in "${EXCLUDES[@]}"; do
      cmd+=(--exclude "$e")
    done

    # Use 2nd arg as search path (e.g., hunt *.py src)
    if [[ -n "$filter" ]]; then
      cmd+=("$filter")
    fi
  fi

  # ---------- CONTENT SEARCH ----------
  if [[ "$mode" == "content" ]]; then
    if [[ "$list_only" -eq 1 ]]; then
      cmd=(rg -i --files-with-matches --no-messages "$pattern")
    else
      cmd=(rg -i -n --heading --color=always --no-messages "$pattern")
    fi
    cmd+=(--no-ignore --hidden)

    for e in "${EXCLUDES[@]}"; do
      cmd+=(--glob "!$e")
    done

    # Use 2nd arg as file glob (e.g., hunt -c TOKEN *.env)
    if [[ -n "$filter" ]]; then
      cmd+=(--glob "$filter")
    fi
  fi

  # ---------- OUTPUT ----------
  local dir_filter="sed 's|/[^/]*$||' | sort -u"

  if [[ "$output" == "dirs" ]]; then
    if [[ "$interactive" -eq 1 ]]; then
      "${cmd[@]}" | eval "$dir_filter" | fzf --preview 'ls -la {}'
    else
      "${cmd[@]}" | eval "$dir_filter"
    fi
    return
  fi

  if [[ "$interactive" -eq 1 ]]; then
    local preview_cmd
    if [[ "$mode" == "content" ]]; then
      # For interactive, always get file list for selection
      local file_cmd=(rg -i --files-with-matches --no-messages --no-ignore --hidden "$pattern")
      for e in "${EXCLUDES[@]}"; do
        file_cmd+=(--glob "!$e")
      done
      if [[ -n "$filter" ]]; then
        file_cmd+=(--glob "$filter")
      fi
      # Show matching lines with context in preview
      preview_cmd="rg -i --color=always -n -C 2 '$pattern' {} | head -50"
      "${file_cmd[@]}" | fzf --preview "$preview_cmd" --preview-window=right:60%
    else
      # Show file contents
      if command -v bat >/dev/null; then
        preview_cmd='bat --style=numbers --color=always --line-range=:100 {}'
      else
        preview_cmd='head -100 {}'
      fi
      "${cmd[@]}" | fzf --preview "$preview_cmd" --preview-window=right:60%
    fi
  else
    "${cmd[@]}"
  fi
}

# Alias to handle glob patterns without quoting
alias hunt='noglob hunt'

# Quick shortcuts
alias hc='hunt -c'      # Content search (shows matches)
alias hcl='hunt -c -l'  # Content search (list files only)
alias hi='hunt -i'      # Interactive name search
alias hci='hunt -c -i'  # Interactive content search
