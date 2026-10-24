---
name: vibe-rebuild
description: Turns an existing app (repo, codebase, legacy system) into a rebuild plan for vibe coding with AI agents – analysis.md, PRD, glossary, CLAUDE.md guardrails, vertical slices with ready-to-run prompts, and acceptance cases that keep what users rely on. Use whenever someone wants to rebuild, rewrite, migrate, modernize or port an existing application to another stack with Claude Code or other coding agents, or needs a rebuild/migration plan, a spec or task breakdown derived from existing code, or a brownfield vibe-coding strategy – even if they never say "vibe coding". Not for greenfield apps without existing code, single features, or plain code reviews.
license: MIT
compatibility: Designed for Claude Code and Claude with file access and subagents; scripts need Python 3.10+; the generated rebuild-loop needs the claude CLI plus PowerShell 7 or bash.
metadata:
  author: vompa
  version: "2.3.0"
---

# Vibe Rebuild – rebuild an existing app with vibe coding

Goal: turn an existing codebase into a plan a coding agent can follow to rebuild the app slice by slice – in the same or another stack.
**Not a copy:** the original is the template, not the yardstick. The rebuild keeps what users and callers rely on – business behaviour and the contracts others depend on – and builds everything else better, guided by the legacy findings and the target-stack research.
The plan is **self-contained**: the analysis captures everything the original does, so once the plan is written the rebuild needs neither the original's code nor a running original. What must stay is proven against cases written into the plan, not against the old system.
The skill extracts the app's *intent* (behaviour, contracts, business numbers), not its implementation, and copies no code. Why: copying code drags the legacy along; carrying over only behaviour and contracts lets you re-cut the design cleanly and still prove that nothing users rely on got lost.

Write the plan in the user's language (default: English).

## Keep the chat clean

The user reads the chat; the work happens in files. This run produces long intermediate material (agent reports, inventories, drafts) that must never land in the conversation:

- **Agent reports are working material.** When a subagent finishes, its result (and any `<task-notification>`, `<result>` or other system/tool markup around it) is for you, not the user. Never paste, quote or echo it. Save the report body to `rebuild/_raw/<area>.md` right away and continue.
- **Between steps, one short status line at most** (e.g. "Analysis 3/4 done – data layer still running."). No headings, no bullet dumps of findings mid-run.
- **Findings go into the plan files**, not into chat messages. The final message is a short summary: what was produced, the 2–3 most important findings, the open architecture questions, and the delivered folder/zip.

## Keep the user posted

Clean does not mean silent. A user staring at a window where nothing moves for twenty minutes assumes the run hung. So:

- **Announce long steps.** Before any step that can take more than a few minutes (parallel analysis, research), say in one line what runs and roughly how long it takes.
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

Repo/path (read only), target stack (default: same stack, current versions), scope, and **where the plan should live**: a local git repo (default – ask for the full path), GitHub if local is not possible, or files only (folder + zip).
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

`PRD.md`: behaviour from the user's point of view – purpose, principles, users/roles, features with a story and Given/When/Then acceptance criteria, edge cases, error behaviour, a short API contract, "Improvements on purpose" (from legacy findings and research, each with its reason), non-goals. No class or file names. If a good spec exists, don't copy it – reference it and add only the acceptance criteria.
`GLOSSARY.md`: term | code identifier | meaning. The agent uses only these terms.

Templates: `references/templates.md`.

## 5. Target-stack research → `rebuild/research.md`

The analysis tells you what the old app does; it says nothing about how the target stack is built well *today*. Without this step, versions, architecture and guardrails come from training data – often outdated, and blind to whatever the model happens not to think of.

Collect first, decide later:

