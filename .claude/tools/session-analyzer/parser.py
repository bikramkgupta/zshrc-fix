#!/usr/bin/env python3
"""
Claude Code Session Analyzer

Parses session transcripts (main + subagent files) and generates
a unified timeline with agent attribution.

Usage:
    python3 parser.py [session-id]              # Analyze specific session
    python3 parser.py --latest                  # Analyze most recent session
    python3 parser.py --latest --project /path  # Most recent in specific project
    python3 parser.py --output json|html        # Output format (default: html)
    python3 parser.py --open                    # Open HTML in browser
    python3 parser.py --list                    # List all sessions with summaries
    python3 parser.py --digest                  # Generate markdown digest for follow-up
"""

import json
import argparse
import sys
import re
from pathlib import Path
from datetime import datetime
from typing import Optional
import subprocess
import tempfile


# Hook events to include (lifecycle events not in JSONL transcripts)
HOOK_EVENTS = {
    "SessionStart", "SessionEnd", "Stop", "SubagentStop",
    "PreCompact", "Notify", "Notification", "Permission", "PostToolUse"
}

# Regex pattern for hook log lines: [HH:MM:SS] [agent_id] EventType(optional): details
HOOK_LOG_PATTERN = re.compile(
    r'\[(\d{2}:\d{2}:\d{2})\]\s+\[([^\]]+)\]\s+(\w+)(?:\(([^)]+)\))?:\s*(.*)$'
)


def find_hook_logs(session_start: str, session_end: str,
                   project_path: Optional[str] = None) -> Optional[tuple[Path, Optional[Path]]]:
    """
    Find hook log files that overlap with the session time window.

    Args:
        session_start: ISO timestamp of session start
        session_end: ISO timestamp of session end
        project_path: Project directory path

    Returns:
        (main_log, agents_log) tuple or None if not found.
        agents_log may be None if only main log exists.
    """
    if not session_start:
        return None

    # Parse session start time
    try:
        session_start_dt = datetime.fromisoformat(session_start.replace("Z", "+00:00"))
    except (ValueError, AttributeError):
        return None

    # Search locations for .claude-logs/
    search_paths = []
    if project_path:
        search_paths.append(Path(project_path) / ".claude-logs")
    search_paths.append(Path.home() / ".claude" / ".claude-logs")

    for logs_dir in search_paths:
        if not logs_dir.exists():
            continue

        # Find log files (exclude -agents.log suffix for main logs)
        log_files = sorted(
            [f for f in logs_dir.glob("*.log")
             if not f.name.endswith("-agents.log") and not f.name.startswith(".")],
            key=lambda f: f.name,
            reverse=True  # Newest first
        )

        for log_file in log_files:
            # Parse timestamp from filename: YYYYMMDD_HHMMSS.log
            try:
                filename = log_file.stem  # e.g., "20251231_113235"
                log_dt = datetime.strptime(filename, "%Y%m%d_%H%M%S")

                # Check if log file time is within reasonable range of session
                # (within 24 hours before session start to session end)
                time_diff = (session_start_dt.replace(tzinfo=None) - log_dt).total_seconds()
                if -86400 <= time_diff <= 86400:  # Within 24 hours
                    # Found a matching log file
                    agents_log = logs_dir / f"{filename}-agents.log"
                    return (log_file, agents_log if agents_log.exists() else None)
            except ValueError:
                continue  # Skip files that don't match the naming pattern

    return None


def parse_hook_log(log_path: Path, log_date: str) -> list[dict]:
    """
    Parse hook log file into list of events.

    Args:
        log_path: Path to .log file
        log_date: Date string (YYYY-MM-DD) derived from filename

    Returns:
        List of event dicts with: timestamp, agent, event_type, details, source
    """
    events = []

    try:
        with open(log_path, encoding="utf-8") as f:
            for line in f:
                line = line.strip()
                if not line or line.startswith("="):  # Skip empty lines and separators
                    continue

                match = HOOK_LOG_PATTERN.match(line)
                if not match:
                    continue

                time_str, agent_id, event_type, param, details = match.groups()

                # Only include events we care about
                if event_type not in HOOK_EVENTS:
                    continue

                # Build ISO timestamp from log_date and time
                timestamp = f"{log_date}T{time_str}"

                event = {
                    "timestamp": timestamp,
                    "agent": agent_id,
                    "event_type": event_type,
                    "details": details.strip() if details else "",
                    "source": "hook",
                }

                # Handle PostToolUse specially - include tool name and status
                if event_type == "PostToolUse" and param:
                    event["tool_name"] = param
                    event["status"] = "error" if "error" in details.lower() else "success"

                events.append(event)

    except (OSError, IOError) as e:
        print(f"Warning: Could not read hook log {log_path}: {e}", file=sys.stderr)

    return events


def date_from_log_filename(log_path: Path) -> str:
    """Extract date string (YYYY-MM-DD) from log filename."""
    # Filename format: YYYYMMDD_HHMMSS.log
    filename = log_path.stem
    try:
        return f"{filename[:4]}-{filename[4:6]}-{filename[6:8]}"
    except (IndexError, ValueError):
        return datetime.now().strftime("%Y-%m-%d")


def encode_project_path(path: str) -> str:
    """Convert project path to Claude's encoded format."""
    # Both / and . are replaced with -
    return path.replace("/", "-").replace(".", "-")


def find_projects_dir() -> Path:
    """Find the Claude projects directory."""
    return Path.home() / ".claude" / "projects"


