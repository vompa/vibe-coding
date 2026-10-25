# Slice Board

A compact pane beside the chat for the open round of [vibe-coding](../vibe-coding/README.md). It is a Claude Code mod: it runs in the CLI, the Code tab of the Desktop app and the VS Code extension.

It is laid out like the app's context pane and refreshed every ten seconds while it is open. Two refreshes never run at once, and none runs while the pane is closed. Every row is plain text, with no timers of its own, so nothing on the pane goes blank under load.

- **The round:** the share of done slices, a thin bar with one segment per group, and a legend with count and share per group: Done, In progress, Ready, Blocked. Each legend row unfolds its slices.
- **In progress** (unfolded by default): one row per slice with a dot for its state (working, awaiting plan approval, idle), the next checklist step with the slice's share (Plan, Red, Green, Checks, Commit), and `↗`, which brings the slice's session to the front.
- **Ready:** `▶` per slice and a `Start N` button above the groups write a request into the prompt box to start one session per slice, at most three slices in progress at once. Enter sends it as your message and Claude starts the sessions under the session's own permission check; a start straight from the pane would have no conversation behind it, and auto mode refuses such a call. A blocked slice joins the ready ones as soon as the slices it depends on are done; a toast says so, and another when a plan waits for approval.

It reads `work/_slices.json`, `work/checklist.md`, `work/rounds/`, `work/conventions.md` and the `slice-NN` branches and worktrees of the repository the session runs in. The request asks for `/slice NN` with the slice's goal, scope and acceptance cases, plus `work/session-hints.md` when the repository has one. Sessions are matched to slices by their title, `Slice NN …`.

## Install

```bash
claude plugin install slice-board@vompa
```

The pane opens only in the chat that runs the round: with `/slices`, `/slice` alone, `/slice status`, `/slice close` or `/vibe-coding`. A slice session works on `/slice NN` and gets no pane, and a session without the pane runs no git. After `/reload-plugins` a session that had the pane opens it again.

## Develop

```bash
claude plugin validate plugins/slice-board
claude plugin test plugins/slice-board
```