1. **State the goal openly** – "rebuild <app> on <target stack> following current best practice". Don't hand the research a short list of topics to check: an agent given two examples examines those two thoroughly and treats everything else as out of scope.
2. **Go broad**: current stable versions and support windows, recommended project structure, how architecture rules are enforced, testing and parity tooling, and the target-stack equivalents of every area in `analysis.md` (persistence, auth, messaging, UI, deployment …). Save everything, structured and with sources, to `research.md`.
3. **Go deep**: derive follow-up queries from what step 2 found and dig into each point that matters for this app – breaking changes, known pitfalls, migration guides from the source stack. **License and terms of every package you would recommend**: licence, paid tiers, sponsorship or registration duties that a build enforces (some packages break the build until a declaration is made). A package that needs money or a licence decision goes to the user, not into `CLAUDE.md`.
4. **Probe what reading cannot show**: if the target SDK is available, build a throwaway hello-world for the risky paths – the planned transport or hosting, the distribution path (package, tool, container), how the process starts, stops and logs – in a scratch folder outside the plan repo. Record what behaved differently from the docs under "Pitfalls & breaking changes", marked `[Probed]`. Reading-only research tends to find no pitfalls; the real ones show up the first time something runs. Without the SDK, make the probe the first task of slice 00.
5. **Distill**: end `research.md` with "Decisions for this rebuild" – each with the finding it rests on and its source. These feed `CLAUDE.md` (§6), the slice order (§7) and the rebuild-vs-refactor assessment (§9).
6. **Present before slicing**: decisions that change architecture or scope go to the user together with the architecture-relevant open questions.

**Run it in passes, not as one long job.** Research is the longest step of the run, so it follows "Keep the user posted" strictly: launch broad, deep and distill as separate short runs (one subagent call each, or inline), and after each pass post one status line – e.g. "Research broad done: 14 topics, 31 sources – going deep on 6 points (~5 min)." The research agent appends each finished topic to `research.md` immediately and logs one line per topic in `_raw/research-progress.md`, so progress is visible even mid-pass.

Use `references/research-prompt.md` when delegating this to a subagent. Same stack and versions stay the same → keep it short: versions, deprecations, current conventions.
Search queries contain only generic technology terms – never code, internal names, customer data or secrets from the original.

## 6. Guardrails → `CLAUDE.md` (repo root)

Built on the decisions in `research.md`, not on defaults from memory. Target architecture with allowed dependency directions – and how it is **enforced** (architecture tests such as NetArchTest/ArchUnit, analyzer rules). Rules that exist only as text don't survive many agent sessions, so:

- **One architecture test per rule.** Every dependency rule written in the Architecture section gets its own test, and `CLAUDE.md` lists the mapping rule → test. A rule without a test is a gap for slice 00, not a guideline.
- **Every quality gate is proven to bite.** Build flags such as "warnings as errors" or "enforce code style" can silently skip rule groups (naming rules, formatting). Slice 00 commits a deliberate violation per gate in a throwaway branch, shows the build or CI turning red, and removes it; the formatter/linter check runs in CI, not only locally.
- **Approved packages with their licence**: a short table package | version line | licence; anything else needs asking.

Plus: hard rules (file size, single responsibility, constants defined once, no secrets, no new packages without asking), "Forbidden" = legacy findings, exact commands, way of working (plan with assumptions → failing tests → code, one slice per session, task commits on branch `slice-NN`, **one squash commit per green slice on `main`**).

## 7. Slicing → `rebuild/slices/NN-name.md`

Vertical and ordered by dependency; slice 00 = scaffold including CI, the parity harness, one architecture test per rule in `CLAUDE.md` (mapping complete) and the proof that every quality gate turns red on a violation (§6). Sizing: one slice ≈ one agent session (1–2 h), roughly one slice per 1.5–2k lines of the original.
Record the slices as a list in `rebuild/_slices.json` and render them:
```
python3 scripts/render_slices.py rebuild/_slices.json rebuild/slices --lang <plan language>
```
`--lang` writes the slice files and their prompts in the plan's language (`en`, `de` built in). For another language, render with `en` and translate the headings and the prompt, keeping file paths and command names unchanged.
Each slice has goal, PRD reference, dependencies, scope, a ready-to-run prompt (plan first, then failing tests, then code), a Definition of Done with the concrete parity cases, and non-goals.

## 8. Parity → `rebuild/parity/`

The safety net that lets the rebuild be better without losing anything. Sort the cases into three kinds:

| Kind | Example | In the rebuild |
|---|---|---|
| **Business contract** | rules, calculations, KPIs, totals, start states from domain docs and tests | keep – check strictly |
| **Interface contract** | what external callers depend on: operation names, parameters, defaults, data formats, status codes, event order | keep for compatibility; change only on purpose, recorded as an improvement |
| **Implementation-bound** | wording and layout of messages, checksums over random generators, byte snapshots, timing | not carried over – the rebuild may do it better; check the information, not the exact form |

