# Templates

## PRD.md
```
# PRD – <product name> (rebuild)
> Describes what, not how. Terms: GLOSSARY.md. Source documents that remain valid: <list>.
> On contradictions: <source precedence>.

## Purpose          (2–3 sentences)
## Principles       (P1…Pn – apply to every feature)
## Users            (role | sees/may | typical tasks)
## Features
### F1 <name>
**Story**: As a <role> I want <goal> so that <benefit>.
- AC1 Given … When … Then … (exact numbers where known)
- Edge cases: …
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
## Pitfalls & breaking changes (incl. migration notes from the source stack)
## Decisions for this rebuild (decision | rests on | source)  → feeds CLAUDE.md, slices, README assessment
## Sources
```

## GLOSSARY.md
```
| Term | Code | Meaning |
```

## CLAUDE.md (target repo)
```
# CLAUDE.md – <product> (rebuild)
<purpose in 2–3 sentences>; points to rebuild/PRD.md, rebuild/GLOSSARY.md, rebuild/research.md; goal = all cases in rebuild/parity/ green; improve the rest per rebuild/research.md.

## Architecture     (project/module tree with dependency arrows; how enforced: architecture tests, analyzers)
## Hard rules       (≤300 lines per file, single responsibility, constants once, no secrets,
                     no new packages without asking, business logic in one place, typed errors)
## Forbidden (legacy) (concrete findings from analysis.md)
## Commands         (exactly runnable: build, test, parity, run, lint)
## Way of working   (read slice → plan → failing tests → code → DoD → commit; unclear = ask)
```

## parity/README.md
```
# Parity harness
## Three kinds (business contract – keep | interface contract – keep for compatibility | implementation-bound – may improve)
## From case to test (one acceptance/approval test per case, written from the plan; each test creates its own fixtures)
## Normalization     (ids, tokens, durations, wall-clock timestamps → placeholders)
## Non-deterministic parts (fake model, stubs)
## Deviation log     (deviations.md: case | expected (plan) | rebuild | verdict)
```

## _slices.json (input for scripts/render_slices.py)
```json
[
  {
    "nr": "00", "slug": "scaffold", "name": "Scaffold",
    "goal": "Runnable empty solution with all quality gates and the parity harness.",
    "prd": "Principles, CLAUDE.md", "deps": "–",
    "scope": ["Solution + projects", "Architecture tests", "CI", "Parity harness"],
    "parity": "Architecture tests green on the empty solution",
    "non_goals": "Business logic"
  }
]
```
