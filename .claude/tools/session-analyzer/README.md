# Claude Session Analyzer

A post-session analysis tool that parses Claude Code transcripts and generates interactive HTML visualizations with accurate agent attribution.

## Why This Exists

Claude Code hooks can't reliably identify which agent (main vs subagent) made a tool call because `session_id` is shared across all agents. This analyzer solves that by parsing the separate transcript files that Claude Code creates for each agent.

## Installation

```bash
# Create symlink for easy access
ln -s ~/.claude/tools/session-analyzer/analyze.sh ~/.local/bin/claude-session-analyzer
```

## Usage

```bash
# List all sessions with summaries
claude-session-analyzer --list

# Analyze latest session in current project
claude-session-analyzer --latest --open

# Analyze specific session (searches globally if not found locally)
claude-session-analyzer bf5793b6 --open

# Output JSON instead of HTML
claude-session-analyzer --output json

# Generate markdown digest for follow-up in new session
claude-session-analyzer 29108e9c --digest

# Save digest to file
claude-session-analyzer 29108e9c --digest > session-digest.md

# Analyze sessions in a specific project
claude-session-analyzer --project /path/to/project --list
```

### Digest Output

The `--digest` flag generates a concise markdown summary perfect for feeding into a new Claude session:

- **User Prompts** - Chronological list of what was asked
- **Key Thinking/Decisions** - Most substantive reasoning from Claude
- **Commands Run** - All bash commands executed
- **Files Modified** - Files that were edited or created
- **Errors Encountered** - Any tool errors that occurred
- **Where It Left Off** - Last prompt, response, and thinking

Use case: Session crashed or was force-closed? Generate a digest and paste it into a new session to continue where you left off.

## Features

### CLI
- `--list` - List all sessions with ID, duration, project, and summary
- `--latest` - Analyze most recent session
- `--digest` - Generate markdown digest for follow-up
- `--open` - Open HTML visualization in browser
- `--output json|html` - Choose output format
- `--project PATH` - Specify project directory
- Global fallback: If session not found locally, searches all projects

### HTML Visualization
- **Timeline View** - Chronological trace of all events
- **Tree View** - Hierarchical view grouped by agent
- **Event Types**:
  - User prompts (blue)
  - Thinking blocks (purple)
  - Text responses (green)
  - Tool calls (red) with inputs and results
  - Lifecycle events (purple) - Stop, SessionStart, SessionEnd, PreCompact
  - PostToolUse (green/red) - Success/error status for each tool call
- **Filters**:
  - By agent (orchestrator, Explore, Plan, etc.)
  - By event type
  - Text search
  - Checkbox toggles for each event type (including Lifecycle)
- **Session Selector** - Dropdown to switch between sessions
- **Stats** - Counts for agents, tools, user prompts, thinking, responses, lifecycle events

### Hook Log Integration

The analyzer automatically integrates events from hook logs (`.claude-logs/`) when available:

- **SessionStart/SessionEnd** - Session boundaries
- **Stop/SubagentStop** - Agent completion events
- **PreCompact** - Context compaction events
- **Notification** - System notifications
- **Permission** - User approval prompts
- **PostToolUse** - Success/error status for each tool call

Hook logs are discovered by matching timestamps with the session time window. If no hook logs exist, the analyzer works normally with just JSONL transcripts.

## How It Works

1. **Transcript Location**: `~/.claude/projects/{encoded-path}/{sessionId}.jsonl`
2. **Agent Transcripts**: Separate `agent-{agentId}.jsonl` files for each subagent
3. **Path Encoding**: Both `/` and `.` are replaced with `-`

The analyzer:
1. Finds the main session transcript
2. Discovers all associated agent transcripts
3. Filters out warmup agents
4. Extracts full trace (user, thinking, text, tool_use, tool_result)
5. Detects agent types from prompts (Explore, Plan, claude-code-guide, etc.)
6. Builds unified timeline with accurate agent attribution
7. Generates interactive HTML or JSON output

## Files

```
~/.claude/tools/session-analyzer/
├── analyze.sh      # CLI entry point (handles symlinks)
├── parser.py       # Core parsing and HTML generation
├── templates/      # (reserved for future templates)
└── README.md       # This file
```

## Dependencies

- Python 3.x (standard library only)
- Browser (for HTML visualization)
