# Slice Board

A compact pane beside the chat for the open round of [vibe-coding](../vibe-coding/README.md). It is a Claude Code mod: it runs in the CLI, the Code tab of the Desktop app and the VS Code extension.

It is laid out like the app's context pane and refreshed every ten seconds:

- **The round:** the share of done slices, a thin bar with one segment per group, and a legend with count and share per group: Done, In progress, Ready, Blocked. Each legend row unfolds its slices.
- **In progress** (unfolded by default): one row per slice with a dot for its state (working, awaiting plan approval, idle), the next checklist step with the slice's share (Plan, Red, Green, Checks, Commit), and `↗`, which brings the slice's session to the front.
- **Ready:** `▶` per slice and a `Start N` button at the bottom start one session per ready slice, at most four slices in progress at once. A blocked slice joins the ready ones as soon as the slices it depends on are done; a toast says so, and another when a plan waits for approval.

It reads `work/_slices.json`, `work/checklist.md`, `work/rounds/`, `work/conventions.md` and the `slice-NN` branches and worktrees of the repository the session runs in. A started session gets `/slice NN` with the slice's goal, scope and acceptance cases, plus `work/session-hints.md` when the repository has one. Sessions are matched to slices by their title, `Slice NN …`.

## Install

```bash
claude plugin install slice-board@vompa
```

Open the pane with `/slices`; it also opens by itself in a session whose repository has an open round.

## Develop

```bash
claude plugin validate plugins/slice-board
claude plugin test plugins/slice-board
```
