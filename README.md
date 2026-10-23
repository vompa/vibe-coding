# vibe-rebuild

**Existing app → plan to rebuild it better with vibe coding – same or new stack, nothing users rely on gets lost.**

An [Agent Skill](https://agentskills.io) and Claude Code plugin. It reads an existing codebase and produces everything a coding agent (Claude Code or similar) needs to rebuild the app slice by slice. Not a copy: the original is the template, the target-stack research shows how to build it better today, and acceptance cases make sure business behaviour and the contracts others depend on survive.

## What you get

By default the plan is committed as a local git repo (full path asked and shown), with GitHub as fallback and a folder/zip only if you want neither. The repo becomes the target repo of the rebuild: `CLAUDE.md` at the root, all plan documents in `rebuild/`, code follows in `src/` and `tests/`.

```
.claude/commands/rebuild.md   one command to run the rebuild slice by slice
CLAUDE.md            guardrails for the target repo (architecture, hard rules, commands)
README.md            rebuild-vs-refactor assessment, slice graph, step-by-step getting started
rebuild/
  analysis.md        stack, domain, features, interfaces, tests, legacy findings
  research.md        current best practice for the target stack, with sources and decisions
  open-questions.md  open questions with marked assumptions
  PRD.md             behaviour from the user's view with Given/When/Then
  GLOSSARY.md        binding terminology
  slices/NN-*.md     per slice: goal, scope, ready-to-run prompt, Definition of Done
  parity/            business contract, interface contract, recording plan
  plans/             detailed per-slice plans (e.g. from superpowers)
  checklist.md
```

## How it works

1. **Inventory** via script: projects, lines per folder, files > 300 lines, existing spec/docs.
2. **Analysis** with 3–5 parallel explorer agents (preferably `feature-dev:code-explorer`), a fixed schema, and a spot-check of the numbers against the code.
3. **PRD and glossary** – existing specifications are used as the primary source, with a source precedence for contradictions.
4. **Target-stack research** – goal stated openly, broad first, then deep; distilled into sourced decisions that drive `CLAUDE.md` and the slices instead of training-data defaults.
5. **CLAUDE.md guardrails** with enforced architecture rules.
6. **Slicing** into vertical, dependency-ordered slices (one agent session each).
7. **Parity** in three kinds: business and interface contracts are checked strictly; implementation-bound checksums are not carried over. LLM parts only with a fake model.

For executing the plan afterwards, [superpowers](https://github.com/obra/superpowers) (`writing-plans` → `subagent-driven-development`) or GitHub Spec Kit work well.

The plan is written in the user's language (English by default).

## Installation

**Claude Code**
```bash
claude plugin marketplace add vompa/vibe-rebuild
claude plugin install vibe-rebuild@vompa
```
or inside a session: `/plugin install vibe-rebuild --marketplace vompa/vibe-rebuild`

**Claude.ai / other agents:** upload the `plugins/vibe-rebuild/skills/vibe-rebuild/` folder as a skill, or copy it into the agent's skills directory.

## Usage

Just describe what you want – the skill triggers on its own, for example:

- "Analyze `github.com/acme/billing` and plan a rewrite in Go with Claude Code."
- "Our WebForms inventory app should move to .NET 10 + Blazor – make a plan the agent can work through and make sure we keep parity."
- "Derive a spec and a refactoring order for the AI from our Spring monolith."

Explicitly: `/vibe-rebuild:vibe-rebuild <repo or path>`

## Quality

- Tried on a real project ([OPCAgentSample](https://github.com/vompa/OPCAgentSample), ~37k lines of .NET/Vue): 22 slices, parity cases drawn from 700+ existing tests.
- Trigger test (`tests/trigger-eval.json`, 10 positive and 10 near-miss negative requests in English and German, 3 runs each): **20/20**, no false triggers.
  ```bash
  python3 tests/trigger_check.py tests/trigger-eval.json --runs 3
  ```

## Development

Repository layout: the shipped plugin lives in `plugins/vibe-rebuild/` (what the directory and installs see); `tests/` and CI stay outside the plugin.

```bash
claude plugin validate --strict .                      # marketplace
claude plugin validate --strict plugins/vibe-rebuild   # plugin
claude --plugin-dir plugins/vibe-rebuild               # load the plugin for one session
```
New version: bump `version` in `plugins/vibe-rebuild/.claude-plugin/plugin.json` and `metadata.version` in SKILL.md, add a `CHANGELOG.md` entry.

## License

MIT – see [LICENSE](LICENSE).
