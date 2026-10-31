#!/usr/bin/env python3
"""PreToolUse hook: keeps an approved goal contract frozen.

Copied unchanged to .claude/hooks/protect-goal.py in the target repo and registered in
.claude/settings.json for Edit, Write, MultiEdit and NotebookEdit.

Blocks (exit 2, reason on stderr – Claude Code shows it to the agent):
- any change to a contract file rebuild/goal/contract-vNNN.md that already carries "Status: APPROVED"
- any write that would put "Status: APPROVED" into a contract file – only the user approves a version

Everything else passes (exit 0). A change to the goal goes into rebuild/goal/change-requests.md and
becomes a new contract version only after the user approves it.
Limit: the hook sees file tools only; a shell command can still change the file. CLAUDE.md forbids it.
"""
import json
import pathlib
import re
import sys

CONTRACT = re.compile(r"(^|/)rebuild/goal/contract-v\d+\.md$")
APPROVED = re.compile(r"^\s*Status:\s*APPROVED\b", re.MULTILINE)
TOOLS = {"Edit", "Write", "MultiEdit", "NotebookEdit"}


def new_text(tool_input: dict) -> str:
    parts = [tool_input.get("content", ""), tool_input.get("new_string", ""), tool_input.get("new_source", "")]
    parts += [e.get("new_string", "") for e in tool_input.get("edits", []) or []]
    return "\n".join(p for p in parts if isinstance(p, str))


def main() -> int:
    try:
        event = json.load(sys.stdin)
    except (ValueError, OSError):
        return 0  # not our business: never break the session over unreadable input
    if event.get("tool_name") not in TOOLS:
        return 0
    tool_input = event.get("tool_input") or {}
    raw = tool_input.get("file_path") or tool_input.get("notebook_path") or ""
    path = pathlib.Path(raw)
    if not path.is_absolute():
        path = pathlib.Path(event.get("cwd") or ".") / path
    if not CONTRACT.search(path.as_posix()):
        return 0
    if path.is_file() and APPROVED.search(path.read_text(encoding="utf-8", errors="replace")):
        print(f"{path.name} is an approved goal contract and frozen. Do not change it. "
              "Write a change request to rebuild/goal/change-requests.md (what, why, which REQ/AC) "
              "and ask the user; in auto mode print 'NEEDS-DECISION: goal change request <id>'.",
              file=sys.stderr)
        return 2
    if APPROVED.search(new_text(tool_input)):
        print("Only the user approves a goal contract version. Leave the status at READY_FOR_APPROVAL "
              "and show the user the version to approve.", file=sys.stderr)
        return 2
    return 0


if __name__ == "__main__":
    sys.exit(main())
