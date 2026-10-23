---
name: vibe-rebuild
description: Turns an existing app (repo, codebase, legacy system) into a rebuild plan for vibe coding with AI agents – analysis.md, PRD, glossary, CLAUDE.md guardrails, vertical slices with ready-to-run prompts, and parity tests against the original. Use whenever someone wants to rebuild, rewrite, migrate, modernize or port an existing application to another stack with Claude Code or other coding agents, or needs a rebuild/migration plan, a spec or task breakdown derived from existing code, or a brownfield vibe-coding strategy – even if they never say "vibe coding". Not for greenfield apps without existing code, single features, or plain code reviews.
license: MIT
compatibility: Designed for Claude Code and Claude with file access and subagents; scripts need Python 3.10+.
metadata:
  author: vompa
  version: "2.2.0"
---

# Vibe Rebuild – rebuild an existing app with vibe coding

Goal: turn an existing codebase into a plan a coding agent can follow to rebuild the app slice by slice while staying **provably equivalent** to the original.
The skill extracts the app's *intent* (behaviour, contracts, business numbers), not its implementation, and copies no code. Why: copying code drags the legacy along; carrying over only behaviour and contracts lets you re-cut the design cleanly and still prove parity.

Write the plan in the user's language (default: English).

## Keep the chat clean

The user reads the chat; the work happens in files. This run produces long intermediate material (agent reports, inventories, drafts) that must never land in the conversation:

- **Agent reports are working material.** When a subagent finishes, its result (and any `<task-notification>`, `<result>` or other system/tool markup around it) is for you, not the user. Never paste, quote or echo it. Save the report body to `rebuild/_raw/<area>.md` right away and continue.
- **Between steps, one short status line at most** (e.g. "Analysis 3/4 done – data layer still running."). No headings, no bullet dumps of findings mid-run.
- **Findings go into the plan files**, not into chat messages. The final message is a short summary: what was produced, the 2–3 most important findings, the open architecture questions, and the delivered folder/zip.

## Keep the user posted

Clean does not mean silent. A user staring at a window where nothing moves for twenty minutes assumes the run hung. So:

- **Announce long steps.** Before any step that can take more than a few minutes (parallel analysis, research, building and testing the original), say in one line what runs and roughly how long it takes.
- **No silent stretch longer than ~5 minutes.** Cut long work into pieces that each come back within a few minutes and post a status line after each piece: what finished, one number that shows progress (topics, sources, files, tests), what runs next. If the session offers a way to check in on a running task (a wake-up/monitor/send-later tool), use it instead of waiting blind.
- **Make progress visible in files too.** Long-running agents append to their output file as they go (see §5) rather than writing everything at the end, so a status line can report real progress.
- Status lines stay short and factual – no findings dumps, no agent markup.
- **Start every status line with an overall percentage**, e.g. `[45 %] Analysis done (3/3) – research broad pass running (~5 min).` The percentage is a phase-based estimate, not a promise of remaining time:

  | Phase | Weight | Counted inside the phase by |
  |---|---|---|
  | 1–2 Inputs, inventory | 5 % | done / not done |
  | 3 Analysis | 25 % | explorer agents finished / launched, merge + spot-check counts as the last share |
  | 4 PRD & glossary | 10 % | files written |
  | 5 Target-stack research | 20 % | passes finished (broad, deep, distill); within a pass, topics finished / planned from `_raw/research-progress.md` |
  | 6 Guardrails | 5 % | done / not done |
  | 7 Slicing | 15 % | slices written / planned |
  | 8 Parity | 15 % | case files written / planned |
  | 9 Handover | 5 % | README, checklist, zip |

  Sum the finished phases plus the counted share of the running one, round to 5 %. The number only goes up; if the plan grows (more slices than expected), slow it down rather than step back. Never show 100 % before the zip is delivered. When phases are skipped (e.g. no research because nothing changes), give their weight to the next phase.
- When the task list is available, keep it in step with the same phases so the percentage and the list never disagree.

## 0. Pick your tools

Check what is available and tell the user in one line what you will use.

| Task | Preferred | Fallback |
|---|---|---|
| Analysis | `feature-dev:code-explorer` agents in parallel; a code-to-PRD skill if one exists | `Explore` subagents |
| Target-stack research | web search + fetch (a deep-research skill if one exists) | model knowledge, every finding marked `[Unverified]` |
| Sharpen the spec | `superpowers:brainstorming` | up to 5 questions to the user |
| Execution later | `/rebuild` command written into the target repo (§9); uses superpowers if installed, never installs it | slice prompts |
| Improve this skill | `skill-creator` | – |

This skill produces the plan; execution happens in a later session in the target repo. Never install plugins or tools for the user – only suggest commands for what is already there.

## 1. Inputs (one round, then go)

Repo/path (read only), target stack (default: same stack, current versions), scope, whether the original runs locally, and **where the plan should live**: a local git repo (default – ask for the full path), GitHub if local is not possible, or files only (folder + zip).
Ask all of these in one go. For the target stack offer concrete options (same stack, 2–3 plausible alternatives for this app, other) rather than a bare "different stack", so no second round of questions is needed.
If the user is away or asks for a trial run, make sensible assumptions, mark them `[Assumption]`, and keep going.