def find_session_files(session_id: Optional[str] = None,
                       project_path: Optional[str] = None,
                       latest: bool = False) -> tuple[Path, list[Path]]:
    """
    Find main session file and associated agent files.

    Returns:
        (main_transcript, list_of_agent_transcripts)
    """
    projects_dir = find_projects_dir()
    project_dir = None

    if project_path:
        encoded = encode_project_path(project_path)
        project_dir = projects_dir / encoded
        if not project_dir.exists():
            # Try with leading dash
            project_dir = projects_dir / f"-{encoded.lstrip('-')}"
        if not project_dir.exists():
            project_dir = None
    else:
        # Use current directory's project
        cwd = Path.cwd()
        encoded = encode_project_path(str(cwd))
        project_dir = projects_dir / encoded
        if not project_dir.exists():
            project_dir = projects_dir / f"-{encoded.lstrip('-')}"
        if not project_dir.exists():
            project_dir = None

    # If searching by session_id and no local project, search globally
    if session_id and not project_dir:
        print(f"Searching all projects for session {session_id}...", file=sys.stderr)
        for pdir in projects_dir.iterdir():
            if not pdir.is_dir():
                continue
            matches = [f for f in pdir.glob("*.jsonl")
                      if not f.name.startswith("agent-") and session_id in f.stem]
            if matches:
                project_dir = pdir
                break

    # Also search globally if session_id provided but not found locally
    if session_id and project_dir:
        local_matches = [f for f in project_dir.glob("*.jsonl")
                        if not f.name.startswith("agent-") and session_id in f.stem]
        if not local_matches:
            print(f"Session not in current project, searching all projects...", file=sys.stderr)
            for pdir in projects_dir.iterdir():
                if not pdir.is_dir():
                    continue
                matches = [f for f in pdir.glob("*.jsonl")
                          if not f.name.startswith("agent-") and session_id in f.stem]
                if matches:
                    project_dir = pdir
                    break

    if not project_dir or not project_dir.exists():
        raise FileNotFoundError(f"No project directory found with sessions")

    # Find main session files (exclude agent-*.jsonl)
    session_files = sorted(
        [f for f in project_dir.glob("*.jsonl") if not f.name.startswith("agent-")],
        key=lambda f: f.stat().st_mtime,
        reverse=True
    )

    if not session_files:
        raise FileNotFoundError(f"No session files found in {project_dir}")

    if latest:
        main_file = session_files[0]
    elif session_id:
        matches = [f for f in session_files if session_id in f.stem]
        if not matches:
            raise FileNotFoundError(f"Session {session_id} not found")
        main_file = matches[0]
    else:
        main_file = session_files[0]  # Default to latest

    # Find associated agent files (by modification time proximity)
    main_mtime = main_file.stat().st_mtime
    agent_files = sorted(
        project_dir.glob("agent-*.jsonl"),
        key=lambda f: f.stat().st_mtime
    )

    return main_file, agent_files


def extract_session_summary(filepath: Path) -> dict:
    """Extract summary and metadata from a session file."""
    session_id = filepath.stem
    summary = ""
    start_time = None
    end_time = None
    project = None

    try:
        with open(filepath) as f:
            for line in f:
                line = line.strip()
                if not line:
                    continue
                try:
                    entry = json.loads(line)

                    # Look for summary entry
                    if entry.get("type") == "summary":
                        summary = entry.get("summary", "")

                    # Track timestamps
                    ts = entry.get("timestamp")
                    if ts:
                        if not start_time or ts < start_time:
                            start_time = ts
                        if not end_time or ts > end_time:
                            end_time = ts

                    # Get project
                    if not project and entry.get("cwd"):
                        project = entry["cwd"]

                except json.JSONDecodeError:
                    continue
    except Exception:
        pass

    # Calculate duration
    duration_mins = None
    if start_time and end_time:
        try:
            start_dt = datetime.fromisoformat(start_time.replace("Z", "+00:00"))
            end_dt = datetime.fromisoformat(end_time.replace("Z", "+00:00"))
            duration_mins = round((end_dt - start_dt).total_seconds() / 60, 1)
        except:
            pass

    return {
        "id": session_id,
        "file": str(filepath),
        "summary": summary,
        "start": start_time,
        "end": end_time,
        "duration_mins": duration_mins,
        "project": project,
        "mtime": filepath.stat().st_mtime,
    }


def list_sessions(project_path: Optional[str] = None, fallback_global: bool = True) -> list[dict]:
    """
    List all sessions with their summaries.

    Args:
        project_path: Specific project to search in
        fallback_global: If True and no sessions found locally, search all projects

    Returns list of session info dicts sorted by modification time (newest first).
    """
    projects_dir = find_projects_dir()
    project_dirs = []

    if project_path:
        encoded = encode_project_path(project_path)
        project_dir = projects_dir / encoded
        if not project_dir.exists():
            project_dir = projects_dir / f"-{encoded.lstrip('-')}"
        if project_dir.exists():
            project_dirs = [project_dir]
    else:
        # Use current directory's project
        cwd = Path.cwd()
        encoded = encode_project_path(str(cwd))
        project_dir = projects_dir / encoded
        if not project_dir.exists():
            project_dir = projects_dir / f"-{encoded.lstrip('-')}"
        if project_dir.exists():
            project_dirs = [project_dir]

    sessions = []
    for project_dir in project_dirs:
        # Find main session files (exclude agent-*.jsonl)
        session_files = [f for f in project_dir.glob("*.jsonl")
                        if not f.name.startswith("agent-")]

        for filepath in session_files:
            sessions.append(extract_session_summary(filepath))

    # Fallback: if no sessions found and fallback enabled, search all projects
    if not sessions and fallback_global and not project_path:
        print("No sessions in current directory, searching all projects...", file=sys.stderr)
        for project_dir in projects_dir.iterdir():
            if not project_dir.is_dir():
                continue
            session_files = [f for f in project_dir.glob("*.jsonl")
                            if not f.name.startswith("agent-")]
            for filepath in session_files:
                sessions.append(extract_session_summary(filepath))

    # Sort by modification time (newest first)
    sessions.sort(key=lambda s: s.get("mtime", 0), reverse=True)

    return sessions


def parse_jsonl(filepath: Path) -> list[dict]:
    """Parse a JSONL file into list of entries."""
    entries = []
    with open(filepath) as f:
        for line_num, line in enumerate(f, 1):
            line = line.strip()
            if not line:
                continue
            try:
                entries.append(json.loads(line))
            except json.JSONDecodeError as e:
                print(f"Warning: Failed to parse line {line_num} in {filepath}: {e}",
                      file=sys.stderr)
    return entries


def extract_all_content(entry: dict) -> list[dict]:
    """Extract all content blocks from a transcript entry."""
    items = []
    message = entry.get("message", {})
    content = message.get("content", [])
    timestamp = entry.get("timestamp", "")
    entry_type = entry.get("type", "")

    if isinstance(content, str):
        # Simple text content
        if content.strip():
            # Use "user" type for user messages to distinguish them
            item_type = "user" if entry_type == "user" else "text"
            items.append({
                "type": item_type,
                "text": content[:1000],
                "timestamp": timestamp,
                "role": entry_type,
            })
        return items

    if not isinstance(content, list):
        return items

    for item in content:
        # Handle string items in content array
        if isinstance(item, str):
            if item.strip():
                content_type = "user" if entry_type == "user" else "text"
                items.append({
                    "type": content_type,
                    "text": item[:1000],
                    "timestamp": timestamp,
                    "role": entry_type,
                })
            continue

        if not isinstance(item, dict):
            continue

        item_type = item.get("type")

        # Also check for text directly in dict without type field
        if not item_type and "text" in item:
            text = item.get("text", "")
            if text.strip():
                content_type = "user" if entry_type == "user" else "text"
                items.append({
                    "type": content_type,
                    "text": text[:1000],
                    "timestamp": timestamp,
                    "role": entry_type,
                })
            continue

        if item_type == "thinking":
            items.append({
                "type": "thinking",
                "text": item.get("thinking", "")[:2000],
                "timestamp": timestamp,
            })
        elif item_type == "text":
            text = item.get("text", "")
            if text.strip():
                # Use "user" type for user messages to distinguish them
                content_type = "user" if entry_type == "user" else "text"
                items.append({
                    "type": content_type,
                    "text": text[:1000],
                    "timestamp": timestamp,
                    "role": entry_type,
                })
        elif item_type == "tool_use":
            items.append({
                "type": "tool_use",
                "id": item.get("id", ""),
                "name": item.get("name", "unknown"),
                "input": item.get("input", {}),
                "timestamp": timestamp,
            })
        elif item_type == "tool_result":
            result_content = item.get("content", "")
            if isinstance(result_content, list):
                # Handle complex tool results
                result_content = str(result_content)[:500]
            else:
                result_content = str(result_content)[:500]
            items.append({
                "type": "tool_result",
                "tool_use_id": item.get("tool_use_id", ""),
                "content": result_content,
                "is_error": item.get("is_error", False),
                "timestamp": timestamp,
            })

    return items


