# Templates

## PRD.md
```
# PRD – <product name> (rebuild)
> Describes what, not how. Terms: GLOSSARY.md. Goal: rebuild/goal/contract-v001.md (wins over this file).
> Source documents that remain valid: <list>.
> On contradictions: <source precedence>.

## Purpose          (2–3 sentences)
## Principles       (P1…Pn – apply to every feature)
## Users            (role | sees/may | typical tasks)
## Features
### F1 <name>
**Goal IDs**: REQ-.., AC-.., INV-..   (from the goal contract; none → ask, don't invent)
**Story**: As a <role> I want <goal> so that <benefit>.
- AC1 Given … When … Then … (exact numbers where known)
- Edge cases: …  (for every input, new ones above all: range limits and overflow at both ends,
  wrong type (number/bool/object instead of text), missing vs. null vs. empty, whitespace and
  control characters, several invalid inputs at once – which error wins)
- Errors: …
## API (contract)   (routes/operations in short, error format)
## Improvements on purpose   (from legacy findings and research, each with reason; may deviate from the original)
## Non-goals
```

## research.md
```
# Target-stack research – <product> on <target stack>
> Goal stated openly; topics below were collected broad-first, then deepened.
## Goal & scope
## Versions & support         (version | support until | source)
## Findings by topic          (one subsection per topic; sources inline)
## Licences & terms         (package | licence | paid tiers / build-enforced declarations | source)
## Pitfalls & breaking changes (incl. migration notes from the source stack; [Probed] = seen in the probe)
## Decisions for this rebuild (decision | rests on | source)  → feeds CLAUDE.md, slices, README assessment
## Findings per slice       (filled while building: "### Slice NN" – what the docs did not say, with the fix)
## Sources
```

## GLOSSARY.md
```
| Term | Code | Meaning |
```

## CLAUDE.md (target repo)
```
# CLAUDE.md – <product> (rebuild)
<purpose in 2–3 sentences>; points to rebuild/goal/ (the approved goal contract), rebuild/PRD.md, rebuild/GLOSSARY.md, rebuild/research.md; done = every criterion of the goal contract evidenced and all cases in rebuild/parity/ green; improve the rest per rebuild/research.md.

## Goal contract  (rebuild/goal/contract-vNNN.md, highest approved version)
- read-only for agents – enforced by .claude/hooks/protect-goal.py; never edit, rename or replace it, also not via the shell
- never reinterpret a criterion, lower a threshold or switch a check off; unreachable or wrong →
  append a change request to rebuild/goal/change-requests.md and ask (auto: NEEDS-DECISION)
- AI_PROPOSED / [Assumption] lines are not requirements; work with them, list them in the plan's assumptions
- never report a criterion or the goal as reached – evidence.py and the cold review decide

## Architecture     (project/module tree with dependency arrows; how enforced: one architecture
                     test per rule, listed as rule → test; analyzers; gates proven to turn red)
## Hard rules       (≤300 lines per file, single responsibility, constants once, no secrets,
                     no new packages without asking, business logic in one place, typed errors,
                     no absolute paths / user, machine or personal names in files)
## Approved packages (package | version line | licence)
## Forbidden (legacy) (concrete findings from analysis.md)
## Commands         (exactly runnable: build, test, parity, run, lint/format check, and the evidence calls:
                     evidence.py start NN | run NN red -- <test> | run NN suite -- <test> |
                     run NN ac:AC-xx -- <check> | check NN)
## Way of working   (read slice + goal criteria → plan with assumptions → evidence start → failing tests
                     (red run logged) → code → suite logged → cold review → evidence check → DoD → findings
                     into research.md → task commits on slice-NN → one squash commit on main; unclear = ask)
```

## parity/README.md
```
# Parity harness
## Three kinds (business contract – keep | interface contract – keep for compatibility | implementation-bound – may improve)
## From case to test (one acceptance/approval test per case, written from the plan; each test creates its own fixtures)
## Normalization     (ids, tokens, durations, wall-clock timestamps → placeholders)
## Non-deterministic parts (fake model, stubs)
## Deviation log     (deviations.md: case | expected (plan) | rebuild | verdict – bug in the rebuild, or
                     improvement on purpose with PRD reference and "decided by User, <date>"; no personal names)
```

## _slices.json (input for scripts/render_slices.py)
`acs` (optional, list or comma-separated): the goal-contract criteria this slice must prove; `evidence.py` reads it to know which proofs the slice owes. Every MUST criterion appears in at least one slice.
```json
[
  {
    "nr": "00", "slug": "scaffold", "name": "Scaffold",
    "goal": "Runnable empty solution with all quality gates and the parity harness.",
    "prd": "Principles, CLAUDE.md", "deps": "–", "acs": [],
    "scope": ["Solution + projects", "One architecture test per rule in CLAUDE.md (mapping complete)", "CI incl. format/lint check", "Proof that every quality gate turns red on a deliberate violation, incl. goal guard and evidence gate", "Parity harness", "Probe from research.md if it could not run during planning"],
    "parity": "Architecture tests green on the empty solution; every gate shown red once",
    "non_goals": "Business logic"
  }
]
```
