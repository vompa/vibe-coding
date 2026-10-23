---
name: vibe-rebuild
description: Turns an existing app (repo, codebase, legacy system) into a rebuild plan for vibe coding with AI agents – analysis.md, PRD, glossary, CLAUDE.md guardrails, vertical slices with ready-to-run prompts, and parity tests against the original. Use whenever someone wants to rebuild, rewrite, migrate, modernize or port an existing application to another stack with Claude Code or other coding agents, or needs a rebuild/migration plan, a spec or task breakdown derived from existing code, or a brownfield vibe-coding strategy – even if they never say "vibe coding". Not for greenfield apps without existing code, single features, or plain code reviews.
license: MIT
compatibility: Designed for Claude Code and Claude with file access and subagents; scripts need Python 3.10+.
metadata:
  author: vompa
  version: "2.1.1"
---

# Vibe Rebuild – rebuild an existing app with vibe coding

Goal: turn an existing codebase into a plan a coding agent can follow to rebuild the app slice by slice while staying **provably equivalent** to the original.
The skill extracts the app's *intent* (behaviour, contracts, business numbers), not its implementation, and copies no code. Why: copying code drags the legacy along; carrying over only behaviour and contracts lets you re-cut the design cleanly and still prove parity.

Write the plan in the user's language (default: English).

## Keep the chat clean

The user reads the chat; the work happens in files. This run produces long intermediate material (agent reports, inventories, drafts) that must never land in the conversation:

- **Agent reports are working material.** When a subagent finishes, its result (and any `<task-notification>`, `<result>` or other system/tool markup around it) is for you, not the user. Never paste, quote or echo it. Save the report body to `vibe-plan/_raw/<area>.md` right away and continue.
- **Between steps, one short status line at most** (e.g. "Analysis 3/4 done – data layer still running."). No headings, no bullet dumps of findings mid-run.
- **Findings go into the plan files**, not into chat messages. The final message is a short summary: what was produced, the 2–3 most important findings, the open architecture questions, and the delivered folder/zip.

## 0. Pick your tools

Check what is available and tell the user in one line what you will use.

| Task | Preferred | Fallback |
|---|---|---|
| Analysis | `feature-dev:code-explorer` agents in parallel; a code-to-PRD skill if one exists | `Explore` subagents |
| Sharpen the spec | `superpowers:brainstorming` | up to 5 questions to the user |
| Execution later | `superpowers:writing-plans` + `subagent-driven-development`, or GitHub Spec Kit | prompts in the slice files |
| Improve this skill | `skill-creator` | – |

This skill produces the plan; execution happens in a later session in the target repo.

## 1. Inputs (one round, then go)

Repo/path (read only), target stack (default: same stack, current versions), scope, and whether the original runs locally.
Ask all of these in one go. For the target stack offer concrete options (same stack, 2–3 plausible alternatives for this app, other) rather than a bare "different stack", so no second round of questions is needed.
If the user is away or asks for a trial run, make sensible assumptions, mark them `[Assumption]`, and keep going.

## 2. Inventory (fast, before the agents)

```
python3 scripts/inventory.py <repo> > vibe-plan/_inventory.md
```
Lists projects, files and lines per folder, files over 300 lines, test files, and existing documentation.
Make two decisions from it:

- **Is there an existing spec?** (`docs/`, `spec*`, `PRD*`, ADRs, mockups, calibration/domain documents). If so, it is the primary source of intent; code and tests show the actual state. Set a **source precedence** (e.g. domain document > tests > spec > mockup > comments) and record it in the PRD. Contradictions between sources are normal and valuable – collect them, don't smooth them over.
- **Analysis split**: 3–5 areas along layers or projects (e.g. domain + simulation, data/persistence, API/integrations, frontend + infra + tests). Rule of thumb: one agent per ~8–12k lines.

## 3. Analysis → `vibe-plan/analysis.md`

Launch the explorer agents in parallel, one per area, using the template in `references/explorer-prompt.md`. As each one finishes, save its report to `vibe-plan/_raw/<area>.md` (silently – see "Keep the chat clean"). When all are in, merge them into one file with this schema:

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

## 5. Guardrails → `vibe-plan/CLAUDE.md` (for the target repo)

Target architecture with allowed dependency directions – and how it is **enforced** (architecture tests such as NetArchTest/ArchUnit, analyzer rules). Rules that exist only as text don't survive many agent sessions.
Plus: hard rules (file size, single responsibility, constants defined once, no secrets, no new packages without asking), "Forbidden" = legacy findings, exact commands, way of working (plan → failing tests → code, one slice per session, one commit per green slice).

## 6. Slicing → `vibe-plan/slices/NN-name.md`

Vertical and ordered by dependency; slice 00 = scaffold including CI, architecture tests and the parity harness. Sizing: one slice ≈ one agent session (1–2 h), roughly one slice per 1.5–2k lines of the original.
Record the slices as a list in `vibe-plan/_slices.json` and render them:
```
python3 scripts/render_slices.py vibe-plan/_slices.json vibe-plan/slices
```
Each slice has goal, PRD reference, dependencies, scope, a ready-to-run prompt (plan first, then failing tests, then code), a Definition of Done with the concrete parity cases, and non-goals.

## 7. Parity → `vibe-plan/parity/`

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

## 8. Handover

`README.md` with:
- **Assessment: rebuild vs. refactor** – if the original is already well structured and tested, a targeted refactor of the legacy findings is often cheaper; then say which slices would suffice for that.
- File overview, slice dependency graph (what can run in parallel), first steps, intended execution skill.
- `checklist.md` (slice × plan / tests red / green / parity / commit).

Deliver the `vibe-plan/` folder (and a zip of it); the original stays untouched.

## Rules

- Never modify the original; only read it and run parity tests.
- Copy no code – behaviour, data contracts, interfaces and business numbers, yes.
- Never put secrets, connection strings or personal test data into the plan; use placeholders.
- A marked assumption beats a silent invention.

## Output structure

```
vibe-plan/
  README.md  analysis.md  open-questions.md  PRD.md  GLOSSARY.md  CLAUDE.md  checklist.md
  slices/00-scaffold.md … NN-*.md
  parity/README.md  <area>-cases.md …
  _inventory.md  _slices.json  _raw/   (agent reports, working material)
```
