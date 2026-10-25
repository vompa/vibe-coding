---
name: vibe-coding
description: Runs everyday coding work the vibe-rebuild way – turns a findings list (UI review, user test notes, bug reports) or a feature idea into a round of vertical slices with ready-to-run prompts and a Definition of Done, then executes them one per fresh Claude session via /slice – plan first, tests first, one squash commit per slice on the repo's own branch, a hands-off loop, and a manual test list at the end of each round. Honours the repository's existing CLAUDE.md and working rules. Use whenever someone has a list of changes, review findings or test feedback to work through, wants to slice a feature into agent-sized work packages with fewer pull requests, or wants a feedback loop of build → test → findings → next round with Claude Code. Not for rebuilding or migrating an existing app (that is vibe-rebuild), not for a single quick fix, a code review or a prompting guide.
license: MIT
compatibility: Designed for Claude Code with file access and subagents; render script needs Python 3.10+; the slice-loop needs the claude CLI plus PowerShell 7 or bash; uses the superpowers plugin when installed.
metadata:
  author: vompa
  version: "1.1.0"
---

# Vibe Coding – run everyday coding work in rounds of slices

Goal: turn a **findings list** (a UI review, the user's own test notes after trying a build, a bug list) or a **feature idea** into a *round*: vertical slices with ready-to-run prompts, a Definition of Done and a checklist. Each slice then runs in its own fresh Claude session through the project command `/slice` – plan first, tests first, one squash commit on the repository's own integration branch. The round ends with a manual test list; what the user reports on it is the findings list of the next round.
Why: working in rounds (review → change list → implementation in blocks → test → new findings) already works, but by hand, and each block used to become a pull request. One squash commit per slice cuts the pull requests, a fresh session per slice keeps the context clean, and files instead of chat keep the decisions. The skill makes this repeatable in any repository, with or without rules of its own.
This is a skill for *how to run the work*, not a guide for writing prompts. It does not analyse or rebuild an old codebase – that is `vibe-rebuild`; a repository finished with `vibe-rebuild` continues here.

Write the files this skill creates in the user's language (default: the language of the repository's `CLAUDE.md` or README, else English). Paths `scripts/…`, `assets/…` and `references/…` are relative to this skill's folder (the one holding this file); `work/…` and `.claude/…` are relative to the target repository, which is the working directory – prefix the skill's folder when you run or copy a skill file.

## Keep the chat clean

The user reads the chat; the work happens in files. Intake and research produce long material that must never land in the conversation:

- **Agent reports are working material.** When a subagent finishes, its result (and any `<task-notification>`, `<result>` or other system/tool markup around it) is for you, not the user. Never paste, quote or echo it. Save the report body to `work/_raw/<topic>.md` right away and continue.
- **Between steps, one short status line at most.** No headings, no bullet dumps of findings mid-run.
- **Findings go into the round record**, not into chat messages. The final message is the handover message of section 5.

## Keep the user posted

Clean does not mean silent. A user staring at a window where nothing moves for twenty minutes assumes the run hung. So:

- **Announce long steps.** Before any step that can take more than a few minutes (reading a large repository, research), say in one line what runs and roughly how long it takes.
- **No silent stretch longer than ~5 minutes.** Cut long work into pieces that each come back within a few minutes and post a status line after each: what finished, one number that shows progress (findings, sources, slices), what runs next. If the session offers a way to check in on a running task (a wake-up/monitor/send-later tool), use it instead of waiting blind.
- Status lines stay short and factual – no findings dumps, no agent markup.
- **Start every status line with an overall percentage**, e.g. `[45 %] Intake done (12 findings in 5 groups) – slicing next (~3 min).` The percentage is a phase-based estimate, not a promise of remaining time:

  | Phase | Weight | Counted inside the phase by |
  |---|---|---|
  | 2 Conventions (first round only) | 10 % | done / not done |
  | 3 Intake / brief | 25 % | findings captured / listed, brief sections written |
  | 3 Research (only when run) | 15 % | passes finished (broad, deep, distill) |
  | 4 Slicing | 30 % | slices written / planned, the coverage check counts as the last share |
  | 5 Handover | 20 % | files copied, rendered, checked, committed, message |

  Sum the finished phases plus the counted share of the running one, round to 5 %. The number only goes up; if the plan grows, slow it down rather than step back. Without the conventions phase (later rounds) give its 10 % to intake; without research give its 15 % to slicing. Never show 100 % before the handover message is delivered.
