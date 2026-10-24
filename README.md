# vibe-rebuild

**Existing app → plan to rebuild it better with vibe coding – same or new stack, nothing users rely on gets lost.**

An [Agent Skill](https://agentskills.io) and Claude Code plugin. It reads an existing codebase and produces everything a coding agent (Claude Code or similar) needs to rebuild the app slice by slice. Not a copy: the original is the template, the target-stack research shows how to build it better today, and acceptance cases make sure business behaviour and the contracts others depend on survive.

## What you get

By default the plan is committed as a local git repo (full path asked and shown), with GitHub as fallback and a folder/zip only if you want neither. The repo becomes the target repo of the rebuild: `CLAUDE.md` at the root, all plan documents in `rebuild/`, code follows in `src/` and `tests/`.

```
.claude/commands/rebuild.md   one command to run the rebuild slice by slice
.claude/scripts/rebuild-loop.*  runs all slices one after another in fresh sessions
CLAUDE.md            guardrails for the target repo (architecture, hard rules, commands)
README.md            origin, rebuild-vs-refactor assessment, slice graph, step-by-step getting started
rebuild/
  analysis.md        stack, domain, features, interfaces, tests, legacy findings
  research.md        current best practice for the target stack, with sources and decisions
  open-questions.md  open questions with marked assumptions
  PRD.md             behaviour from the user's view with Given/When/Then, improvements on purpose
  GLOSSARY.md        binding terminology
  slices/NN-*.md     per slice: goal, scope, ready-to-run prompt, Definition of Done
  parity/            what must survive: cases with exact expected values, deviation log
  plans/             detailed per-slice plans, created while building
  checklist.md       progress per slice
  slice-graph.*      dependency graph (Mermaid + images)
```

The plan is self-contained: once it is written, neither you nor the coding agent needs the original's code or a running original.

## How it works

1. **Inventory** via script: projects, lines per folder, files > 300 lines, existing spec/docs.
2. **Analysis** with parallel explorer agents (preferably `feature-dev:code-explorer`), a fixed schema, and a spot-check of the numbers against the code.
3. **PRD and glossary** – behaviour from the user's view; existing specifications are the primary source, legacy findings become "improvements on purpose".
4. **Target-stack research** in three short passes – broad, deep, distill – with the goal stated openly, distilled into sourced decisions; architecture-relevant ones go to you before slicing. It checks the licence and terms of every recommended package (some break the build until a sponsorship declaration is made) and, when the target SDK is available, runs a short **probe** of the risky paths – transport, packaging, start-up, logging – because reading alone rarely finds the pitfalls.
5. **CLAUDE.md guardrails** built on those decisions: one architecture test per dependency rule, every quality gate proven to turn red on a deliberate violation in slice 00, approved packages listed with their licence.
6. **Slicing** into vertical, dependency-ordered slices (one agent session each), slice prompts in the plan's language.
7. **Parity** – not a copy, a safety net: the business contract and the interface contract external callers depend on are kept and checked; wording, structure and anything implementation-bound may improve. Every case carries exact expected values from the original's tests and code.
8. **Handover** – the plan as a git repo (written directly in Claude Code on your machine, via the device shell from a cloud session), a README with the origin of the rebuild and a getting-started section anyone can follow, the slice graph sized for document and side panel, the `/rebuild` command and the `rebuild-loop` scripts. No absolute paths, user or machine names or personal names end up in the files, and the commit identity is checked before the first commit – the plan repo is often pushed later.

Long steps are announced, status lines start with an overall percentage, and there is no silent stretch longer than a few minutes.

## After the plan: `/rebuild`

Open a terminal in the plan repo, run `claude`, type `/rebuild`:

| Input | What happens |
|---|---|
| `/rebuild` | picks the next slice whose dependencies are done, shows a plan, builds after your approval (tests first) |
| `/rebuild 07` | exactly slice 07 |
| `/rebuild status` | done, in progress, ready, blocked |
| `/rebuild 07 direct` | without superpowers, even if it is installed |

If the [superpowers](https://github.com/obra/superpowers) plugin is installed, `/rebuild` uses it automatically (worktree, `writing-plans`, `subagent-driven-development`); otherwise it follows the slice prompt. The skill never installs plugins.

Each slice ends the same way: the plan lists its assumptions for you to confirm, tests come first, deviations and undocumented findings are written down in fixed places, and the slice lands as **one squash commit on `main`** (task commits stay on the branch `slice-NN`). Nothing is pushed. When every slice is done, `/rebuild` offers to turn the plan README into the product README.

### Hands-off: all slices in one go

Typing `/rebuild` in a fresh session after every slice is the safe default – each slice gets a clean context. The plan repo also ships a loop script that does exactly that for you:

```bash
pwsh .claude/scripts/rebuild-loop.ps1     # Windows, macOS, Linux (PowerShell 7)
bash .claude/scripts/rebuild-loop.sh      # macOS, Linux, Git Bash
```

How it works:

1. The script picks the next ready slice from `rebuild/_slices.json` and `rebuild/checklist.md`.
2. It starts a **fresh headless Claude session** for that slice (`claude -p --session-id …`) that reads the plan, writes the slice plan and stops.
3. You see the plan's path and any open decisions: **Enter** approves, **text** sends a change request and gets a revised plan, **`q`** stops.
4. After approval the **same session** (`--resume`) builds the slice, runs the tests and closes it.
5. The script checks that the slice is really ticked, then moves on – until every slice is done.

| Option (PowerShell / bash) | Effect |
|---|---|
| *(none)* | asks for every plan |
| `-Yes` / `--yes` | approves plans automatically; still stops when a plan reports an open decision (`NEEDS-DECISION`), a slice stays red, or a slice reports done without being ticked |
| `-Parallel` / `--parallel` | builds slices that are ready at the same time side by side, each in its own worktree (experimental) |
| `-DryRun` / `--dry-run` | only lists the slices that are ready now |

Good to know:

- Headless sessions can't answer permission prompts, so they run with `--permission-mode auto`; set `REBUILD_PERMISSION_MODE` to choose another mode.
- Logs per slice go to `.rebuild-loop/` in the repo, which the script keeps out of git.
- Approvals need a terminal. Without one (e.g. in CI) the script stops instead of approving silently.
- The script never pushes and never installs anything.
- Under the hood `/rebuild` prints marker lines the script reads (`PLAN:`, `NEEDS-DECISION:`, `SLICE-DONE:`, `SLICE-OPEN:`, `ALL-DONE`); `/rebuild NN plan auto` is what the script sends.

The plan is written in your language (English by default).

## Installation

**Claude Code**
```bash
claude plugin marketplace add vompa/vibe-coding
claude plugin install vibe-rebuild@vompa
```
or inside a session: `/plugin install vibe-rebuild --marketplace vompa/vibe-coding`

**Claude.ai / other agents:** upload the `plugins/vibe-rebuild/skills/vibe-rebuild/` folder as a skill, or copy it into the agent's skills directory.

## Usage

Just describe what you want – the skill triggers on its own, for example:

- "Analyze `github.com/acme/billing` and plan a rewrite in Go with Claude Code."
- "Our WebForms inventory app should move to .NET 10 + Blazor – make a plan the agent can work through, nothing our users rely on may get lost."
- "Derive a spec and a refactoring order for the AI from our Spring monolith."

Explicitly: `/vibe-rebuild:vibe-rebuild <repo or path>`

## Quality

- **End-to-end reference: [mcp-time-net](https://github.com/vompa/mcp-time-net).** The official MCP [`time` server](https://github.com/modelcontextprotocol/servers/tree/51b6382/src/time) (~310 lines Python) rebuilt on .NET 10 with vibe-rebuild 2.2.0 – the plan and then all 5 slices via `/rebuild` with superpowers, one squash commit per slice. Result: 44 parity cases with exact values green, 202 tests, every deviation from the original logged as an improvement on purpose. Its README walks through both phases step by step; the git history shows the plan commit followed by one commit per slice.
- Trigger test (`tests/trigger-eval.json`, 10 positive and 10 near-miss negative requests in English and German, 3 runs each): **20/20**, no false triggers.
  ```bash
  python3 tests/trigger_check.py tests/trigger-eval.json --runs 3
  ```
- Loop test (`tests/rebuild_loop_test.py`): both `rebuild-loop` scripts against a fake `claude` CLI – auto approval, parallel slices, red slice, open decision, no terminal, all done; runs in CI on every push.

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
