# Template: prompt for an explorer agent

Launch one agent per analysis area (`feature-dev:code-explorer`, otherwise `Explore`) with this prompt – all in the same turn so they run in parallel. Replace the `<…>` placeholders.

```
Read-only analysis of the repo at <PATH> (do NOT modify anything).
Scope: <folders/projects>, the related tests under <test folder>, plus the sections of <existing spec/docs> that concern this scope.

Goal: extract the INTENT (behaviour, contracts, business numbers), not the implementation,
so a coding agent could rebuild it from scratch. Answer in <user's language>, Markdown,
exactly these headings, only what applies to your scope:

## Stack & runtime       (packages + versions, run/build/test commands, ports, config defaults)
## Domain                (entities, invariants, rules with exact formulas/thresholds; glossary candidates with 1-line definitions)
## Features              (each: purpose, entry point, modules, key behaviour)
## Interfaces            (APIs/routes, protocols, events, storage schema/keys, CLI, config keys – no secret values)
## Non-functional        (security, determinism, performance figures, limits, failure behaviour, telemetry)
## Existing tests        (what each test file pins; which are usable as acceptance criteria / golden master;
                          flag tests tied to implementation details, e.g. checksums over RNG output)
## Legacy findings       (what a rebuild should NOT copy: files >300 lines, mixed responsibilities, duplication,
                          dead/speculative code, spec-vs-code contradictions – each with file path and reason)
## Open questions

Then add "Golden-master candidates": concrete input → observable output pairs, with the exact numbers.
Say explicitly which files you did NOT read. Max ~1000 words.
Start your answer directly with the first heading – no preamble ("I have read …"), no closing remarks.
Your answer is saved to a file by the orchestrator; it is not shown to the end user.
```

## Notes
- Ask for exact numbers (limits, defaults, expected values from tests) – they become acceptance criteria.
- "Which files you did NOT read" matters: gaps end up as open questions instead of silent assumptions in the PRD.
- After merging, spot-check numbers against the code (see SKILL.md §3).