## 2. Inventory (fast, before the agents)

```
python3 scripts/inventory.py <repo> > rebuild/_inventory.md
```
Lists projects, files and lines per folder, files over 300 lines, test files, and existing documentation.
Make two decisions from it:

- **Is there an existing spec?** (`docs/`, `spec*`, `PRD*`, ADRs, mockups, calibration/domain documents). If so, it is the primary source of intent; code and tests show the actual state. Set a **source precedence** (e.g. domain document > tests > spec > mockup > comments) and record it in the PRD. Contradictions between sources are normal and valuable – collect them, don't smooth them over.
- **Analysis split**: 3–5 areas along layers or projects (e.g. domain + simulation, data/persistence, API/integrations, frontend + infra + tests). Rule of thumb: one agent per ~8–12k lines.

## 3. Analysis → `rebuild/analysis.md`

Launch the explorer agents in parallel, one per area, using the template in `references/explorer-prompt.md`. As each one finishes, save its report to `rebuild/_raw/<area>.md` (silently – see "Keep the chat clean"). When all are in, merge them into one file with this schema:

```
# Analysis
## Stack & runtime   ## Domain   ## Features   ## Interfaces
## Non-functional    ## Existing tests   ## Legacy findings   ## Open questions
```

This schema is the interface to every later phase – if an external reverse-engineering skill delivers the analysis, map its output into this schema first.

**Spot-check before building on it**: verify 3–5 hard numbers from the agent reports (counts of tools/endpoints/tests, default limits) against the code with `grep`. Subagents tend to estimate counts; a wrong number in the PRD becomes a wrong acceptance criterion later.

**Open questions** go into a separate `open-questions.md`, grouped as *architecture-relevant* (changes target architecture or scope), *functional*, and *dropped in the rebuild*, each with the `[Assumption]` taken. Put the architecture-relevant ones to the user before slicing if they are reachable; otherwise continue on assumptions and say so clearly in the README.

## 4. PRD & glossary

`PRD.md`: behaviour from the user's point of view – purpose, principles, users/roles, features with a story and Given/When/Then acceptance criteria, edge cases, error behaviour, a short API contract, "Legacy bugs fixed on purpose", non-goals. No class or file names. If a good spec exists, don't copy it – reference it and add only the acceptance criteria.
`GLOSSARY.md`: term | code identifier | meaning. The agent uses only these terms.

Templates: `references/templates.md`.

## 5. Target-stack research → `rebuild/research.md`

The analysis tells you what the old app does; it says nothing about how the target stack is built well *today*. Without this step, versions, architecture and guardrails come from training data – often outdated, and blind to whatever the model happens not to think of.

Collect first, decide later:

1. **State the goal openly** – "rebuild <app> on <target stack> following current best practice". Don't hand the research a short list of topics to check: an agent given two examples examines those two thoroughly and treats everything else as out of scope.
2. **Go broad**: current stable versions and support windows, recommended project structure, how architecture rules are enforced, testing and parity tooling, and the target-stack equivalents of every area in `analysis.md` (persistence, auth, messaging, UI, deployment …). Save everything, structured and with sources, to `research.md`.
3. **Go deep**: derive follow-up queries from what step 2 found and dig into each point that matters for this app – breaking changes, known pitfalls, migration guides from the source stack.
4. **Distill**: end `research.md` with "Decisions for this rebuild" – each with the finding it rests on and its source. These feed `CLAUDE.md` (§6), the slice order (§7) and the rebuild-vs-refactor assessment (§9).
5. **Present before slicing**: decisions that change architecture or scope go to the user together with the architecture-relevant open questions.

**Run it in passes, not as one long job.** Research is the longest step of the run, so it follows "Keep the user posted" strictly: launch broad, deep and distill as separate short runs (one subagent call each, or inline), and after each pass post one status line – e.g. "Research broad done: 14 topics, 31 sources – going deep on 6 points (~5 min)." The research agent appends each finished topic to `research.md` immediately and logs one line per topic in `_raw/research-progress.md`, so progress is visible even mid-pass.

Use `references/research-prompt.md` when delegating this to a subagent. Same stack and versions stay the same → keep it short: versions, deprecations, current conventions.
Search queries contain only generic technology terms – never code, internal names, customer data or secrets from the original.

## 6. Guardrails → `CLAUDE.md` (repo root)

Built on the decisions in `research.md`, not on defaults from memory. Target architecture with allowed dependency directions – and how it is **enforced** (architecture tests such as NetArchTest/ArchUnit, analyzer rules). Rules that exist only as text don't survive many agent sessions.
Plus: hard rules (file size, single responsibility, constants defined once, no secrets, no new packages without asking), "Forbidden" = legacy findings, exact commands, way of working (plan → failing tests → code, one slice per session, one commit per green slice).

## 7. Slicing → `rebuild/slices/NN-name.md`