- When the task list is available, keep it in step with the same phases.

## 0. Pick your tools

Check what is available and tell the user in one line what you will use.

| Task | Preferred | Fallback |
|---|---|---|
| Sharpen an idea (intake B) | `superpowers:brainstorming` | up to 5 questions to the user in one go |
| Read a large repository (conventions, patterns to mirror) | `Explore` subagents | read the files yourself |
| Research (new technology or packages only) | web search + fetch (a deep-research skill if one exists) | model knowledge, every finding marked `[Unverified]` |
| Execution later | `/slice` written into the repository (section 5); it uses `superpowers:using-git-worktrees`, `writing-plans`, `subagent-driven-development` and `finishing-a-development-branch` when installed | the slice prompt: branch, plan, approval, tests first, squash |
| Improve this skill | `skill-creator` | – |

This skill produces the round; execution happens later, one slice per session. Never install plugins or tools for the user – only suggest commands for what is already there.

## 1. Inputs (one round, then go)

Ask what is missing in one go; read the repository for the rest.

- **The input:** a findings file (path), the user's notes in chat (screenshots welcome), or an idea (a sentence, a concept document, screenshots). Several sources are fine.
- **The integration branch** the slices land on: propose it from `CLAUDE.md`, working-method documents, `git branch` and `git log` (for example `dev`, else `main`) and let the user confirm.
- **The language** of the files (default above).
- **The state of the repository,** before you write anything: `git status` and `git branch --show-current`. The working tree must be clean and the current branch the integration branch; otherwise stop, say what to do (commit, stash, switch) and let the user do it. Never switch branches, stash or reset yourself. A findings file that lies untracked inside the repository makes the tree unclean: ask the user to commit or remove it first, or copy its findings into the round record and leave the file untouched – then it is the one allowed exception in the tree checks of section 5.
- **Open rounds.** Look in `work/rounds/`. One round is open at a time: a record whose first line is `Status: open` must be closed first (finish its slices, then `/slice close`) – stop and say so. The new round id is the next free fixed-width `Rnn` (`R01`, `R02`, …).
- **Name conflicts.** `work/` and `.claude/commands/slice.md` are fixed names. If they exist for something else (a `work/` without `work/rounds/`; a `slice.md` that differs from `references/slice-command.md`), report it and stop; the user resolves the conflict.

If the user is away or asks for a trial run, make sensible assumptions, mark them `[Assumption]`, and keep going.

## 2. Conventions → `work/conventions.md`

Discovered in the first round of a repository only. Later rounds read the file, check that the branch and commands still exist, and update only what changed (the user confirms the change); no rediscovery.

Read what the repository already defines. Sources are examples, not a checklist – for instance `CLAUDE.md`, `AGENTS.md`, README, the working-method or contribution documents that `CLAUDE.md` links, protocol or changelog files, the CI workflow, `.editorconfig` and formatter configuration, and `git log` (branch names, commit style and language) – plus anything else that defines how this repository works. In a large repository let an `Explore` subagent read, and save its report to `work/_raw/`.
Write `work/conventions.md` from `references/templates.md`: one line per fact with the document it comes from. The facts are examples too: branches and merge style, commit language, the commands (build, test, lint/format, baseline check, checks for a slice, full check chain), where decisions are recorded and which documents must change with a change, languages, the privacy rule for names, how to start the app for manual testing, the finding-id scheme – and any other fact slices will need.