def is_warmup_agent(entries: list[dict]) -> bool:
    """Check if this is a warmup agent (should be filtered out)."""
    for entry in entries:
        if entry.get("type") == "user":
            content = entry.get("message", {}).get("content", "")
            if isinstance(content, str):
                # Check for warmup indicators
                if content.strip().lower() in ["warmup", "warmup..."]:
                    return True
            elif isinstance(content, list):
                for item in content:
                    if isinstance(item, dict) and item.get("type") == "text":
                        text = item.get("text", "").strip().lower()
                        if text in ["warmup", "warmup..."]:
                            return True
            break  # Only check first user message
    return False


def get_first_user_prompt(entries: list[dict]) -> str:
    """Get the first user prompt for an agent."""
    for entry in entries:
        if entry.get("type") == "user":
            content = entry.get("message", {}).get("content", "")
            if isinstance(content, str):
                if content.strip() and content.strip().lower() not in ["warmup", "warmup..."]:
                    return content[:200]
            elif isinstance(content, list):
                for item in content:
                    if isinstance(item, str) and item.strip():
                        return item[:200]
                    if isinstance(item, dict):
                        # Check for text type
                        if item.get("type") == "text":
                            text = item.get("text", "")
                            if text.strip():
                                return text[:200]
                        # Also check for text field without type
                        elif "text" in item and item.get("text", "").strip():
                            return item["text"][:200]
            # Don't break - keep looking for a useful prompt
    return ""


def build_session_data(main_file: Path, agent_files: list[Path]) -> dict:
    """
    Build unified session data from main and agent transcripts.
    Now extracts full trace: thinking, text, tool_use, tool_result.
    """
    main_entries = parse_jsonl(main_file)

    # Extract session metadata
    session_id = None
    start_time = None
    end_time = None
    project = None

    for entry in main_entries:
        if not session_id and entry.get("sessionId"):
            session_id = entry["sessionId"]
        if entry.get("timestamp"):
            ts = entry["timestamp"]
            if not start_time or ts < start_time:
                start_time = ts
            if not end_time or ts > end_time:
                end_time = ts
        if not project and entry.get("cwd"):
            project = entry["cwd"]

    # Build main agent trace
    main_trace = []
    tool_results = {}  # Map tool_use_id -> result

    for entry in main_entries:
        for item in extract_all_content(entry):
            if item["type"] == "tool_result":
                tool_results[item["tool_use_id"]] = item
            else:
                main_trace.append(item)

    # Attach results to tool calls
    for item in main_trace:
        if item["type"] == "tool_use" and item["id"] in tool_results:
            item["result"] = tool_results[item["id"]]

    main_agent = {
        "id": "main",
        "type": "orchestrator",
        "file": str(main_file),
        "start": start_time,
        "end": end_time,
        "prompt": "",
        "trace": main_trace,
        "tool_calls": [t for t in main_trace if t["type"] == "tool_use"],
    }

    agents = [main_agent]
    skipped_warmup = 0

    # Process agent files
    for agent_file in agent_files:
        agent_entries = parse_jsonl(agent_file)
        if not agent_entries:
            continue

        # Filter out warmup agents
        if is_warmup_agent(agent_entries):
            skipped_warmup += 1
            continue

        agent_id = None
        agent_start = None
        agent_end = None
        agent_type = "subagent"

        for entry in agent_entries:
            if not agent_id and entry.get("agentId"):
                agent_id = entry["agentId"]
            if entry.get("timestamp"):
                ts = entry["timestamp"]
                if not agent_start or ts < agent_start:
                    agent_start = ts
                if not agent_end or ts > agent_end:
                    agent_end = ts

        # Get first user prompt
        first_prompt = get_first_user_prompt(agent_entries)

        # Determine agent type from prompt
        prompt_lower = first_prompt.lower()
        if "explore" in prompt_lower or "codebase" in prompt_lower or "search" in prompt_lower:
            agent_type = "Explore"
        elif "plan" in prompt_lower or "design" in prompt_lower or "architect" in prompt_lower:
            agent_type = "Plan"
        elif "claude-code-guide" in prompt_lower or "documentation" in prompt_lower or "how to" in prompt_lower:
            agent_type = "claude-code-guide"
        elif "general" in prompt_lower or "research" in prompt_lower:
            agent_type = "general-purpose"

        # Build agent trace
        agent_trace = []
        agent_results = {}

        for entry in agent_entries:
            for item in extract_all_content(entry):
                if item["type"] == "tool_result":
                    agent_results[item["tool_use_id"]] = item
                else:
                    agent_trace.append(item)

        # Attach results to tool calls
        for item in agent_trace:
            if item["type"] == "tool_use" and item["id"] in agent_results:
                item["result"] = agent_results[item["id"]]

        agent_data = {
            "id": agent_id or agent_file.stem,
            "type": agent_type,
            "file": str(agent_file),
            "parent": "main",
            "start": agent_start,
            "end": agent_end,
            "prompt": first_prompt,
            "trace": agent_trace,
            "tool_calls": [t for t in agent_trace if t["type"] == "tool_use"],
        }

        agents.append(agent_data)

    # Build unified timeline from all traces
    timeline = []
    for agent in agents:
        agent_id = agent["id"]
        agent_type = agent["type"]

        for item in agent.get("trace", []):
            event = {
                "time": item.get("timestamp", ""),
                "agent": agent_id,
                "agent_type": agent_type,
                "event": item["type"],
            }

            if item["type"] == "user":
                event["text"] = item["text"]
                event["role"] = "user"
            elif item["type"] == "thinking":
                event["text"] = item["text"]
            elif item["type"] == "text":
                event["text"] = item["text"]
                event["role"] = item.get("role", "")
            elif item["type"] == "tool_use":
                event["tool_name"] = item["name"]
                event["tool_input"] = item["input"]
                event["tool_id"] = item["id"]
                if "result" in item:
                    event["tool_result"] = item["result"]

            timeline.append(event)

    # Integrate hook log events (lifecycle events not in JSONL)
    hook_logs = find_hook_logs(start_time, end_time, project)
    hook_event_count = 0
    if hook_logs:
        main_log, agents_log = hook_logs
        if main_log:
            log_date = date_from_log_filename(main_log)
            hook_events = parse_hook_log(main_log, log_date)
            for he in hook_events:
                # Convert hook event to timeline event format
                event = {
                    "time": he["timestamp"],
                    "agent": "main",  # Hook logs use "orchestrator" but we map to main agent
                    "agent_type": "orchestrator",
                    "source": "hook",
                }

                if he["event_type"] == "PostToolUse":
                    event["event"] = "post_tool_use"
                    event["tool_name"] = he.get("tool_name", "unknown")
                    event["status"] = he.get("status", "success")
                    event["details"] = he.get("details", "")
                else:
                    event["event"] = "lifecycle"
                    event["event_type"] = he["event_type"]
                    event["details"] = he.get("details", "")

                timeline.append(event)
                hook_event_count += 1

            print(f"Integrated {hook_event_count} hook events from {main_log.name}", file=sys.stderr)

    # Sort timeline by timestamp
    timeline.sort(key=lambda x: x.get("time", ""))

    # Calculate duration
    duration_mins = None
    if start_time and end_time:
        try:
            start_dt = datetime.fromisoformat(start_time.replace("Z", "+00:00"))
            end_dt = datetime.fromisoformat(end_time.replace("Z", "+00:00"))
            duration_mins = round((end_dt - start_dt).total_seconds() / 60, 1)
        except:
            pass

    # Count events by type
    event_counts = {}
    for e in timeline:
        event_counts[e["event"]] = event_counts.get(e["event"], 0) + 1

    return {
        "session": {
            "id": session_id,
            "file": str(main_file),
            "start": start_time,
            "end": end_time,
            "duration_mins": duration_mins,
            "project": project,
        },
        "agents": agents,
        "timeline": timeline,
        "stats": {
            "total_agents": len(agents),
            "skipped_warmup": skipped_warmup,
            "total_tool_calls": sum(len(a["tool_calls"]) for a in agents),
            "event_counts": event_counts,
            "tools_by_agent": {a["id"]: len(a["tool_calls"]) for a in agents},
        }
    }