Sources, in this order – all read during planning, none needed afterwards:
1. **The original's existing tests** – usually the richest source; turn assertions into cases (input → expected output).
2. **The code itself** for behaviour no test pins: exact response and error formats, limits, defaults, edge cases – taken from the analysis and spot-checked against the code.
3. Domain documents.

Write every case into `rebuild/parity/` as concrete input → expected output, with exact values and the source it came from, so the rebuild's acceptance tests can be written from the plan alone. Each test creates its own fixtures (files, data, config). The original is never built, started or queried to run these tests – not while planning, not while building.

For messages and other output, a case pins the information that must be there (e.g. which lines were read, why an edit failed), not the exact wording. Free prose such as help or description texts is not copied – the rebuild writes its own from the PRD.

Never call non-deterministic dependencies (LLM calls, external APIs, wall-clock time) live in parity tests: use scripted fakes/stubs, record deterministic fallbacks, freeze the clock.
`parity/README.md` describes the harness (how cases become tests), normalization of volatile values, and a deviation log (bug in the rebuild vs. improvement on purpose + PRD reference).

## 9. Handover

`README.md` with:
- **Origin** – full link to the original (repository URL, path inside it if only part was rebuilt, commit, licence) and one line "Plan created with vibe-rebuild <version> on <date>". The README later becomes the product README, and readers must be able to find the original without asking.
- **Assessment: rebuild vs. refactor** – if the original is already well structured and tested, a targeted refactor of the legacy findings is often cheaper; then say which slices would suffice for that. Weigh in what `research.md` found about the target stack (migration effort, breaking changes).
- File overview and slice dependency graph (what can run in parallel), as a Mermaid block in the README plus rendered images (`rebuild/slice-graph.mmd/.png/.svg`), so it shows wherever the README is read. Size the picture for where it is seen:
  - **Up to ~6 slices:** one compact top-down diagram is enough for the README and the side panel.
  - **More slices:** a document version at roughly 2:1 for the README (group parallel strands into lanes and draw arrows between lanes, not between every slice, so lines don't cross) and a portrait version without group frames (`slice-graph-panel.png`) for the side panel or chat.
  - Render with Mermaid CLI when available; otherwise ship the `.mmd` and the Mermaid block only. Show the panel image directly below the delivered result.
- **Getting started** from `references/getting-started.md`, filled in for this plan – prerequisites, the `/rebuild` flow, commands, parallel work, what to do when something goes wrong, where things are. Someone who has never seen the plan must be able to start from it alone.
- `checklist.md` (slice × plan / tests red / green / parity / commit): one row per slice starting with `| NN `, every cell `☐` until done, then `☑` – `/rebuild` and `rebuild-loop` read exactly this format.
- `.claude/commands/rebuild.md` – copy `references/rebuild-command.md` unchanged. `/rebuild` picks the next ready slice (or `/rebuild NN`, `/rebuild status`), uses superpowers when it is installed and the slice prompt otherwise, and closes each slice with the next ready ones.
- `.claude/scripts/rebuild-loop.ps1` and `.claude/scripts/rebuild-loop.sh` – copy `assets/rebuild-loop.ps1` and `assets/rebuild-loop.sh` unchanged with a file copy (`cp` / `Copy-Item`), not by rewriting them, and add `*.sh text eol=lf` to the target repo's `.gitattributes` – a CRLF bash script fails with `$'\r'`. They run every slice in its own fresh headless Claude session, stop for plan approval, and move on to the next ready slice, so nobody has to type `/rebuild` after each slice.

**No personal or machine data in any file.** Paths in files are relative to the repo ("open a terminal in the repo folder"); the full local path appears only in the handover message in chat. No user names, machine names, private e-mail addresses or personal names – decisions are recorded as "User, <date>".

**Where the plan goes – in this order:**

1. **Local git repo (default).** Ask for the full local path and show it back in full in chat (e.g. `C:\Development\Repositories\<name>`, never `~/…` or a bare name) – but never write it into a file. The plan becomes the target repo: only `CLAUDE.md` (Claude Code loads it from the root), `README.md`, `.gitignore`, `.gitattributes` and `.claude/` (commands and scripts) sit at the root; every plan document goes into `rebuild/`, detailed per-slice plans into `rebuild/plans/`, and the root stays free for `src/` and `tests/` from slice 00 on. `git init`, a `.gitignore` for the target stack, one initial commit.
   **Check the commit identity first**: a fresh repo commits with the global git identity, which is often a private address. Show `git config user.name` / `user.email` and, if it looks private, ask which identity to use (e.g. the GitHub noreply address) and set it with `git config --local` – the plan commit is the first thing that becomes public when the repo is pushed.
2. **GitHub**, when a local repo is not possible: the user creates an empty repo and names it, you push the initial commit (or a new branch in an existing repo).
3. **Files only**, when the user wants neither: deliver the folder and a zip and say how to turn it into a repo later.

**Check where you run before writing anything** – the way to reach the target path depends on it:

| Environment | How you notice | How to write the repo |
|---|---|---|
| Claude Code on the user's machine | the target path is on your own file system; normal file tools and shell work there | write all files directly, including `.git/` and `.claude/`; run `git init`, `git add`, `git commit` as usual |
| Cloud session linked to the user's machine | remote-device tools are present; your own file system is a container | plain files via the file-transfer tool; `.git/` and `.claude/` are protected for transfer tools, so create them with the device shell: build the repo in a scratch folder on the device (`git init`, commit), then copy `.git/` and `.claude/` into the target folder. On a Windows folder mounted into a Linux shell, set `core.filemode=false`. Never ask for delete rights on a parent folder that holds other projects. |
| No access to the user's machine | neither of the above | offer GitHub (2.) or files (3.) |

Verify at the end, whatever the environment: `git log` shows the commit with the agreed identity, `git status` is clean, `.claude/commands/rebuild.md` and both `.claude/scripts/rebuild-loop.*` exist, and a search over all committed files finds no absolute path, user or machine name.

The original stays untouched.

**Handover message.** Keep it short and concrete, so the user knows exactly what to do next:
1. The full location (local path, repo URL, or the delivered files).
2. How to start: "Open a terminal in <full path>, run `claude`, type `/rebuild`." – plus one sentence on what happens then (it picks slice 00, shows a plan, builds after approval). Then the hands-off way: "or run `pwsh .claude/scripts/rebuild-loop.ps1` (`bash .claude/scripts/rebuild-loop.sh`) – it runs all slices one after another in fresh sessions and only stops for your plan approvals."
3. Prerequisites that are still missing on the user's side (e.g. the target SDK), if any.
4. One line pointing to the README section "Getting started" for commands, parallel work and troubleshooting.
For files only, give the same steps as an example directly below the delivered files, with "after unpacking into a folder and running `git init`" as the first step. Mention that superpowers is optional and detected automatically; never install it yourself.

## Rules

- Never modify the original; only read it.
- The plan must stand on its own: anything the rebuild needs from the original goes into the plan files. If a slice would need to look at the original, the analysis has a gap – close it in the plan.
- Copy no code – behaviour, data contracts, interfaces and business numbers, yes.
- Never put secrets, connection strings or personal test data into the plan; use placeholders.
- No personal or machine data in files: no absolute paths, user or machine names, private e-mail addresses or personal names (decisions: "User, <date>"). This holds for the commands and plans written later, too.
- A marked assumption beats a silent invention.
- Examples in prompts are open lists, not checklists. Agents take named examples literally and weight them above everything else; when a prompt (yours or a template's) lists examples, say explicitly that they are examples and ask for anything else that matters.

## Output structure

Root of the git repo (or the delivered folder when the user chose files only):

```
CLAUDE.md  README.md  .gitignore  .gitattributes
.claude/commands/rebuild.md
.claude/scripts/rebuild-loop.ps1  rebuild-loop.sh
rebuild/
  analysis.md  research.md  open-questions.md  PRD.md  GLOSSARY.md  checklist.md
  slices/00-scaffold.md … NN-*.md
  parity/README.md  <area>-cases.md  deviations.md
  plans/                 (detailed per-slice plans, e.g. from superpowers)
  _inventory.md  _slices.json  _raw/   (agent reports, working material)
src/  tests/             (from slice 00 on)
```