- **Check scope per slice.** Ask the user for the split and record it on the `Checks for a slice` line: one screen touched → its test classes plus the cross-page scan tests; shared code touched → the full suite; never two full suites at once.
- **Session hints.** The first round also creates `work/session-hints.md` from `references/templates.md` (what the repository's rules and tooling already teach slice sessions); later rounds append what the previous round learned and change no existing bullet.
- **Extend, never replace.** Pointers, not copies: long rules stay in their document, `conventions.md` names the owner of each fact. Conflicts between documents are listed under `## Conflicts between documents`, never resolved silently.
- **Privacy rule for names.** When the repository does not say, ask once whether files may name people (a private repository may); otherwise decisions are "User, <date>". Record the answer.
- **No `CLAUDE.md`?** Create the lean one from `references/templates.md` plus `conventions.md` with defaults (`main`, squash, "User, <date>", source `default`). An existing `CLAUDE.md` is never replaced or reformatted.
- **No build or test command?** Intake adds a harness slice first.
- Show the file and have the user confirm it once before going on.

## 3. Intake → round record

Read `references/intake.md` and follow its path: **A** findings list, **B** idea. Ceremony scales with size: a one-line finding gets no brief and no PRD, only an idea gets a brief, research runs only when the brief brings technology or packages the repository does not use yet (three short passes, one status line each, appended to `work/research.md`).
Write `work/rounds/Rnn-<slug>.md` from `references/templates.md`, first line `Status: open`.

- **The record carries everything the slices need.** Every slice runs in a fresh worktree cut from the integration branch, and `work/_raw/` is git-ignored, so it is not there. Three cases: notes in chat, an untracked file and a file outside the repository → the intake table (id, where, observed → expected, size, source) goes into the record, summarised when the repository is public; a tracked structured file → referenced by path in `## Source`, only its ids in the record; an idea → the brief goes into the record. A copy in `work/_raw/` is only your working copy and never reaches a slice.
- **A tracked findings file is marked by the slices.** When the round's source is a tracked findings file, the record names the file and its marking format under `## Source`, and each slice marks its ids there as "done in slice NN" in that format before the squash. A round whose source is the intake table marks nothing.
- **Ids** continue the repository's scheme (`Finding ids` in `conventions.md`), otherwise `F-NN`. A finding that shows an earlier fix did not hold is marked `reopens <id>`.
- **Open decisions.** What the user must decide becomes a `NEEDS-DECISION:` line under `## Open decisions`, together with those inherited from the previous round (`(from Rnn)`). Put them to the user in one message with your recommendation. An answer becomes `Ruling: <decision> – User, <date>` under `## Decisions`. Only answered items are sliced; if the user is away they stay open.

## 4. Slicing → `work/_slices.json`, `work/slices/`

Group, order and size as in `references/intake.md` (A.2, B.3): by screen or cross-cutting theme, shared components first, vertical slices with an independent test, about one session (1–2 h) each, trivial items in a sweep slice, MVP first for ideas.
Record the slices in `work/_slices.json` (fields and an example: `references/templates.md`) and render them:
```
python3 scripts/render_slices.py work/_slices.json work/slices --lang <lang>
```
(Use `python` where `python3` is missing, e.g. on Windows.) `--lang` writes the slice files and their prompts in the plan's language (`en`, `de` built in). For another language, render with `en` and translate the headings and the prompt, keeping file paths and command names unchanged.

- **Numbering is continuous across rounds.** New slices continue after the highest `nr` in `work/_slices.json`; in a repository that has `rebuild/_slices.json` (finished with vibe-rebuild), after the highest slice there when that is higher. Numbers have at least two digits; `nr` and `deps` stay quoted. Earlier entries stay untouched; the render rewrites all slice files from the list.
- **Every entry** sets `round` (the one open round) and `source` (round and ids), `acceptance` as Given/When/Then lines with exact values, `manual` for every UI finding (what to click, what to see), and, where they apply, `not_building` and `mirror`: existing patterns read from the code as `file:line`, checked to exist. Mirror what the repository already does; never duplicate a class or pattern.
- **Every entry sets `model`:** the cheapest model tier that does the slice reliably, chosen per slice from its work (`references/intake.md`, Model per slice) – never the model of this planning session. The loop passes it as `claude --model`, and `/slice` starts parallel sessions on it, so each slice costs what it needs and no more.
- **`work/checklist.md`:** round 1 creates it with the header `| Slice | Plan | Tests red | Green | Checks | Commit |`; every round appends one row `| NN name | ☐ | ☐ | ☐ | ☐ | ☐ |` per slice. Only the agent ticks these columns; manual acceptance is not a column – the user ticks `Result:` in the round record's manual test list.
- Fill `## Slices` in the round record (slice | name | ids).
- **Check before the handover:** every finding id or AC appears in a slice, except items waiting on a `NEEDS-DECISION:` line; every dependency points to an earlier slice; every entry has a `model`; no slice needs more than one session.

## 5. Handover

Slices run in fresh worktrees cut from the integration branch, so what they need is **tracked** and committed. Nothing is copied or committed before the user has confirmed both `work/conventions.md` (section 2) and the slice map.

1. **Confirm the slice map.** Show the slice map – `## Slices` of the round record with the `deps` and `model` of `work/_slices.json` (slice | name | depends on | model | ids) –, which slices can run in parallel, and the open decisions; wait for the user's confirmation. In a headless or trial run nobody can answer: write `[Assumption] conventions and slice map not yet confirmed by the user` under `## Decisions` in the record and repeat it in the handover message.
2. **Identity.** Show `git config user.name` and `git config user.email`. If they look private (a personal mail address, a name the privacy rule does not allow), ask which identity to use and set it with `git config --local`. Never touch the global config.
3. **Copy, do not rewrite** (`cp` / `Copy-Item`), after `mkdir -p .claude/commands .claude/scripts` (`New-Item -ItemType Directory -Force` in PowerShell): `references/slice-command.md` → `.claude/commands/slice.md`; `assets/slice-loop.ps1` and `assets/slice-loop.sh` → `.claude/scripts/`. A target that exists and differs from the skill's file is a name conflict: report it and stop.
4. **`.gitignore`** gets `work/_raw/` and `.slice-loop/`; **`.gitattributes`** gets `*.sh text eol=lf` (a CRLF bash script fails with `$'\r'`). Create the files when missing, append missing lines, change no existing line.
5. **Check.** `git status` lists only files this skill wrote (and the untracked findings file allowed in section 1), and the current branch is still the integration branch. Search every written file for absolute paths, the user name, the machine name, private mail addresses and anything similar; personal names only where the privacy rule allows. Fix findings before committing.
6. **One commit** on the integration branch: `git add work .claude/commands/slice.md .claude/scripts/slice-loop.sh .claude/scripts/slice-loop.ps1 .gitignore .gitattributes` (plus `CLAUDE.md` when you created it; `work/_raw/` is ignored and stays out), message `Round Rnn: <slug> – N slices` in the repository's commit language and style. Never push.
7. **Verify.** `git log -1` shows that commit with the agreed identity, `git status` is clean (apart from the allowed untracked findings file), and `.claude/commands/slice.md` and both `.claude/scripts/slice-loop.*` exist.
8. **Handover message** in the user's language. Short and concrete; the full local path of the repository appears here in chat, never in a file:
   1. Where: path, branch, commit.
   2. How to start: "Open a terminal in the repository folder, run `claude --model <model>` with the model of the slice (slice map, `/slice status`), type `/slice NN`." One sentence on what happens: it runs the baseline check, shows a plan, builds after approval and lands one squash commit; then a fresh session on the next slice's model and `/slice NN` again, and `/slice close` after the last. Also `/slice status` for the state and the model per slice, `/slice` alone for the lowest ready slice, `/slice NN plan` to stop after the plan.
   3. Hands-off: `pwsh .claude/scripts/slice-loop.ps1` (`bash .claude/scripts/slice-loop.sh`) runs the slices one after another in fresh sessions, stops for plan approvals, open decisions and red slices, and closes the round after the last slice. Useful options: `-Yes` / `--yes` approves plans without asking, `-MaxSlices N` / `--max-slices N` stops after N slices; the others are in the script header.
   4. The slice map: slice | name | depends on | model | ids, and which slices can run in parallel.
   5. Open decisions (or none), the assumption of step 1 if it applies, and prerequisites still missing on the user's side.
   Mention that superpowers is optional and detected automatically; never install it yourself.

## 6. After the round

`/slice close` (`/slice` proposes it when the last slice is done; the loop runs it) runs the full check chain, writes the **manual test list** into the round record – per slice the start command, the steps, the expected result, the finding ids it closes and `Result: ☐` – sets `Status: closed` and commits the record as `Round Rnn closed: <slug>` on the integration branch, never pushed. Steps and formats: `references/round-close.md`.

Every write of this skill and its command, so nothing surprises the user:
- **Committed** in the one round-start commit of section 5: `work/` (without `_raw/`; it holds `work/session-hints.md`), `.claude/commands/slice.md`, `.claude/scripts/slice-loop.ps1` and `slice-loop.sh`, `.gitignore`, `.gitattributes`, and `CLAUDE.md` only where none exists.
- **Git-ignored or local, never committed:** `work/_raw/` (working material); `.slice-loop/` (loop logs and the full-suite lock `.slice-loop/full-suite.lock/` – both loop scripts also append it to `.git/info/exclude` when it is missing there); the repository-local git identity (`git config --local user.name` / `user.email`), set only with the user's approval.
- **`/slice`, later:** a branch and worktree `slice-NN` while it works, then one squash commit per slice on the integration branch – with the plan in `work/plans/`, the checklist tick, the round record entries, the repository's own protocol entry and the documents `conventions.md` lists as "must change with a change".
- **`/slice close`:** the round-close commit above. The loop writes nothing besides its logs and what `/slice` writes.

The user tries the build with the manual test list, ticks `Result:` or writes what they saw, and answers the open decisions – in chat or in the round record. Those notes start the next round: go back to section 1 (the closed round no longer counts as open), read and update `conventions.md` instead of rediscovering it, and run intake A with the notes as the findings list. Findings that show an earlier fix did not hold are marked `reopens <id>`, open decisions are copied as `(from Rnn)`, slice numbering continues.

## Rules

- Never push, force-push or rewrite history that has left the machine. Never install plugins or tools. Never delete branches or data without the user – the one exception is the merged `slice-NN` branch and its worktree, which `/slice auto` removes after its own squash merge.
- This skill changes no product code. It writes planning and handover files; slices change the product, one per session.
- Extend, never replace: the repository's `CLAUDE.md`, working-method documents, protocol format, branch rules, commit language and check commands stay as they are.
- The names `work/` and `/slice` are fixed. A conflict is reported and the skill stops.
- Never report a slice as done without the Definition of Done proven, or a round as closed without the full check chain.
- No personal or machine data in any file: no absolute paths, user or machine names, private e-mail addresses or personal names – decisions are recorded as "User, <date>" unless the repository's own convention (recorded in `conventions.md`) allows names. This holds for the commands and plans written later, too.
- A marked assumption beats a silent invention.
- Examples in prompts are open lists, not checklists. Agents take named examples literally and weight them above everything else; when a prompt (yours or a template's) lists examples, say explicitly that they are examples and ask for anything else that matters.

## Output structure

Root of the target repository (files this skill writes or copies; the product code is untouched):

```
CLAUDE.md (only if none)  .gitignore  .gitattributes
.claude/commands/slice.md
.claude/scripts/slice-loop.ps1  slice-loop.sh
work/
  conventions.md            how this repository works (first round)
  session-hints.md          hints for slice sessions, grown round by round
  checklist.md              | NN | name | Plan | Tests red | Green | Checks | Commit |  (agent-ticked)
  _slices.json              input for render_slices.py
  rounds/R01-<slug>.md      Status: open|closed; intake or brief, slice map, decisions, open decisions, manual test list
  slices/NN-<slug>.md       one file per slice (rendered)
  plans/<date>-slice-NN.md  the plan each /slice writes
  research.md               only when a round needed research
  _raw/                     working material (git-ignored)
```