def generate_html(data: dict, all_sessions: list[dict] = None) -> str:
    """Generate HTML visualization from session data with full trace support."""

    # Escape JSON for embedding in script tag
    json_str = json.dumps(data, ensure_ascii=True)
    json_str = json_str.replace("</", "<\\/")

    # Build sessions list for selector
    sessions_json = "[]"
    if all_sessions:
        sessions_json = json.dumps(all_sessions, ensure_ascii=True)
        sessions_json = sessions_json.replace("</", "<\\/")

    session_id = data["session"]["id"] or "Unknown"
    session_id_short = session_id[:8] if session_id != "Unknown" else session_id
    project = data["session"]["project"] or "Unknown"
    duration = data["session"]["duration_mins"] or "?"
    total_agents = data["stats"]["total_agents"]
    total_tools = data["stats"]["total_tool_calls"]
    skipped = data["stats"].get("skipped_warmup", 0)
    event_counts = data["stats"].get("event_counts", {})

    html_template = '''<!DOCTYPE html>
<html lang="en">
<head>
    <meta charset="UTF-8">
    <meta name="viewport" content="width=device-width, initial-scale=1.0">
    <title>Claude Session: {session_id_short}</title>
    <style>
        * {{ box-sizing: border-box; margin: 0; padding: 0; }}
        body {{
            font-family: -apple-system, BlinkMacSystemFont, 'Segoe UI', Roboto, sans-serif;
            background: #1a1a2e;
            color: #eee;
            padding: 20px;
            line-height: 1.5;
        }}
        .header {{
            background: #16213e;
            padding: 20px;
            border-radius: 8px;
            margin-bottom: 20px;
        }}
        .header-top {{
            display: flex;
            justify-content: space-between;
            align-items: flex-start;
            margin-bottom: 10px;
        }}
        .header h1 {{ font-size: 1.5em; margin-bottom: 10px; }}
        .session-selector {{
            display: flex;
            flex-direction: column;
            align-items: flex-end;
            gap: 5px;
        }}
        .session-selector select {{
            padding: 8px 12px;
            background: #0f3460;
            border: 1px solid #333;
            color: #eee;
            border-radius: 4px;
            font-size: 14px;
            max-width: 350px;
        }}
        .session-selector .hint {{
            font-size: 0.75em;
            color: #666;
        }}
        .session-cmd {{
            display: none;
            margin-top: 5px;
            padding: 8px 12px;
            background: #0a1628;
            border-radius: 4px;
            font-family: monospace;
            font-size: 0.85em;
            color: #4da8da;
        }}
        .session-cmd.visible {{ display: block; }}
        .header .meta {{ color: #888; font-size: 0.9em; }}
        .header .meta div {{ margin-bottom: 4px; }}
        .stats {{
            display: flex;
            gap: 15px;
            margin-top: 15px;
            flex-wrap: wrap;
        }}
        .stat {{
            background: #0f3460;
            padding: 10px 15px;
            border-radius: 6px;
        }}
        .stat-value {{ font-size: 1.3em; font-weight: bold; color: #e94560; }}
        .stat-label {{ font-size: 0.75em; color: #888; }}
        .filter-bar {{
            margin-bottom: 15px;
            display: flex;
            gap: 10px;
            flex-wrap: wrap;
            align-items: center;
        }}
        .filter-bar select, .filter-bar input, .filter-bar label {{
            padding: 8px 12px;
            background: #16213e;
            border: 1px solid #333;
            color: #eee;
            border-radius: 4px;
            font-size: 14px;
        }}
        .filter-bar label {{
            display: flex;
            align-items: center;
            gap: 6px;
            cursor: pointer;
        }}
        .filter-bar input[type="checkbox"] {{
            width: 16px;
            height: 16px;
        }}
        .tabs {{
            display: flex;
            gap: 10px;
            margin-bottom: 20px;
        }}
        .tab {{
            padding: 10px 20px;
            background: #16213e;
            border: none;
            color: #888;
            cursor: pointer;
            border-radius: 6px;
            font-size: 1em;
        }}
        .tab.active {{ background: #e94560; color: white; }}
        .view {{ display: none; }}
        .view.active {{ display: block; }}

        /* Timeline View */
        .timeline {{ padding: 10px; max-width: 1200px; }}
        .trace-item {{
            margin-bottom: 8px;
            border-radius: 6px;
            overflow: hidden;
        }}
        .trace-header {{
            display: flex;
            align-items: flex-start;
            padding: 10px 12px;
            cursor: pointer;
            gap: 10px;
        }}
        .trace-header:hover {{ filter: brightness(1.1); }}
        .trace-time {{
            width: 75px;
            flex-shrink: 0;
            font-size: 0.75em;
            color: #666;
            font-family: monospace;
        }}
        .trace-agent {{
            width: 90px;
            flex-shrink: 0;
            padding: 2px 6px;
            border-radius: 3px;
            font-size: 0.7em;
            text-align: center;
        }}
        .trace-type {{
            width: 70px;
            flex-shrink: 0;
            padding: 2px 6px;
            border-radius: 3px;
            font-size: 0.7em;
            text-align: center;
            font-weight: bold;
        }}
        .trace-summary {{
            flex: 1;
            font-size: 0.9em;
            white-space: nowrap;
            overflow: hidden;
            text-overflow: ellipsis;
        }}
        .trace-detail {{
            display: none;
            padding: 10px 12px 12px 12px;
            background: rgba(0,0,0,0.2);
            font-size: 0.85em;
            white-space: pre-wrap;
            word-break: break-word;
            max-height: 300px;
            overflow-y: auto;
            font-family: monospace;
            color: #aaa;
        }}
        .trace-item.expanded .trace-detail {{ display: block; }}

        /* Event type colors */
        .trace-thinking {{ background: #1e293b; }}
        .trace-thinking .trace-type {{ background: #6366f1; color: white; }}
        .trace-text {{ background: #1a2e1a; }}
        .trace-text .trace-type {{ background: #22c55e; color: white; }}
        .trace-user {{ background: #1e3a5f; }}
        .trace-user .trace-type {{ background: #3b82f6; color: white; }}
        .trace-tool_use {{ background: #16213e; }}
        .trace-tool_use .trace-type {{ background: #e94560; color: white; }}

        /* Lifecycle events (Stop, SessionStart, etc.) */
        .trace-lifecycle {{ background: #2d1f3d; }}
        .trace-lifecycle .trace-type {{ background: #9333ea; color: white; }}

        /* PostToolUse success */
        .trace-post_tool_use {{ background: #1a2e1a; }}
        .trace-post_tool_use .trace-type {{ background: #22c55e; color: white; }}

        /* PostToolUse error */
        .trace-post_tool_use.error {{ background: #2e1a1a; }}
        .trace-post_tool_use.error .trace-type {{ background: #ef4444; color: white; }}

        /* Agent colors */
        .agent-orchestrator {{ background: #0f3460; color: #4da8da; }}
        .agent-Explore {{ background: #1a472a; color: #4ade80; }}
        .agent-Plan {{ background: #4a3728; color: #fbbf24; }}
        .agent-subagent {{ background: #3d2952; color: #a78bfa; }}
        .agent-claude-code-guide {{ background: #2d3748; color: #68d391; }}
        .agent-general-purpose {{ background: #374151; color: #9ca3af; }}

        /* Tool result */
        .tool-result {{
            margin-top: 8px;
            padding: 8px;
            background: #0a1628;
            border-radius: 4px;
            border-left: 3px solid #22c55e;
        }}
        .tool-result.error {{ border-left-color: #ef4444; }}
        .tool-result-label {{ font-size: 0.75em; color: #666; margin-bottom: 4px; }}

        /* Tree View */
        .tree {{ padding: 10px; }}
        .tree-agent {{
            margin-bottom: 15px;
            background: #16213e;
            border-radius: 8px;
            overflow: hidden;
        }}
        .tree-agent-header {{
            padding: 12px 15px;
            cursor: pointer;
            display: flex;
            justify-content: space-between;
            align-items: center;
        }}
        .tree-agent-header:hover {{ background: #1e2a4a; }}
        .tree-agent-name {{ font-weight: bold; }}
        .tree-agent-prompt {{
            font-size: 0.8em;
            color: #888;
            margin-top: 4px;
            font-style: italic;
        }}
        .tree-agent-stats {{ font-size: 0.85em; color: #888; }}
        .tree-agent-trace {{
            padding: 0 15px 15px 15px;
            display: none;
            max-height: 500px;
            overflow-y: auto;
        }}
        .tree-agent.expanded .tree-agent-trace {{ display: block; }}
        .tree-item {{
            padding: 6px 10px;
            margin-top: 4px;
            border-radius: 4px;
            font-size: 0.85em;
        }}
        .tree-item-user {{ background: #1e3a5f; border-left: 3px solid #3b82f6; }}
        .tree-item-thinking {{ background: #1e293b; border-left: 3px solid #6366f1; }}
        .tree-item-text {{ background: #1a2e1a; border-left: 3px solid #22c55e; }}
        .tree-item-tool {{ background: #0f3460; border-left: 3px solid #e94560; }}
        .tree-item-time {{ color: #666; font-family: monospace; font-size: 0.8em; }}
        .tree-item-label {{ font-weight: bold; margin-left: 8px; }}
        .tree-item-content {{ margin-top: 4px; color: #aaa; font-size: 0.9em; }}
        .expand-icon {{ transition: transform 0.2s; display: inline-block; margin-right: 8px; }}
        .tree-agent.expanded .expand-icon {{ transform: rotate(90deg); }}
    </style>
</head>
<body>
    <div class="header">
        <div class="header-top">
            <div>
                <h1>Agent Trace Viewer</h1>
                <div class="meta">
                    <div>Project: {project}</div>
                    <div>Duration: {duration} minutes</div>
                </div>
            </div>
            <div class="session-selector">
                <select id="sessionSelect">
                    <option value="{session_id}">{session_id_short} - (current)</option>
                </select>
                <div class="hint">Select a session to view</div>
                <div id="sessionCmd" class="session-cmd"></div>
            </div>
        </div>
        <div class="stats">
            <div class="stat">
                <div class="stat-value">{total_agents}</div>
                <div class="stat-label">Agents</div>
            </div>
            <div class="stat">
                <div class="stat-value">{total_tools}</div>
                <div class="stat-label">Tool Calls</div>
            </div>
            <div class="stat">
                <div class="stat-value">{user_count}</div>
                <div class="stat-label">User Prompts</div>
            </div>
            <div class="stat">
                <div class="stat-value">{thinking_count}</div>
                <div class="stat-label">Thinking</div>
            </div>
            <div class="stat">
                <div class="stat-value">{text_count}</div>
                <div class="stat-label">Responses</div>
            </div>
            <div class="stat">
                <div class="stat-value">{lifecycle_count}</div>
                <div class="stat-label">Lifecycle</div>
            </div>
        </div>
    </div>

    <div class="filter-bar">
        <select id="agentFilter">
            <option value="">All Agents</option>
        </select>
        <select id="eventFilter">
            <option value="">All Events</option>
            <option value="user">User Prompt</option>
            <option value="thinking">Thinking</option>
            <option value="tool_use">Tool Use</option>
            <option value="text">Text Response</option>
            <option value="lifecycle">Lifecycle (Stop, SessionStart...)</option>
            <option value="post_tool_use">PostToolUse</option>
        </select>
        <input type="text" id="searchInput" placeholder="Search...">
        <label><input type="checkbox" id="showUser" checked> User</label>
        <label><input type="checkbox" id="showThinking" checked> Thinking</label>
        <label><input type="checkbox" id="showText" checked> Responses</label>
        <label><input type="checkbox" id="showTools" checked> Tools</label>
        <label><input type="checkbox" id="showLifecycle" checked> Lifecycle</label>
    </div>

    <div class="tabs">
        <button class="tab active" data-view="timeline">Timeline</button>
        <button class="tab" data-view="tree">Tree</button>
    </div>

    <div id="timeline" class="view active">
        <div class="timeline"></div>
    </div>

    <div id="tree" class="view">
        <div class="tree"></div>
    </div>

    <script>
        const data = {json_str};
        const allSessions = {sessions_json};
        const currentSessionId = '{session_id}';

        // Populate session selector
        const sessionSelect = document.getElementById('sessionSelect');
        const sessionCmd = document.getElementById('sessionCmd');

        if (allSessions && allSessions.length > 0) {{
            // Clear default option
            sessionSelect.innerHTML = '';

            allSessions.forEach(s => {{
                const opt = document.createElement('option');
                opt.value = s.id;
                const shortId = s.id.substring(0, 8);
                const summary = s.summary ? s.summary.substring(0, 40) : '(no summary)';
                const duration = s.duration_mins ? s.duration_mins + 'm' : '?';
                opt.textContent = shortId + ' - ' + duration + ' - ' + summary;
                if (s.id === currentSessionId) {{
                    opt.selected = true;
                    opt.textContent += ' (current)';
                }}
                sessionSelect.appendChild(opt);
            }});
        }}

        sessionSelect.addEventListener('change', function() {{
            const selectedId = this.value;
            if (selectedId !== currentSessionId) {{
                sessionCmd.textContent = 'Run: claude-session-analyzer ' + selectedId.substring(0, 8) + ' --open';
                sessionCmd.classList.add('visible');
            }} else {{
                sessionCmd.classList.remove('visible');
            }}
        }});

        // Populate agent filter
        const agentFilter = document.getElementById('agentFilter');
        data.agents.forEach(a => {{
            const opt = document.createElement('option');
            opt.value = a.id;
            opt.textContent = a.type + ' (' + a.id.substring(0, 8) + ')';
            agentFilter.appendChild(opt);
        }});

        function formatTime(ts) {{
            if (!ts) return '';
            const d = new Date(ts);
            return d.toLocaleTimeString();
        }}

        function escapeHtml(str) {{
            if (!str) return '';
            return String(str).replace(/&/g, '&amp;').replace(/</g, '&lt;').replace(/>/g, '&gt;');
        }}

        function formatInput(input) {{
            if (!input) return '';
            if (input.file_path) return input.file_path;
            if (input.command) return input.command.substring(0, 100);
            if (input.pattern) return '"' + input.pattern + '"';
            if (input.query) return input.query;
            if (input.url) return input.url;
            if (input.description) return input.description;
            return JSON.stringify(input).substring(0, 100);
        }}

        function getAgentClass(type) {{
            const classes = {{
                'orchestrator': 'agent-orchestrator',
                'Explore': 'agent-Explore',
                'Plan': 'agent-Plan',
                'claude-code-guide': 'agent-claude-code-guide',
                'general-purpose': 'agent-general-purpose',
            }};
            return classes[type] || 'agent-subagent';
        }}

        function getSummary(e) {{
            if (e.event === 'user') return escapeHtml((e.text || '').substring(0, 100));
            if (e.event === 'thinking') return escapeHtml((e.text || '').substring(0, 100));
            if (e.event === 'text') return escapeHtml((e.text || '').substring(0, 100));
            if (e.event === 'tool_use') return escapeHtml(e.tool_name + ': ' + formatInput(e.tool_input));
            if (e.event === 'lifecycle') return escapeHtml(e.event_type + ': ' + (e.details || ''));
            if (e.event === 'post_tool_use') return escapeHtml(e.tool_name + ': ' + e.status);
            return '';
        }}

        function getDetail(e) {{
            let detail = '';
            if (e.event === 'user') {{
                detail = escapeHtml(e.text || '');
            }} else if (e.event === 'thinking') {{
                detail = escapeHtml(e.text || '');
            }} else if (e.event === 'text') {{
                detail = escapeHtml(e.text || '');
            }} else if (e.event === 'tool_use') {{
                detail = 'Input:\\n' + escapeHtml(JSON.stringify(e.tool_input, null, 2));
                if (e.tool_result) {{
                    const isError = e.tool_result.is_error;
                    detail += '\\n\\n<div class="tool-result' + (isError ? ' error' : '') + '">';
                    detail += '<div class="tool-result-label">' + (isError ? 'Error:' : 'Result:') + '</div>';
                    detail += escapeHtml(e.tool_result.content || '');
                    detail += '</div>';
                }}
            }} else if (e.event === 'lifecycle') {{
                detail = 'Event: ' + escapeHtml(e.event_type) + '\\nDetails: ' + escapeHtml(e.details || '(none)');
            }} else if (e.event === 'post_tool_use') {{
                detail = 'Tool: ' + escapeHtml(e.tool_name) + '\\nStatus: ' + escapeHtml(e.status) + '\\nDetails: ' + escapeHtml(e.details || '(none)');
            }}
            return detail;
        }}

        function renderTimeline() {{
            const container = document.querySelector('.timeline');
            const agentVal = agentFilter.value;
            const eventVal = document.getElementById('eventFilter').value;
            const search = document.getElementById('searchInput').value.toLowerCase();
            const showUser = document.getElementById('showUser').checked;
            const showThinking = document.getElementById('showThinking').checked;
            const showText = document.getElementById('showText').checked;
            const showTools = document.getElementById('showTools').checked;
            const showLifecycle = document.getElementById('showLifecycle').checked;

            let filtered = data.timeline.filter(e => {{
                if (e.event === 'user' && !showUser) return false;
                if (e.event === 'thinking' && !showThinking) return false;
                if (e.event === 'text' && !showText) return false;
                if (e.event === 'tool_use' && !showTools) return false;
                if ((e.event === 'lifecycle' || e.event === 'post_tool_use') && !showLifecycle) return false;
                return true;
            }});

            if (agentVal) filtered = filtered.filter(e => e.agent === agentVal);
            if (eventVal) filtered = filtered.filter(e => e.event === eventVal);
            if (search) {{
                filtered = filtered.filter(e => {{
                    const summary = getSummary(e).toLowerCase();
                    return summary.includes(search);
                }});
            }}

            let html = '';
            filtered.forEach((e, idx) => {{
                let eventClass = 'trace-' + e.event;
                // Add error class for post_tool_use with error status
                if (e.event === 'post_tool_use' && e.status === 'error') {{
                    eventClass += ' error';
                }}
                html += '<div class="trace-item ' + eventClass + '" data-idx="' + idx + '">';
                html += '<div class="trace-header">';
                html += '<div class="trace-time">' + formatTime(e.time) + '</div>';
                html += '<div class="trace-agent ' + getAgentClass(e.agent_type) + '">' + escapeHtml(e.agent_type) + '</div>';
                html += '<div class="trace-type">' + e.event.replace('_', ' ') + '</div>';
                html += '<div class="trace-summary">' + getSummary(e) + '</div>';
                html += '</div>';
                html += '<div class="trace-detail">' + getDetail(e) + '</div>';
                html += '</div>';
            }});

            container.innerHTML = html || '<p style="color:#666;padding:20px;">No events match the filter</p>';

            // Add click handlers for expand/collapse
            container.querySelectorAll('.trace-header').forEach(header => {{
                header.addEventListener('click', function() {{
                    this.parentElement.classList.toggle('expanded');
                }});
            }});
        }}

        function renderTree() {{
            const container = document.querySelector('.tree');
            let html = '';

            data.agents.forEach(agent => {{
                const traceCount = (agent.trace || []).length;
                html += '<div class="tree-agent">';
                html += '<div class="tree-agent-header ' + getAgentClass(agent.type) + '">';
                html += '<div>';
                html += '<span class="tree-agent-name"><span class="expand-icon">▶</span>' + escapeHtml(agent.type) + ' (' + agent.id.substring(0, 8) + ')</span>';
                if (agent.prompt) {{
                    html += '<div class="tree-agent-prompt">"' + escapeHtml(agent.prompt.substring(0, 80)) + '..."</div>';
                }}
                html += '</div>';
                html += '<span class="tree-agent-stats">' + traceCount + ' events, ' + agent.tool_calls.length + ' tools</span>';
                html += '</div>';
                html += '<div class="tree-agent-trace">';

                (agent.trace || []).forEach(item => {{
                    if (item.type === 'user') {{
                        html += '<div class="tree-item tree-item-user">';
                        html += '<span class="tree-item-time">' + formatTime(item.timestamp) + '</span>';
                        html += '<span class="tree-item-label">USER</span>';
                        html += '<div class="tree-item-content">' + escapeHtml((item.text || '').substring(0, 200)) + '...</div>';
                        html += '</div>';
                    }} else if (item.type === 'thinking') {{
                        html += '<div class="tree-item tree-item-thinking">';
                        html += '<span class="tree-item-time">' + formatTime(item.timestamp) + '</span>';
                        html += '<span class="tree-item-label">THINKING</span>';
                        html += '<div class="tree-item-content">' + escapeHtml((item.text || '').substring(0, 200)) + '...</div>';
                        html += '</div>';
                    }} else if (item.type === 'text') {{
                        html += '<div class="tree-item tree-item-text">';
                        html += '<span class="tree-item-time">' + formatTime(item.timestamp) + '</span>';
                        html += '<span class="tree-item-label">RESPONSE</span>';
                        html += '<div class="tree-item-content">' + escapeHtml((item.text || '').substring(0, 200)) + '...</div>';
                        html += '</div>';
                    }} else if (item.type === 'tool_use') {{
                        html += '<div class="tree-item tree-item-tool">';
                        html += '<span class="tree-item-time">' + formatTime(item.timestamp) + '</span>';
                        html += '<span class="tree-item-label">' + escapeHtml(item.name) + '</span>';
                        html += '<div class="tree-item-content">' + escapeHtml(formatInput(item.input)) + '</div>';
                        if (item.result) {{
                            html += '<div class="tool-result' + (item.result.is_error ? ' error' : '') + '">';
                            html += '<div class="tool-result-label">Result:</div>';
                            html += escapeHtml((item.result.content || '').substring(0, 200));
                            html += '</div>';
                        }}
                        html += '</div>';
                    }}
                }});

                html += '</div></div>';
            }});

            container.innerHTML = html;

            // Toggle expand
            container.querySelectorAll('.tree-agent-header').forEach(header => {{
                header.addEventListener('click', function() {{
                    this.parentElement.classList.toggle('expanded');
                }});
            }});
        }}

        // Tab switching
        document.querySelectorAll('.tab').forEach(tab => {{
            tab.addEventListener('click', function() {{
                document.querySelectorAll('.tab').forEach(t => t.classList.remove('active'));
                document.querySelectorAll('.view').forEach(v => v.classList.remove('active'));
                this.classList.add('active');
                document.getElementById(this.dataset.view).classList.add('active');
            }});
        }});

        // Filter events
        agentFilter.addEventListener('change', renderTimeline);
        document.getElementById('eventFilter').addEventListener('change', renderTimeline);
        document.getElementById('searchInput').addEventListener('input', renderTimeline);
        document.getElementById('showUser').addEventListener('change', renderTimeline);
        document.getElementById('showThinking').addEventListener('change', renderTimeline);
        document.getElementById('showText').addEventListener('change', renderTimeline);
        document.getElementById('showTools').addEventListener('change', renderTimeline);
        document.getElementById('showLifecycle').addEventListener('change', renderTimeline);

        // Initial render
        renderTimeline();
        renderTree();
    </script>
</body>
</html>'''

    # Calculate lifecycle count (lifecycle + post_tool_use events)
    lifecycle_count = event_counts.get("lifecycle", 0) + event_counts.get("post_tool_use", 0)

    return html_template.format(
        session_id_short=session_id_short,
        session_id=session_id,
        project=project,
        duration=duration,
        total_agents=total_agents,
        total_tools=total_tools,
        user_count=event_counts.get("user", 0),
        thinking_count=event_counts.get("thinking", 0),
        text_count=event_counts.get("text", 0),
        lifecycle_count=lifecycle_count,
        json_str=json_str,
        sessions_json=sessions_json
    )