Vertical and ordered by dependency; slice 00 = scaffold including CI, architecture tests and the parity harness. Sizing: one slice ≈ one agent session (1–2 h), roughly one slice per 1.5–2k lines of the original.
Record the slices as a list in `rebuild/_slices.json` and render them:
```
python3 scripts/render_slices.py rebuild/_slices.json rebuild/slices
```
Each slice has goal, PRD reference, dependencies, scope, a ready-to-run prompt (plan first, then failing tests, then code), a Definition of Done with the concrete parity cases, and non-goals.

## 8. Parity → `rebuild/parity/`

The central lever. Sort parity cases into three kinds, because they are not equally robust:

| Kind | Example | In the rebuild |
|---|---|---|
| **Business contract** | KPIs, totals, start states from domain docs and tests | check strictly |
| **Interface contract** | status codes, error formats, field names, event order | check strictly |
| **Implementation-bound** | checksums over random generators, byte snapshots, timing | do not carry over; define anew in the rebuild |

Sources, in this order:
1. **The original's existing tests** – usually the richest source; turn assertions into cases (input → expected output).
2. **Recordings against the running original** (request/response per endpoint and role), volatile fields normalized; compare with Verify/approval tests or similar.
3. Domain documents.

Never call non-deterministic dependencies (LLM calls, external APIs, wall-clock time) live in parity tests: use scripted fakes/stubs, record deterministic fallbacks, freeze the clock.
`parity/README.md` describes harness, recording, normalization, and a deviation log (bug in the rebuild vs. fixed on purpose + PRD reference).

## 9. Handover

`README.md` with:
- **Assessment: rebuild vs. refactor** – if the original is already well structured and tested, a targeted refactor of the legacy findings is often cheaper; then say which slices would suffice for that. Weigh in what `research.md` found about the target stack (migration effort, breaking changes).
- File overview and slice dependency graph (what can run in parallel).
- **Getting started** from `references/getting-started.md`, filled in for this plan – prerequisites, the `/rebuild` flow, commands, parallel work, what to do when something goes wrong, where things are. Someone who has never seen the plan must be able to start from it alone.
- `checklist.md` (slice × plan / tests red / green / parity / commit).
- `.claude/commands/rebuild.md` – copy `references/rebuild-command.md` unchanged. `/rebuild` picks the next ready slice (or `/rebuild NN`, `/rebuild status`), uses superpowers when it is installed and the slice prompt otherwise, and closes each slice with the next ready ones.

**Where the plan goes – in this order:**

1. **Local git repo (default).** Ask for the full local path and show it back in full (e.g. `C:\Development\Repositories\<name>`, never `~/…` or a bare name). The plan becomes the target repo: only `CLAUDE.md` (Claude Code loads it from the root), `README.md` and `.gitignore` sit at the root; every plan document goes into `rebuild/`, detailed per-slice plans into `rebuild/plans/`, and the root stays free for `src/` and `tests/` from slice 00 on. `git init`, a `.gitignore` for the target stack, one initial commit. If the session reaches the user's machine only through remote file tools that may not write `.git`, build the repo in a scratch folder there and copy the finished `.git` in – never ask for delete rights on a parent folder that holds other projects.
2. **GitHub**, when a local repo is not possible: the user creates an empty repo and names it, you push the initial commit (or a new branch in an existing repo).
3. **Files only**, when the user wants neither: deliver the folder and a zip and say how to turn it into a repo later.

The original stays untouched.

**Handover message.** Keep it short and concrete, so the user knows exactly what to do next:
1. The full location (local path, repo URL, or the delivered files).
2. How to start: "Open a terminal in <full path>, run `claude`, type `/rebuild`." – plus one sentence on what happens then (it picks slice 00, shows a plan, builds after approval).
3. Prerequisites that are still missing on the user's side (e.g. build the original), if any.
4. One line pointing to the README section "Getting started" for commands, parallel work and troubleshooting.
For files only, give the same steps as an example directly below the delivered files, with "after unpacking into a folder and running `git init`" as the first step. Mention that superpowers is optional and detected automatically; never install it yourself.

## Rules

- Never modify the original; only read it and run parity tests.
- Copy no code – behaviour, data contracts, interfaces and business numbers, yes.
- Never put secrets, connection strings or personal test data into the plan; use placeholders.
- A marked assumption beats a silent invention.
- Examples in prompts are open lists, not checklists. Agents take named examples literally and weight them above everything else; when a prompt (yours or a template's) lists examples, say explicitly that they are examples and ask for anything else that matters.

## Output structure

Root of the git repo (or the delivered folder when the user chose files only):

```
CLAUDE.md  README.md  .gitignore
.claude/commands/rebuild.md
rebuild/
  analysis.md  research.md  open-questions.md  PRD.md  GLOSSARY.md  checklist.md
  slices/00-scaffold.md … NN-*.md
  parity/README.md  <area>-cases.md  deviations.md
  plans/                 (detailed per-slice plans, e.g. from superpowers)
  _inventory.md  _slices.json  _raw/   (agent reports, working material)
src/  tests/             (from slice 00 on)
```
