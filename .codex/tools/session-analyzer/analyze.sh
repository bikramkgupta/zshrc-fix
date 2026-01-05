#!/bin/bash
# Codex Session Analyzer - CLI wrapper
#
# Usage:
#   codex-session-analyzer --list              # List all sessions
#   codex-session-analyzer --latest            # Analyze most recent session
#   codex-session-analyzer --latest --open     # Open latest in browser
#   codex-session-analyzer --latest --digest   # Markdown digest for continuation
#   codex-session-analyzer <session-id>        # Analyze specific session
#   codex-session-analyzer <session-id> --open # Open specific session in browser

# Resolve symlinks to find actual script location
SOURCE="${BASH_SOURCE[0]}"
while [ -L "$SOURCE" ]; do
  DIR="$(cd -P "$(dirname "$SOURCE")" && pwd)"
  SOURCE="$(readlink "$SOURCE")"
  [[ $SOURCE != /* ]] && SOURCE="$DIR/$SOURCE"
done
SCRIPT_DIR="$(cd -P "$(dirname "$SOURCE")" && pwd)"

exec python3 "$SCRIPT_DIR/parser.py" "$@"
