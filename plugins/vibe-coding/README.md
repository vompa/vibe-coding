# Vibe Coding

**Findings or ideas in, one squash commit per slice out – fresh Claude session each, your repo's rules honoured.**

```bash
claude plugin marketplace add vompa/vibe-coding
claude plugin install vibe-coding@vompa
```

A skill for *running the work*, not a guide to writing prompts (other skills that carry the name `vibe-coding` cover that). Give Claude a findings list – a UI review, your own notes after trying a build, a bug list – or a feature idea. It turns the input into a *round* of vertical slices, each with a ready-to-run prompt and a Definition of Done, and the `/slice` command then works through them one per fresh Claude session: plan first, tests first, one squash commit per slice on your repository's own branch. The round ends with a manual test list; what you report on it is the findings list of the next round.

It uses the way of working of [vibe-rebuild](../vibe-rebuild/README.md) for everyday changes in any repository instead of for rebuilding an old app. Your existing `CLAUDE.md`, working-method documents, branch rules and check commands are discovered once and followed, never replaced.

Needs Claude Code with file access; Python 3.10+ for the slice renderer; the `claude` CLI plus PowerShell 7 or bash for the hands-off loop. The [superpowers](https://github.com/obra/superpowers) plugin is used when it is installed and never installed for you.

## What you get

These files appear in your repository. The round-start commit on its integration branch (nothing is pushed) carries them all except `plans/`, which each slice adds, and `_raw/`, which stays local:

```
CLAUDE.md                     only if the repository has none
.gitignore  .gitattributes    lines for work/_raw/, .slice-loop/ and *.sh added, nothing else touched
.claude/commands/slice.md     the /slice command – next slice, a given slice, status, close
.claude/scripts/slice-loop.*  runs the slices one after another in fresh sessions
work/
  conventions.md              how this repository works – branch, commands, rules – each fact with the document it comes from
  checklist.md                progress per slice, ticked by the agent
  _slices.json                the slice list, input for the renderer
  rounds/R01-<slug>.md        one record per round: intake or brief, slice map, decisions, surprises, open decisions, manual test list
  slices/NN-<slug>.md         one file per slice
  plans/<date>-slice-NN.md    the plan each /slice writes before it builds
  research.md                 only when a round needed research
  _raw/                       working material, git-ignored
```

Every slice file holds the goal, its source (round and finding or acceptance-criterion ids), dependencies, scope, **patterns to mirror** (`file:line`, read from your code), **NOT building**, a self-contained prompt, and a Definition of Done with Given/When/Then acceptance cases, manual check items for what the eye must see, and a "no test weakened or skipped" boundary.

The names `work/` and `/slice` are fixed. If either already exists for something else, the skill reports it and stops.

## How to use it

Just describe what you want, for example:

- "Here is the UI review of all screens against our design system: `reviews/ui-2026-10.md`. Turn it into slices we can work through."
- "I tried the new build. The save button on the booking form does nothing when the date is empty; invoice totals round 19.995 to 19.99; at 1024 px the sidebar covers the table. Make a round out of this."
- "I want the point of sale ready for real operation – cash drawer, receipts, end-of-day report. The concept and two screenshots are in `docs/pos/`. Sharpen the idea and slice it."

The skill triggers on its own. To call it explicitly and unambiguously, even if another skill named `vibe-coding` is installed, use the namespaced form: `/vibe-coding:vibe-coding <file or idea>`. The files are written in the language of your repository (the language of its `CLAUDE.md` or README, else English).

Before it writes anything the working tree must be clean, the integration branch checked out and no other round open. Otherwise it stops and says what to do; it never switches branches, stashes or resets for you.

## How it works

1. **Conventions** (first round of a repository only) → `work/conventions.md`. It reads what the repository already defines – `CLAUDE.md`, `AGENTS.md`, README, working-method and contribution documents, protocol files, CI, formatter configuration, `git log` – and records one line per fact with its source: branches and merge style, commit language, the build, test and check commands, where decisions are recorded, which documents must change with a change, the privacy rule for names. Pointers, not copies; conflicts between documents are listed, not resolved; you confirm the file once. A repository without a `CLAUDE.md` gets a lean one.
2. **Intake** → round record. **A, findings list:** a tracked file is referenced by path, notes from you are captured in an intake table (id, place, observed → expected, size); ids continue the repository's own scheme, and a finding that shows an earlier fix did not hold is marked `reopens <id>`. **B, idea:** a brief of at most one page with Given/When/Then acceptance criteria and a NOT-building list, sharpened with `superpowers:brainstorming` when installed, otherwise with up to five questions. Ceremony scales with size: a one-line finding gets no brief. Research runs only when the brief brings technology or packages the repository does not use yet. What you must decide becomes a `NEEDS-DECISION:` line, put to you in one message; only answered items are sliced.
3. **Slicing** → `work/_slices.json`, `work/slices/`. Grouped by screen or theme, shared components first, vertical slices of about one session each with an independent test, trivial items in a sweep slice, MVP first for ideas. Every UI finding gets a manual check item. A coverage check makes sure every finding id or acceptance criterion lands in a slice.
4. **Handover.** You confirm the conventions and the slice map; the git identity is checked (a private one is never used silently); then one commit on the integration branch, `Round Rnn: <slug> – N slices`, in your commit language and style. Nothing is pushed. The final message tells you how to start.

Long steps are announced and status lines start with an overall percentage. Agent reports go to files, not into the chat.

## Running a round

Open a terminal in the repository, run `claude`, type `/slice`:

| Input | What happens |
|---|---|
| `/slice` | picks the lowest slice whose dependencies are done, runs the baseline check, shows a plan, builds after your approval (tests first) |
| `/slice 07` | exactly slice 07 |
| `/slice 07 plan` | stops after the plan; your next message approves it, answers its open questions or asks for changes |
| `/slice 07 direct` | without superpowers, even if it is installed |
| `/slice status` | one table: done, in progress, ready, blocked; open decisions; what is ready next |
| `/slice close` | closes the round (see below) |

If the superpowers plugin is installed, `/slice` uses it (worktree, `writing-plans`, `subagent-driven-development`, `finishing-a-development-branch`); otherwise it follows the slice prompt. Each slice lands as **one squash commit on the integration branch**; task commits stay on the branch `slice-NN` (in auto mode, which the loop uses, the merged branch and its own worktree are removed after the squash). The commit carries the plan, the checklist tick, the round-record entries (decisions, surprises, deferred minors, manual check items), the repository's own protocol entry and the documents your conventions list as "must change with a change". Nothing is pushed. Start a fresh session and type `/slice` again for the next slice; `/slice` proposes `close` after the last one.

### Hands-off: all slices in one go

```bash
pwsh .claude/scripts/slice-loop.ps1     # Windows, macOS, Linux (PowerShell 7)
bash .claude/scripts/slice-loop.sh      # macOS, Linux, Git Bash
```

The loop checks that a round is open, then for each ready slice starts a fresh headless Claude session that writes the plan and stops. You see the plan's path and any open decisions: **Enter** approves, **text** sends a change request or your answers, **`q`** stops. After approval the same session builds, tests and closes the slice. When the last slice is ticked, one more fresh session runs `/slice close auto`, and the loop stops at `ROUND-DONE` or `ROUND-OPEN`.

| Option (PowerShell / bash) | Effect |
|---|---|
| *(none)* | asks for every plan |
| `-Yes` / `--yes` | approves plans automatically; still stops when a plan reports an open decision (`NEEDS-DECISION`), a slice stays red, or a slice reports done without being ticked |
| `-Parallel` / `--parallel` | builds slices that are ready at the same time side by side, each in its own worktree (experimental) |
| `-DryRun` / `--dry-run` | only lists the slices that are ready now |
| `-MaxSlices N` / `--max-slices N` | stops after N built slices if slices are left (exit 0; run it again to continue) |

Good to know:

- Headless sessions can't answer permission prompts, so they run with `--permission-mode auto`; set `SLICE_PERMISSION_MODE` to choose another mode.
- Logs go to `.slice-loop/` in the repository, which the script keeps out of git.
- Approvals need a terminal. Without one (for example in CI) the script stops instead of approving silently.
- The script never pushes and never installs anything.
- Under the hood `/slice` prints marker lines the script reads (`PLAN:`, `NEEDS-DECISION:`, `SLICE-DONE:`, `SLICE-OPEN:`, `ALL-DONE`, `ROUND-DONE:`, `ROUND-OPEN:`); `/slice NN plan auto` is what the script sends.

## After the round

`/slice close` (the loop runs it for you) needs every slice of the round done, a clean working tree and the integration branch checked out. It then:

1. runs the full check chain from `work/conventions.md` – red changes nothing and ends with `ROUND-OPEN`;
2. writes the **manual test list** into the round record: per slice the start command, the steps, what you should see, the finding ids it closes and `Result: ☐`;
3. sets `Status: closed` and commits the record as `Round Rnn closed: <slug>` on the integration branch. Nothing is pushed.

Try the build with that list. Tick `Result:` or write what you saw, answer the open decisions – in chat or in the round record. Your notes are the findings list of the next round: ask for the next round with the skill, and it reads and updates `work/conventions.md` instead of discovering it again, inherits the open decisions as `(from Rnn)`, and continues the slice numbering. One round is open at a time.

## Relationship to vibe-rebuild

vibe-coding uses the same formats as [vibe-rebuild](../vibe-rebuild/README.md) – `_slices.json`, `checklist.md`, the marker lines and the two-run plan approval – for a different job: vibe-rebuild analyses an old codebase and plans its rebuild with parity cases; vibe-coding does no analysis and no parity cases, it runs everyday changes. The two plugins are independent; install either or both. A repository finished with vibe-rebuild continues here after its last slice: `work/conventions.md` is derived from its `CLAUDE.md`, `rebuild/` stays as the record of the origin, and slice numbering in `work/` continues after the highest number in `rebuild/_slices.json` (rebuild slices 00–04, first slice here 05), so branch names `slice-NN` and markers never collide.

## Privacy

No data collection, no network access of its own, no credentials; it writes the planning files above and, slice by slice, the product changes you approve; it pushes nothing – see [PRIVACY.md](PRIVACY.md).

## License

MIT – see [LICENSE](LICENSE). Source and issues: https://github.com/vompa/vibe-coding
