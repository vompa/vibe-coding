---
name: vibe-coding
description: Runs everyday coding work the vibe-rebuild way – turns a findings list (UI review, user test notes, bug reports) or a feature idea into a round of vertical slices with ready-to-run prompts and a Definition of Done, then executes them one per fresh Claude session via /slice – plan first, tests first, one squash commit per slice on the repo's own branch, a hands-off loop, and a manual test list at the end of each round. Honours the repository's existing CLAUDE.md and working rules. Use whenever someone has a list of changes, review findings or test feedback to work through, wants to slice a feature into agent-sized work packages with fewer pull requests, or wants a feedback loop of build → test → findings → next round with Claude Code. Not for rebuilding or migrating an existing app (that is vibe-rebuild), not for a single quick fix, a code review or a prompting guide.
license: MIT
compatibility: Designed for Claude Code with file access and subagents; render script needs Python 3.10+; the slice-loop needs the claude CLI plus PowerShell 7 or bash; uses the superpowers plugin when installed.
metadata:
  author: vompa
  version: "1.0.0"
---

Filled in Task 7
