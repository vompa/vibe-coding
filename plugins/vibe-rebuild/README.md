# Vibe Rebuild

**Existing app → plan to rebuild it better with vibe coding – same or new stack, nothing users rely on gets lost.**

Point Claude at an existing codebase and get everything a coding agent needs to rebuild it better, slice by slice – keeping the behaviour and contracts users rely on, improving the rest based on current best practice.

## What you get

A git repo (or, if you prefer, a folder and zip) that becomes the target repo of the rebuild, with:

- **analysis.md** – stack, domain, features, interfaces, existing tests, legacy findings
- **research.md** – current best practice for the target stack, with sources and the decisions drawn from it
- **PRD.md** and **GLOSSARY.md** – behaviour from the user's view with Given/When/Then acceptance criteria, improvements on purpose, and binding terminology
- **CLAUDE.md** – guardrails for the target repo: architecture with enforced dependency rules, hard rules, exact commands
- **slices/** – vertical, dependency-ordered slices, each with a ready-to-run prompt and a Definition of Done
- **parity/** – what must survive the rebuild: cases with exact expected values from the original's tests and code, plus a deviation log
- **open-questions.md**, **checklist.md**, a slice graph, and a rebuild-vs-refactor assessment
- **README** with a step-by-step getting-started section anyone can follow
- **`/rebuild`** – one Claude Code command that runs the plan slice by slice (`/rebuild`, `/rebuild 07`, `/rebuild status`), using superpowers if you have it installed

## How to use it

Just describe what you want, for example:

- "Analyze github.com/acme/billing and plan a rewrite in Go with Claude Code."
- "Our WebForms inventory app should move to .NET 10 + Blazor – make a plan the agent can work through, nothing our users rely on may get lost."
- "Derive a spec and a refactoring order for the AI from our Spring monolith."

The skill triggers on its own; you can also call it as `/vibe-rebuild:vibe-rebuild <repo or path>`. The plan is written in your language.

## How it works

1. Quick inventory of the codebase (projects, sizes, oversized files, existing docs).
2. Parallel analysis by explorer subagents into a fixed schema, with numbers spot-checked against the code.
3. PRD and glossary – existing specs are the primary source of intent; legacy findings become improvements on purpose.
4. Target-stack research in three short passes (broad, deep, distill), distilled into sourced decisions.
5. CLAUDE.md guardrails built on those decisions.
6. Slicing into one-session work packages, prompts in your language.
7. Parity cases: business and interface contracts are kept, the rest may improve – no original needed afterwards.
8. Handover as a git repo with `/rebuild`: open a terminal there, run `claude`, type `/rebuild`.

Status lines show an overall percentage, so you always see that the run is moving. Works best with Claude Code and subagents; uses superpowers for execution if you have it installed.

## Privacy

No data collection, no network access of its own, no credentials – see [PRIVACY.md](PRIVACY.md).

## License

MIT – see [LICENSE](LICENSE). Source and issues: https://github.com/vompa/vibe-rebuild