def generate_digest(data: dict) -> str:
    """Generate a concise markdown digest for feeding into a new Claude session."""
    lines = []

    session = data["session"]
    stats = data["stats"]
    timeline = data["timeline"]
    agents = data["agents"]

    # Header
    session_id = session.get("id", "unknown")[:8]
    lines.append(f"# Session Digest: {session_id}")
    lines.append("")
    lines.append(f"**Project:** {session.get('project', 'unknown')}")
    lines.append(f"**Duration:** {session.get('duration_mins', '?')} minutes")
    lines.append(f"**Agents:** {stats.get('total_agents', 0)} ({', '.join(a['type'] for a in agents[:5])})")
    lines.append("")

    # User prompts
    user_prompts = [e for e in timeline if e.get("event") == "user" and e.get("text")]
    if user_prompts:
        lines.append("## User Prompts (chronological)")
        lines.append("")
        for i, prompt in enumerate(user_prompts[:10], 1):  # Limit to first 10
            text = prompt.get("text", "")[:300]
            text = text.replace("\n", " ").strip()
            if len(prompt.get("text", "")) > 300:
                text += "..."
            lines.append(f"{i}. \"{text}\"")
        if len(user_prompts) > 10:
            lines.append(f"   ... and {len(user_prompts) - 10} more prompts")
        lines.append("")

    # Key thinking (extract most substantive ones)
    thinking_blocks = [e for e in timeline if e.get("event") == "thinking" and e.get("text")]
    if thinking_blocks:
        lines.append("## Key Thinking/Decisions")
        lines.append("")
        # Get longer thinking blocks (more likely to be substantive)
        substantive = sorted(thinking_blocks, key=lambda x: len(x.get("text", "")), reverse=True)[:5]
        for block in substantive:
            text = block.get("text", "")[:400]
            # Get first meaningful sentence/thought
            text = text.replace("\n", " ").strip()
            if len(block.get("text", "")) > 400:
                text += "..."
            lines.append(f"- {text}")
        lines.append("")

    # Commands run
    bash_commands = [e for e in timeline if e.get("event") == "tool_use" and e.get("tool_name") == "Bash"]
    if bash_commands:
        lines.append("## Commands Run")
        lines.append("")
        seen = set()
        for cmd in bash_commands:
            command = cmd.get("tool_input", {}).get("command", "")[:100]
            if command and command not in seen:
                seen.add(command)
                lines.append(f"- `{command}`")
        lines.append("")

    # Files modified
    file_ops = [e for e in timeline if e.get("event") == "tool_use" and e.get("tool_name") in ["Edit", "Write"]]
    if file_ops:
        lines.append("## Files Modified")
        lines.append("")
        seen = set()
        for op in file_ops:
            tool = op.get("tool_name", "")
            filepath = op.get("tool_input", {}).get("file_path", "")
            if filepath and filepath not in seen:
                seen.add(filepath)
                # Shorten path for display
                if len(filepath) > 60:
                    filepath = "..." + filepath[-57:]
                lines.append(f"- {filepath} ({tool})")
        lines.append("")

    # Errors encountered
    errors = [e for e in timeline if e.get("event") == "tool_use" and e.get("tool_result", {}).get("is_error")]
    if errors:
        lines.append("## Errors Encountered")
        lines.append("")
        for err in errors[:5]:  # Limit to 5
            tool = err.get("tool_name", "unknown")
            error_content = err.get("tool_result", {}).get("content", "")[:200]
            error_content = error_content.replace("\n", " ").strip()
            lines.append(f"- **{tool}**: {error_content}")
        lines.append("")

    # Where it left off
    lines.append("## Where It Left Off")
    lines.append("")

    # Last user prompt
    if user_prompts:
        last_prompt = user_prompts[-1].get("text", "")[:500]
        lines.append("**Last user request:**")
        lines.append(f"> {last_prompt}")
        lines.append("")

    # Last assistant response
    text_responses = [e for e in timeline if e.get("event") == "text" and e.get("text")]
    if text_responses:
        last_response = text_responses[-1].get("text", "")[:500]
        last_response = last_response.replace("\n", "\n> ")
        lines.append("**Last assistant response:**")
        lines.append(f"> {last_response}")
        lines.append("")

    # Pending work (from last thinking)
    if thinking_blocks:
        last_thinking = thinking_blocks[-1].get("text", "")[:300]
        if last_thinking:
            lines.append("**Last thinking:**")
            lines.append(f"> {last_thinking}")
            lines.append("")

    return "\n".join(lines)


