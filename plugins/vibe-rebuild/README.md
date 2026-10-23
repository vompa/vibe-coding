# Vibe Rebuild

**Existing app → rebuild plan for vibe coding, with parity tests against the original.**

Point Claude at an existing codebase and get everything a coding agent needs to rebuild it slice by slice – and to prove the rebuild behaves like the original.

## What you get

A `vibe-plan/` folder with:

- **analysis.md** – stack, domain, features, interfaces, existing tests, legacy findings
- **research.md** – current best practice for the target stack, with sources and the decisions drawn from it
- **PRD.md** and **GLOSSARY.md** – behaviour from the user's view with Given/When/Then acceptance criteria and binding terminology
- **CLAUDE.md** – guardrails for the target repo: architecture with enforced dependency rules, hard rules, exact commands
- **slices/** – vertical, dependency-ordered slices, each with a ready-to-run prompt and a Definition of Done
- **parity/** – business and interface contracts drawn from the original's tests, plus a recording plan
- **open-questions.md**, **checklist.md**, and a rebuild-vs-refactor assessment

## How to use it

Just describe what you want, for example:

- "Analyze github.com/acme/billing and plan a rewrite in Go with Claude Code."
- "Our WebForms inventory app should move to .NET 10 + Blazor – make a plan the agent can work through and keep parity."
- "Derive a spec and a refactoring order for the AI from our Spring monolith."

The skill triggers on its own; you can also call it as `/vibe-rebuild:vibe-rebuild <repo or path>`. The plan is written in your language.

## How it works

1. Quick inventory of the codebase (projects, sizes, oversized files, existing docs).
2. Parallel analysis by explorer subagents into a fixed schema, with numbers spot-checked against the code.
3. PRD and glossary – existing specs are treated as the primary source of intent.
4. Target-stack research: broad first, then deep, distilled into sourced decisions.
5. CLAUDE.md guardrails built on those decisions.
6. Slicing into one-session work packages.
7. Parity cases sorted into business contract, interface contract and implementation-bound (not carried over).

Works best with Claude Code and subagents; pairs well with superpowers or GitHub Spec Kit for executing the plan.

## Privacy

No data collection, no network access of its own, no credentials – see [PRIVACY.md](PRIVACY.md).

## License

MIT – see [LICENSE](LICENSE). Source and issues: https://github.com/vompa/vibe-rebuild
