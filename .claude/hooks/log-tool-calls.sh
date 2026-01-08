#!/bin/bash
# Comprehensive Hook Logging with Agent/Subagent Identification
#
# This hook captures ALL Claude Code hook events from orchestrator and subagents,
# prefixing each log entry with the agent identifier for easy filtering.
#
# SUPPORTED HOOKS:
# - PreToolUse, PostToolUse, PermissionRequest
# - UserPromptSubmit, Notification
# - Stop, SubagentStop
# - SessionStart, SessionEnd, PreCompact
#
# LOG FORMAT:
# [HH:MM:SS] [agent_id] EVENT_TYPE: details
#
# AGENT IDENTIFICATION:
# - orchestrator: Main agent controlling the workflow
# - subagent:{name}: Specialized subagent (e.g., subagent:Explore)
#
# The hook determines which agent is active by checking:
# 1. The most recent HANDOFF.md file (indicates active subagent)
# 2. Falls back to "orchestrator" if no active subagent

# Note: Deliberately NOT using 'set -e' here - hooks should be resilient
# and not block Claude operations if logging fails

# Read hook input from stdin
input=$(cat)

# Get current session timestamp
SESSION_TS=$(cat .claude-logs/.current_session 2>/dev/null)
if [ -z "$SESSION_TS" ]; then
  # Create new session if none exists
  SESSION_TS=$(date +%Y%m%d-%H%M%S)
  mkdir -p .claude-logs
  echo "$SESSION_TS" > .claude-logs/.current_session
fi

LOG_FILE=".claude-logs/${SESSION_TS}.log"
AGENT_LOG=".claude-logs/${SESSION_TS}-agents.log"

# Extract hook event type and tool info
HOOK_EVENT=$(echo "$input" | jq -r '.hook_event_name // "PreToolUse"')
TOOL_NAME=$(echo "$input" | jq -r '.tool_name // "unknown"')
TOOL_INPUT=$(echo "$input" | jq -r '.tool_input // {}')

# Determine agent ID
# Check for active subagent by finding most recent HANDOFF.md
AGENT_ID="orchestrator"

# Look for active task folder with HANDOFF.md but no RESULT.md
if [ -d ".claude-tasks" ]; then
  # Find all HANDOFF.md files, sort by modification time (newest first)
  ACTIVE_HANDOFF=$(find .claude-tasks -name "HANDOFF.md" -type f 2>/dev/null | while read f; do
    # Check if corresponding RESULT.md exists
    RESULT_FILE="${f%HANDOFF.md}RESULT.md"
    if [ ! -f "$RESULT_FILE" ]; then
      echo "$f"
    fi
  done | head -1)

  if [ -n "$ACTIVE_HANDOFF" ]; then
    # Extract subagent name from HANDOFF.md
    SUBAGENT=$(grep -m1 "^\*\*Subagent\*\*:" "$ACTIVE_HANDOFF" 2>/dev/null | sed 's/.*: *//' | tr -d ' ')
    if [ -z "$SUBAGENT" ]; then
      # Try alternate format
      SUBAGENT=$(grep -m1 "^## Subagent:" "$ACTIVE_HANDOFF" 2>/dev/null | sed 's/.*: *//' | tr -d ' ')
    fi
    if [ -z "$SUBAGENT" ]; then
      # Try another format (Subagent: value in a line)
      SUBAGENT=$(grep -m1 "Subagent:" "$ACTIVE_HANDOFF" 2>/dev/null | sed 's/.*Subagent: *//' | tr -d ' ' | tr -d '*')
    fi
    if [ -n "$SUBAGENT" ]; then
      AGENT_ID="subagent:$SUBAGENT"
    fi
  fi
fi

# Get timestamp
TIME=$(date +%H:%M:%S)
DATETIME=$(date +%Y-%m-%dT%H:%M:%S)