def format_session_list(sessions: list[dict]) -> str:
    """Format session list for terminal display."""
    if not sessions:
        return "No sessions found."

    lines = []
    lines.append(f"{'ID':<12} {'Duration':>8}  {'Project':<30} {'Summary'}")
    lines.append("-" * 100)

    for s in sessions:
        sid = s["id"][:8]  # Short ID is enough to identify
        duration = f"{s['duration_mins']}m" if s["duration_mins"] else "?"
        project = s.get("project", "")
        # Shorten project path
        if project:
            project = project.replace(str(Path.home()), "~")
            if len(project) > 28:
                project = "..." + project[-25:]
        else:
            project = "(unknown)"
        summary = s["summary"][:40] + "..." if len(s["summary"]) > 40 else s["summary"]
        if not summary:
            summary = "(no summary)"
        lines.append(f"{sid:<12} {duration:>8}  {project:<30} {summary}")

    return "\n".join(lines)


def main():
    parser = argparse.ArgumentParser(description="Claude Code Session Analyzer")
    parser.add_argument("session_id", nargs="?", help="Session ID to analyze")
    parser.add_argument("--latest", action="store_true", help="Analyze most recent session")
    parser.add_argument("--list", action="store_true", help="List all sessions with summaries")
    parser.add_argument("--project", help="Project path to search in")
    parser.add_argument("--output", choices=["json", "html"], default="html",
                        help="Output format (default: html)")
    parser.add_argument("--digest", action="store_true",
                        help="Generate markdown digest for follow-up in new session")
    parser.add_argument("--open", action="store_true", help="Open HTML in browser")
    parser.add_argument("--out-file", help="Write output to file instead of stdout")

    args = parser.parse_args()

    # Handle --list flag
    if args.list:
        try:
            sessions = list_sessions(project_path=args.project)
            if args.output == "json":
                print(json.dumps(sessions, indent=2))
            else:
                print(format_session_list(sessions))
        except FileNotFoundError as e:
            print(f"Error: {e}", file=sys.stderr)
            sys.exit(1)
        return

    try:
        main_file, agent_files = find_session_files(
            session_id=args.session_id,
            project_path=args.project,
            latest=args.latest or (not args.session_id)
        )

        print(f"Analyzing session: {main_file.name}", file=sys.stderr)
        print(f"Found {len(agent_files)} agent file(s)", file=sys.stderr)

        data = build_session_data(main_file, agent_files)

        # Get all sessions for the selector
        all_sessions = []
        try:
            all_sessions = list_sessions(project_path=args.project)
        except:
            pass  # Session list is optional

        if args.digest:
            output = generate_digest(data)
        elif args.output == "json":
            output = json.dumps(data, indent=2)
        else:
            output = generate_html(data, all_sessions=all_sessions)

        if args.out_file:
            with open(args.out_file, "w") as f:
                f.write(output)
            print(f"Written to {args.out_file}", file=sys.stderr)
            if args.open and args.output == "html":
                subprocess.run(["open", args.out_file])
        elif args.open and args.output == "html":
            # Write to temp file and open
            with tempfile.NamedTemporaryFile(mode="w", suffix=".html", delete=False) as f:
                f.write(output)
                temp_path = f.name
            print(f"Opening {temp_path}", file=sys.stderr)
            subprocess.run(["open", temp_path])
        else:
            print(output)

    except FileNotFoundError as e:
        print(f"Error: {e}", file=sys.stderr)
        sys.exit(1)


if __name__ == "__main__":
    main()
