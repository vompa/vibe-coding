# vibe-coding – design

Status: **approved by the user on 2026-10-24** (User: keep the name `vibe-coding`; the dry run is the real round 1 in the user's main project on its `dev` branch; rename the GitHub repository right after approval). Written in English like everything else in this repository.

## 1. Intent

`vibe-rebuild` turns a legacy codebase into a plan and then executes it slice by slice: one fresh Claude session per slice, plan first, tests first, one squash commit per slice, a hands-off loop, decisions recorded in files. The user wants the same way of working for everyday coding, where the input is not an old codebase but

- a **findings list** – the result of a UI review (for example all screens checked against a design-system skill) or the user's own test notes after trying a build, or
- a **feature idea** – a new package of work such as "make the point of sale ready for real operation", which starts as an idea, a concept document and a few screenshots.

Why: the current practice in the user's main project already works in rounds (review → change list → implementation in blocks → user test → new findings → … → "alpha" → field test), but it is run by hand and each block used to be a pull request. Slices with one squash commit each cut the number of pull requests, a fresh session per slice keeps the context clean, and files instead of chat keep the decisions. `vibe-coding` makes this repeatable in any repository, with or without existing conventions.

## 2. Goals

1. **Two intakes, one output.** A findings list (file or chat) or an idea (sharpened in a short brainstorm into a brief with Given/When/Then acceptance criteria) both become a *round*: slices, prompts, Definition of Done, checklist.
2. **Execution exactly as in vibe-rebuild.** A project command (`/slice`) picks the next ready slice, plans with assumptions and review focus, waits for approval, builds tests first, lands the slice as one squash commit on the repository's integration branch, records decisions, ticks the checklist. A loop script runs all slices in fresh headless sessions and stops only for plan approval. superpowers is used when installed, never installed.
3. **Honour the host repository.** Existing `CLAUDE.md`, working-method documents, protocol files, branch rules and check commands are discovered once, written to `work/conventions.md`, and followed. Nothing the repository already defines is redefined. In a repository without rules the skill creates a lean `CLAUDE.md` in the style of vibe-rebuild §6.
4. **Close the loop with the human.** Every round ends with the full check chain, a manual test list (screen by screen, step and expected result, which finding it closes) and an archived round record. The user's feedback on that list is the findings list of the next round.
5. **Ceremony scales with size.** A one-line finding does not get a PRD. Small findings are bundled into theme or screen slices; only ideas get a brief; research runs only when new technology or packages are involved.
6. **Ship as the second plugin** of the `vompa` marketplace in this repository, which is renamed to `vibe-coding`.

## 3. Non-goals

- No analysis of an existing codebase and no parity cases – that is `vibe-rebuild`. (A finished rebuild repository can continue with `vibe-coding` rounds; see §9.)
- No pull-request automation, no pushing, no GitHub issues, no merge queue.
- No replacement for superpowers; `vibe-coding` orchestrates, superpowers plans and builds when present.
- No in-session loop (Anthropic's `ralph-loop` re-feeds one session; the opposite of fresh-session-per-slice).
- No installation of plugins or tools; no deletion of branches or data without the user.
- Not in this version: migrating `vibe-rebuild` to the generic `/slice` command and loop (follow-up, §11).

## 4. Anti-goals (a failure even if it technically works)

- Verbose specification ceremony for small fixes (the pattern users criticise in Kiro and Spec Kit).
- Silently changing a repository's documented conventions – protocol format, integration branch, commit language, ADR rule.
- Duplicating existing classes or patterns instead of mirroring them (Huntley's and Fowler's reports).
- Reporting a slice as done without the Definition of Done proven, or a round as closed without the full check chain.
- Pushing, force-pushing, or rewriting history that has left the machine.
- Personal or machine data in files of a repository that may become public.

## 5. Constraints

- Agent Skills spec and Claude Code plugin format; `claude plugin validate --strict` must pass for marketplace and plugin; `skills-ref validate` for the skill.
- Everything in the repository in English (skill text, references, README, tests, commit messages); the files the skill writes into a target repository follow the user's language (German in the user's projects).
- Scripts: Python 3.10+ (`render_slices.py`), PowerShell 7 and bash for the loop, as in vibe-rebuild. Windows is the primary platform of the user; both loop scripts are tested with the fake `claude` CLI in CI.
- Headless sessions cannot answer prompts: plan approval is a two-run protocol (plan run exits with `PLAN:`/`NEEDS-DECISION:`, approval, resumed run builds) – already implemented in `rebuild-loop`; `--bare` is never used (it drops `CLAUDE.md`, skills and plugins).
- Privacy rules of the user: no secrets, no absolute paths, user names or private addresses in plugin files; in target repositories the repository's own rule applies (a private repository may name people; the skill asks once and records it in `work/conventions.md`).

## 6. Prior art and what it changes in this design

Two reports (web and locally installed plugins) were produced on 2026-10-24; they live in the session scratchpad, the conclusions are here.

- **Nothing covers the whole chain.** Fresh session per unit with state on disk exists (Anthropic's long-running-agent harness, snarktank/ralph, BMAD story files); plan gate, ledger, TDD and stop rules exist (superpowers); convention adoption exists (Agent OS, Gemini Conductor, ECC PRP "Patterns to Mirror"); findings-list intake, Given/When/Then from brief to test name, one squash commit per slice, and a round-end manual test list exist nowhere together.
- **The skill name is taken elsewhere.** `adhi-jp/agent-skills` ships a `vibe-coding` skill invoked as `/vibe-coding`; four more `vibe-coding` skills are listed on skills.sh; the Pawgrammer skills market lists Nate Jones's `vibe-coding` (Exploration-labs/Nates-Substack-Skills) – a methodology skill (intent definition, tool selection, iterative development, integration; a three-tier MVP scoping and a list of domains not to vibe-code such as payments or security) with no slices, sessions, approvals or loop. All of these are *how to prompt* skills; this one is a *how to run the work* skill, and its description and README must say so in the first sentence. Inside Claude Code a plugin skill is namespaced (`/vibe-coding:vibe-coding`) and cannot collide; a bare `/vibe-coding` would be ambiguous only for a user who also installed one of those. The GitHub repository `vompa/vibe-coding` is free; the official marketplace has no `vibe-coding` plugin. Consequence: the project command written into target repositories gets a distinctive name (`/slice`, not `/vibe-coding`), and the README says how to invoke the skill unambiguously.
- **Borrowed patterns** (each marked where it lands):
  - self-contained slice prompt for a reader who knows nothing (Codex ExecPlans, BMAD) → slice template;
  - "Patterns to mirror (file:line)" and "NOT building" (ECC PRP) → slice template, plan template;
  - living sections Progress / Surprises / Decision log (ExecPlans) and superpowers' ledger vocabulary (`Ruling:`, deferred minors) → round record;
  - machine-decidable Definition of Done plus a "must not" boundary, retry cap, human flips manual items (ECC `loop-design-check`) → DoD template, loop;
  - iteration and budget caps, no-progress breaker (Ralph, ECC loops, superpowers fix cap) → loop options;
  - size classifier to skip ceremony (ECC `orch-*`), "Independent test per slice" (Spec Kit) → intake rules;
  - session-start routine: read progress and git log, run a baseline check before changing anything (Anthropic harness) → `/slice` step 2;
  - convention discovery that extends instead of replacing (ECC `inherit-legacy-style`, `living-docs-governance`) → `work/conventions.md`.
- **Deliberately left out:** ECC `/epic-*` (needs GitHub issues), ECC GATE 2 commit confirmation (contradicts hands-off), `ralph-loop`, `/checkpoint`, per-task reviewer subagents as a default (cost; superpowers decides that itself), any hard dependency on `ecc:` agents.

## 7. The round model

A **round** is one intake, its slices and its close. Rounds are numbered `R01`, `R02`, …; **slices are numbered continuously across rounds** (`01` … `NN`), so `work/_slices.json`, `work/checklist.md` and the loop keep the exact formats of vibe-rebuild.

```
work/
  conventions.md            how this repository works (discovered once, §8)
  checklist.md              | NN | name | plan ☐ | tests red ☐ | green ☐ | checks ☐ | commit ☐ |   (agent-ticked only)
  _slices.json              input for render_slices.py (nr, slug, name, goal, round, source, deps, scope, mirror, not_building, acceptance, manual, non_goals)
  rounds/R01-<slug>.md      first line "Status: open" | "Status: closed"; intake, brief (ideas only), slice map, decision log, surprises, open decisions, manual test list
  slices/NN-<slug>.md       one file per slice (rendered)
  plans/<date>-slice-NN.md  the detailed plan each /slice writes
  research.md               only when a round needed research (versions, licences, pitfalls; appended per round)
  _raw/                     working material (agent reports, copies of findings files from outside the repo); git-ignored
.claude/commands/slice.md   the /slice command (copied unchanged from references/slice-command.md)
.claude/scripts/slice-loop.ps1 / .sh   the loop (copied unchanged from assets/)
```

Folder name `work/` and command name `/slice` are fixed – no configuration, so command, loop and tests stay simple and "copied unchanged" can be verified. If `work/` or `.claude/commands/slice.md` already exists for something else, the skill reports it and stops; the user resolves the conflict. Manual acceptance is **not** a checklist column: the human ticks items in the round record's manual test list, so the loop's "done = no ☐ in the row" rule stays exactly as in vibe-rebuild.

### 7.0 Handover into the repository

The skill works on the repository's integration branch (from `conventions.md`, for example `dev`). Before writing: the working tree must be clean and the current branch the integration branch, otherwise the skill stops and says what to do (headless: `ROUND-OPEN` with the reason); the git identity is shown and, if it looks private, asked for, as in vibe-rebuild. `work/`, `.claude/commands/slice.md` and `.claude/scripts/slice-loop.*` are **tracked** and committed as one commit per round start ("Round R01: <slug> – N slices") in the repository's commit language, because every slice runs in a fresh worktree cut from that branch and must see them. `work/_raw/` and `.slice-loop/` go into `.gitignore`; `*.sh text eol=lf` into `.gitattributes`. A findings file that lives outside the repository or is untracked is copied to `work/_raw/` (private repositories) or summarised into the round record (public repositories), so fresh sessions can read it.

### 7.1 Intake A – findings list

Input: a file (for example a review list with ids, rule, fix, classification, effort) or a chat message with the user's test notes, possibly with screenshots.

1. **Capture without copying.** A structured file is referenced; only ids go into the round record. Unstructured notes are written into the round record's intake table: `id | where (screen, file) | observed → expected | size S/M/L | source`. Ids continue the repository's own scheme when one exists (the user's project numbers findings `Ä…`, `W…`, `B…`); otherwise `F-NN`. A finding that reopens an earlier one is marked `reopens F-12`.
2. **Group into slices** by screen or by cross-cutting theme (all message bars, all field labels), ordered by dependency: shared components first, then screens, then the items the user still has to decide on. One slice ≈ one session (1–2 h). Trivial items are bundled into a sweep slice. An item classified "the user decides" becomes a `NEEDS-DECISION` line in the round record and is not sliced until answered.
3. **Acceptance per finding** is the observable fix (observed → expected), written as a Given/When/Then line in the slice's DoD. UI findings also get a manual check item (what to click, what to see), because unit tests alone miss them (Anthropic's harness report).

### 7.2 Intake B – idea

Input: a sentence, a concept document, screenshots, a competitor comparison.

1. **Brief** (≤ 1 page) in the round record: purpose, users, acceptance criteria `AC-NN` as Given/When/Then with exact numbers, edge cases, errors, non-goals, "NOT building", assumptions `[Assumption]`. When `superpowers:brainstorming` is installed the skill uses it to sharpen the idea; otherwise up to five questions in one go. Existing concept documents are referenced, not copied.
2. **Research** only if the brief introduces technology or packages the repository does not use yet: a short broad/deep/distill pass as in vibe-rebuild §5, including licence and terms of every recommended package, appended to `work/research.md`. Decisions that change architecture or cost go to the user before slicing.
3. **Slices** vertical and dependency-ordered, MVP first, each with an independent test; sizing as in 7.1.

### 7.3 Slice file (rendered from `_slices.json`)

Goal · Source (round, finding or AC ids) · Depends on · Scope · Patterns to mirror (`file:line`) · NOT building · Prompt (self-contained: read conventions, round record, slice; plan with assumptions and review focus; failing tests first; the minimum to go green; DoD; record) · Definition of Done (machine-checkable checks from `conventions.md`, acceptance cases Given/When/Then, manual check items, "must not" boundary such as "no test weakened or skipped") · Non-goals.

### 7.4 `/slice` – the project command

`.claude/commands/slice.md`, project-independent, copied unchanged; everything specific comes from `work/`. Arguments: `[status | NN | close] [plan] [auto] [direct]`.

- **status** – table slice / name / state (done, in progress, ready, blocked by …), then "Ready next".
- **NN or nothing** – as `/rebuild`: pick the lowest ready slice; read `conventions.md`, the round record, the slice file, `CLAUDE.md`; run the repository's baseline check before changing anything; superpowers path (`using-git-worktrees` on branch `slice-NN`, `writing-plans` saved to `work/plans/`, approval, `subagent-driven-development` or `executing-plans`, `finishing-a-development-branch` with the squash override: `git merge --squash slice-NN` onto the integration branch, never push) or direct path (branch, plan, approval, tests first, squash). `plan` stops after the plan with `PLAN:` and `NEEDS-DECISION:` lines; `auto` never asks.
- **Closing a slice** – run the checks named in `conventions.md` for a slice; tick the checklist; append to the round record: decisions (`Ruling:`), surprises, deferred minors, manual check items; write the repository's own protocol entry if `conventions.md` names one (for example a section in a PR protocol file with the fields that file uses); update the documents `conventions.md` lists as "must change with a change" (status page, help, ADR when a principle changed). End with the three lines of `/rebuild` (`Slice NN done`, `Ready next`, `Next step`) or the markers `SLICE-DONE: NN` / `SLICE-OPEN: NN <reason>`.
- **close** – round close of the one open round (`Status: open` in `work/rounds/`): requires every slice of that round (field `round` in `_slices.json`) to be ticked, otherwise `ROUND-OPEN: R01 <reason>`; runs the full check chain from `conventions.md` (red → `ROUND-OPEN` with the failing check); writes the manual test list into the round record (per slice: start command, steps, expected result, finding ids); sets `Status: closed`; lists open `NEEDS-DECISION` items, which the next round's record inherits; ends with `ROUND-DONE: R01`. Only one round is open at a time: a new intake first closes the open round or stops. When every slice is ticked and the round is still open, `/slice` proposes `close` (`ALL-DONE` in auto mode). With no open round, `/slice` says so and does nothing.
- **Missing or red checks** – if the baseline check is red before a slice starts, the slice stops (`SLICE-OPEN: NN baseline red: <check>`; interactive: ask). If the repository has no test or build command, the first round gets a harness slice first (test project, check chain, CI hook), proposed in the round record as `NEEDS-DECISION` when it changes the stack.

### 7.5 `slice-loop` – hands-off

`assets/slice-loop.ps1` and `.sh`, derived from `rebuild-loop` with three changes: folder and command are constants at the top (`work/`, `/slice`), `--max-slices N` caps the iterations, and after `ALL-DONE` the loop runs `/slice close auto` once and stops on `ROUND-DONE` or `ROUND-OPEN`. Before the first slice the loop checks that a round is open (`Status: open` in a round record) and otherwise prints "no open round" and exits, so re-running it on a finished repository does nothing. Options `-Yes`, `-Parallel` (experimental, as before), `-DryRun` stay. Stops on `NEEDS-DECISION`, a red slice, a slice reported done but not ticked, or no terminal for approvals. Logs in `.slice-loop/` (git-ignored). `REBUILD_PERMISSION_MODE` becomes `SLICE_PERMISSION_MODE` (default `auto`).

### 7.6 Keeping the chat clean and the user posted

Same rules as vibe-rebuild: agent reports go to `work/_raw/`, one status line per step with an overall percentage, no silent stretch over ~5 minutes. Phase weights for a round: conventions 10 (first round only), intake/brief 25, research 15 (when run), slicing 30, handover 20.

## 8. `work/conventions.md` – honouring the repository

Written on the first round in a repository, from: `CLAUDE.md`, `AGENTS.md`, README, any working-method or contribution document the `CLAUDE.md` links, protocol or changelog files, CI workflow, `.editorconfig`/format config, and `git log` (branch names, commit style, language). Content, one line each with its source:

- integration branch (for example `dev`), slice branch pattern (`slice-NN`), merge style (squash onto the integration branch; never push), commit language and style;
- exact commands: build, test (per project), lint/format check, baseline check, full check chain;
- where decisions are recorded (file, section title format; fields that exist only for pull requests, such as number or URL, are left out when a slice lands as a local squash commit) and which documents must change with a change; whether and when the integration branch becomes a pull request is the repository's own rule and is only noted here;
- language of UI, docs and tests; privacy rule for names in files;
- how to start the app for manual testing;
- work folder name; finding-id scheme in use.

Rules: extend, never replace (`CLAUDE.md` is only created when none exists); one canonical owner per fact – `conventions.md` points to the repository's documents instead of restating long rules; conflicts between documents are listed, not resolved silently; the user confirms the file once. A new repository gets a lean `CLAUDE.md` (purpose, hard rules, commands, way of working with one slice per session and one squash commit) plus `conventions.md` with defaults (`main`, squash, "User, <date>").

## 9. Relationship to vibe-rebuild

- Same formats for `_slices.json`, `checklist.md`, markers and the two-run approval protocol; `render_slices.py` gains the optional fields `source`, `mirror`, `not_building`, `acceptance`, `manual` (unknown fields are ignored, so the vibe-rebuild copy keeps working).
- A repository built with `vibe-rebuild` continues with `vibe-coding` after `ALL-DONE`: `conventions.md` is derived from its `CLAUDE.md`; `rebuild/` stays as the origin record; slice numbering in `work/` continues after the highest number in `rebuild/_slices.json` (rebuild 00–04 → first `work/` slice is 05), so branch names `slice-NN` and markers never collide. Slice numbers have at least two digits and grow to three when needed; command, loop and checklist already match any number of digits.
- `vibe-rebuild` 2.3.x is untouched apart from the repository links (§10). The generic `/slice` and `slice-loop` are candidates for `vibe-rebuild` 3.0 (follow-up).

## 10. Repository rename and packaging

- GitHub repository `vompa/vibe-rebuild` → `vompa/vibe-coding` (GitHub redirects the old name). Order: the rename comes **first**, right after this design is approved, so every new URL is written once; the user triggers or confirms it (`gh repo rename`), then `git remote set-url`; the local folder is renamed in a fresh session (a folder in use cannot be renamed). Pushing, tagging 2.3.1 and 1.0.0 and the plugin-directory submission are the user's approvals at the time; the builder prepares and asks. The non-goal "never push" in §3 is for the skill at run time; for building this plugin the user's standing rule applies: ask before anything public.
- Marketplace `vompa` stays; `.claude-plugin/marketplace.json` lists both plugins. Root `README.md` becomes the family README (what each plugin does, one install block, development); each plugin keeps its own README, PRIVACY, LICENSE and CHANGELOG (`CHANGELOG.md` moves to `plugins/vibe-rebuild/`, a new one starts at `plugins/vibe-coding/`).
- References to update: install commands in the root README, six URLs in `plugins/vibe-rebuild/.claude-plugin/plugin.json`, `PRIVACY.md`, plugin README; outside this repository the README of `mcp-time-net` and the user's knowledge base (`projects.md`). `vibe-rebuild` gets version 2.3.1 for the link change.
- New plugin `plugins/vibe-coding/` with `plugin.json` (version 1.0.0, MIT, same author block, keywords `vibe-coding`, `slices`, `feedback-loop`, `tdd`, `claude-code`, `superpowers`), skill `skills/vibe-coding/` (`SKILL.md`, `references/`, `assets/`, `scripts/`).
- CI (`validate.yml`): validate marketplace and both plugins, `skills-ref validate` both skills, `py_compile` all scripts, render a sample `_slices.json` with the new fields in `en` and `de`, syntax-check both loop scripts, run the loop test against both scripts (the fake-`claude` test is parametrised by folder and command).
- Plugin directory submission after the user's release decision (not part of this design).

## 11. What is left to the builder

- Exact wording of `SKILL.md` (trigger description with positive and negative cases, phases, status lines), the reference templates and the `/slice` command text; keep vibe-rebuild's style and its rules (open lists, not checklists; marked assumptions beat silent inventions).
- Parametrising `rebuild_loop_test.py` for both scripts and adding the `--max-slices`, `ROUND-DONE` and `close` cases.
- The trigger eval set for `vibe-coding` (positive: findings lists, test feedback, feature ideas, "slice this"; negative: rebuild requests, single bug fix, code review, upgrade) and a run against the installed plugin.
- A dry run in the user's main project (private; named in the user's own notes, not here): it is the real start of round 1 from the existing UI change list – `work/conventions.md` reflecting the `dev` branch and the protocol format, the slice map, `/slice status`, `/slice NN plan` – committed on `dev` only after the user has confirmed `conventions.md` and the slice map; no product code changes before the user's go for the first slice.
- Follow-up candidates, not in scope: `vibe-rebuild` 3.0 on the generic command and loop; structured session output (`--output-format json --json-schema`) instead of marker lines; per-session budget cap once the CLI flag is confirmed.

## 12. Decisions

Decided by the user (2026-10-24): the second plugin lives in this repository, which is renamed to `vibe-coding`; plugin and skill keep the name `vibe-coding` despite the methodology skills of the same name elsewhere; the dry run is the real round 1 in the user's main project on `dev`; the rename happens first. The items below were Claude's calls, approved with the design.

### Decisions made by Claude in this design

1. Work folder `work/` (root, visible, English), one folder for rounds, slices, plans, research; name changeable once per repository.
2. Project command `/slice` with `status | NN | close`, not `/vibe-coding` (name collision, generic term) and not `/rebuild` (misleading in non-rebuild repositories).
3. Continuous slice numbering across rounds; rounds as `R01…`; finding ids continue the repository's scheme.
4. Plan approval stays the only stop in hands-off mode; `-Yes` auto-approves but still stops on `NEEDS-DECISION`, red slices and unticked "done".
5. Round close is a `/slice close` run (also triggered by the loop after `ALL-DONE`), not a separate command.
6. Conventions are a pointer file (`work/conventions.md`), not a copy of the repository's rules; `CLAUDE.md` is created only where none exists.
7. Research is conditional (new technology or packages only) and reuses vibe-rebuild's §5 procedure and research-prompt.
8. Acceptance criteria are Given/When/Then end to end: brief → slice DoD → test names.
9. CHANGELOG per plugin; root README becomes the family README.
10. `vibe-rebuild` is not migrated to `/slice` in this version; duplication between `rebuild-loop` and `slice-loop` is accepted and listed as the follow-up.
11. Fixed names `work/` and `/slice`; a conflict is reported, not worked around.
12. The checklist keeps only agent-ticked columns; manual acceptance lives in the round record's test list.
13. Round start is one commit on the integration branch (tracked `work/` and `.claude/` files); `_raw/` and `.slice-loop/` are ignored; files from outside the repository are copied into `_raw/` (private) or summarised (public).
14. One open round at a time; `round` field in `_slices.json`; `Status:` line in the round record; markers `ROUND-DONE: Rnn` / `ROUND-OPEN: Rnn <reason>`; open decisions carry over.
15. Red baseline stops the slice; a repository without checks gets a harness slice first.
16. Continued rebuild repositories number on after the last rebuild slice; numbers may grow beyond two digits.
17. The GitHub rename comes first, after approval; every public step is the user's call at the time.

## 13. Success criteria (checked before "done")

1. `claude plugin validate --strict` passes for the marketplace and both plugins; `skills-ref validate` passes for both skills; CI green.
2. Trigger eval: at least 18 of 20 cases right over three runs, zero triggers on the vibe-rebuild negative cases and zero vibe-rebuild triggers on vibe-coding cases.
3. Loop test green for `slice-loop.ps1` and `slice-loop.sh` (auto approval, parallel, red slice, open decision, no terminal, max slices, all done + close).
4. Dry run in the user's main project produces `work/conventions.md`, `R01` with slices from the existing change list, `/slice status`, and a plan for one slice – without touching code.
5. No absolute path, user or machine name, private address or secret in any plugin file (scan over the committed files).