# Route by hook event type
case "$HOOK_EVENT" in
  "PreToolUse")
    # Format the log entry based on tool type
    case "$TOOL_NAME" in
      "Write")
        FILE_PATH=$(echo "$TOOL_INPUT" | jq -r '.file_path // "unknown"')
        CONTENT_SIZE=$(echo "$TOOL_INPUT" | jq -r '.content // ""' | wc -c)

        # Check if this is a task folder operation
        if [[ "$FILE_PATH" == *".claude-tasks"* ]]; then
          if [[ "$FILE_PATH" == *"HANDOFF.md" ]]; then
            echo "[$TIME] [$AGENT_ID] HANDOFF: $FILE_PATH" >> "$LOG_FILE"
            echo "[$DATETIME] DISPATCH: $(dirname "$FILE_PATH" | xargs basename)" >> "$AGENT_LOG"
          elif [[ "$FILE_PATH" == *"RESULT.md" ]]; then
            echo "[$TIME] [$AGENT_ID] RESULT: $FILE_PATH" >> "$LOG_FILE"
            echo "[$DATETIME] COMPLETE: $(dirname "$FILE_PATH" | xargs basename)" >> "$AGENT_LOG"
          elif [[ "$FILE_PATH" == *"MASTER.md" ]]; then
            echo "[$TIME] [$AGENT_ID] MASTER: Updated progress" >> "$LOG_FILE"
          else
            echo "[$TIME] [$AGENT_ID] Write: $FILE_PATH (${CONTENT_SIZE}b)" >> "$LOG_FILE"
          fi
        elif [[ "$FILE_PATH" == *"/plans/"* ]]; then
          echo "[$TIME] [$AGENT_ID] PLAN: $FILE_PATH" >> "$LOG_FILE"
        else
          echo "[$TIME] [$AGENT_ID] Write: $FILE_PATH (${CONTENT_SIZE}b)" >> "$LOG_FILE"
        fi
        ;;

      "Edit")
        FILE_PATH=$(echo "$TOOL_INPUT" | jq -r '.file_path // "unknown"')
        echo "[$TIME] [$AGENT_ID] Edit: $FILE_PATH" >> "$LOG_FILE"
        ;;

      "Read")
        FILE_PATH=$(echo "$TOOL_INPUT" | jq -r '.file_path // "unknown"')
        echo "[$TIME] [$AGENT_ID] Read: $FILE_PATH" >> "$LOG_FILE"
        ;;

      "Glob")
        PATTERN=$(echo "$TOOL_INPUT" | jq -r '.pattern // "unknown"')
        echo "[$TIME] [$AGENT_ID] Glob: $PATTERN" >> "$LOG_FILE"
        ;;

      "Grep")
        PATTERN=$(echo "$TOOL_INPUT" | jq -r '.pattern // "unknown"')
        echo "[$TIME] [$AGENT_ID] Grep: \"$PATTERN\"" >> "$LOG_FILE"
        ;;

      "Bash")
        COMMAND=$(echo "$TOOL_INPUT" | jq -r '.command // "unknown"' | head -c 100)
        BACKGROUND=$(echo "$TOOL_INPUT" | jq -r '.run_in_background // false')
        if [ "$BACKGROUND" = "true" ]; then
          echo "[$TIME] [$AGENT_ID] Bash(bg): $COMMAND" >> "$LOG_FILE"
        else
          echo "[$TIME] [$AGENT_ID] Bash: $COMMAND" >> "$LOG_FILE"
        fi
        ;;

      "Task")
        DESC=$(echo "$TOOL_INPUT" | jq -r '.description // "unknown"')
        SUBTYPE=$(echo "$TOOL_INPUT" | jq -r '.subagent_type // "unknown"')
        echo "[$TIME] [$AGENT_ID] Task($SUBTYPE): $DESC" >> "$LOG_FILE"
        echo "[$DATETIME] SPAWN: $SUBTYPE - $DESC" >> "$AGENT_LOG"
        ;;

      "WebFetch")
        URL=$(echo "$TOOL_INPUT" | jq -r '.url // "unknown"')
        echo "[$TIME] [$AGENT_ID] WebFetch: $URL" >> "$LOG_FILE"
        ;;

      "WebSearch")
        QUERY=$(echo "$TOOL_INPUT" | jq -r '.query // "unknown"')
        echo "[$TIME] [$AGENT_ID] WebSearch: $QUERY" >> "$LOG_FILE"
        ;;

      "TodoWrite")
        TODO_COUNT=$(echo "$TOOL_INPUT" | jq -r '.todos | length // 0')
        echo "[$TIME] [$AGENT_ID] TodoWrite: $TODO_COUNT items" >> "$LOG_FILE"
        ;;

      "NotebookEdit")
        NOTEBOOK=$(echo "$TOOL_INPUT" | jq -r '.notebook_path // "unknown"')
        echo "[$TIME] [$AGENT_ID] NotebookEdit: $NOTEBOOK" >> "$LOG_FILE"
        ;;

      *)
        echo "[$TIME] [$AGENT_ID] $TOOL_NAME" >> "$LOG_FILE"
        ;;
    esac
    ;;

  "PostToolUse")
    # Log tool completion with status only
    TOOL_RESPONSE=$(echo "$input" | jq -r '.tool_response // {}')
    # Check if response indicates error
    HAS_ERROR=$(echo "$TOOL_RESPONSE" | jq -r 'if type == "object" then (has("error") or has("Error")) else false end')
    if [ "$HAS_ERROR" = "true" ]; then
      echo "[$TIME] [$AGENT_ID] PostToolUse($TOOL_NAME): error" >> "$LOG_FILE"
    else
      echo "[$TIME] [$AGENT_ID] PostToolUse($TOOL_NAME): success" >> "$LOG_FILE"
    fi
    ;;

  "PermissionRequest")
    MESSAGE=$(echo "$input" | jq -r '.message // "unknown"' | head -c 100)
    echo "[$TIME] [$AGENT_ID] Permission: $MESSAGE" >> "$LOG_FILE"
    ;;

  "Notification")
    NOTIF_TYPE=$(echo "$input" | jq -r '.notification_type // "unknown"')
    MESSAGE=$(echo "$input" | jq -r '.message // ""' | head -c 80)
    echo "[$TIME] [$AGENT_ID] Notify($NOTIF_TYPE): $MESSAGE" >> "$LOG_FILE"
    ;;

  "UserPromptSubmit")
    PROMPT=$(echo "$input" | jq -r '.prompt // ""' | head -c 80)
    echo "[$TIME] [$AGENT_ID] Prompt: \"$PROMPT\"" >> "$LOG_FILE"
    ;;

  "Stop")
    echo "[$TIME] [$AGENT_ID] Stop: agent finished" >> "$LOG_FILE"
    echo "[$DATETIME] STOP: orchestrator" >> "$AGENT_LOG"
    ;;

  "SubagentStop")
    echo "[$TIME] [$AGENT_ID] SubagentStop: finished" >> "$LOG_FILE"
    echo "[$DATETIME] STOP: $AGENT_ID" >> "$AGENT_LOG"
    ;;

  "PreCompact")
    TRIGGER=$(echo "$input" | jq -r '.trigger // "unknown"')
    echo "[$TIME] [$AGENT_ID] PreCompact: $TRIGGER" >> "$LOG_FILE"
    ;;

  "SessionStart")
    SOURCE=$(echo "$input" | jq -r '.source // "unknown"')
    echo "[$TIME] [$AGENT_ID] SessionStart: $SOURCE" >> "$LOG_FILE"
    ;;

  "SessionEnd")
    REASON=$(echo "$input" | jq -r '.reason // "unknown"')
    echo "[$TIME] [$AGENT_ID] SessionEnd: $REASON" >> "$LOG_FILE"
    echo "[$DATETIME] SESSION_END: $REASON" >> "$AGENT_LOG"
    ;;

  *)
    # Unknown hook event
    echo "[$TIME] [$AGENT_ID] $HOOK_EVENT" >> "$LOG_FILE"
    ;;
esac

# Exit successfully (don't block the hook)
exit 0
