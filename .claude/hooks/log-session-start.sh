#!/bin/bash
# Creates session log file in project's .claude-logs directory

# Read hook input (contains session_id, workspace info, etc.)
input=$(cat)

# Create logs directory in current project
mkdir -p .claude-logs

# Generate timestamp-based filename
TIMESTAMP=$(date +%Y%m%d_%H%M%S)

# Store current session identifier for other hooks to reference
echo "$TIMESTAMP" > .claude-logs/.current_session

# Create log file with header
LOG_FILE=".claude-logs/${TIMESTAMP}.log"
{
  echo "=============================================="
  echo "Session: $TIMESTAMP"
  echo "Started: $(date)"
  echo "Directory: $(pwd)"
  echo "=============================================="
  echo ""
} > "$LOG_FILE"

# Reminder for manual config
echo "Remember: /config -> disable autocompact"
