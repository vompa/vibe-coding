# Vibe Rebuild

**Existing app → plan to rebuild it better with vibe coding – same or new stack, nothing users rely on gets lost.**

Point Claude at an existing codebase and get everything a coding agent needs to rebuild it better, slice by slice – keeping the behaviour and contracts users rely on, improving the rest based on current best practice.

```bash
claude plugin marketplace add vompa/vibe-coding
claude plugin install vibe-rebuild@vompa
```

## What you get

A git repo that becomes the target repo of the rebuild – local by default (the full path is asked and shown), GitHub as fallback, a folder and zip only if you want neither. `CLAUDE.md` and `README.md` sit at its root, all plan documents in `rebuild/`; the code follows in `src/` and `tests/`. It contains:

- **analysis.md** – stack, domain, features, interfaces, existing tests, legacy findings
- **research.md** – current best practice for the target stack, with sources and the decisions drawn from it
- **PRD.md** and **GLOSSARY.md** – behaviour from the user's view with Given/When/Then acceptance criteria, improvements on purpose, and binding terminology
- **CLAUDE.md** – guardrails for the target repo: architecture with enforced dependency rules, hard rules, exact commands
- **slices/** – vertical, dependency-ordered slices, each with a ready-to-run prompt and a Definition of Done
- **parity/** – what must survive the rebuild: cases with exact expected values from the original's tests and code, plus a deviation log
- **open-questions.md**, **checklist.md**, a slice graph (Mermaid plus images, sized for the document and the side panel), and a rebuild-vs-refactor assessment
- **README** with the origin of the rebuild and a step-by-step getting-started section anyone can follow
- **`/rebuild`** – one Claude Code command that runs the plan slice by slice (`/rebuild`, `/rebuild 07`, `/rebuild status`), using superpowers (worktree, `writing-plans`, `subagent-driven-development`) if you have it installed, never installing it for you
- **`rebuild-loop`** – a script (PowerShell and bash) that runs every slice in its own fresh Claude session, stops only for your plan approval and moves on by itself – no typing `/rebuild` after each slice

The plan is self-contained: once it is written, neither you nor the coding agent needs the original's code or a running original.

## How to use it

Just describe what you want, for example:

- "Analyze github.com/acme/billing and plan a rewrite in Go with Claude Code."
- "Our WebForms inventory app should move to .NET 10 + Blazor – make a plan the agent can work through, nothing our users rely on may get lost."
- "Derive a spec and a refactoring order for the AI from our Spring monolith."

The skill triggers on its own; you can also call it as `/vibe-rebuild:vibe-rebuild <repo or path>`. The plan is written in your language.

## How it works

1. Quick inventory of the codebase (projects, sizes, oversized files, existing docs).
2. Parallel analysis by explorer subagents (preferably `feature-dev:code-explorer`) into a fixed schema, with numbers spot-checked against the code.
3. PRD and glossary – existing specs are the primary source of intent; legacy findings become improvements on purpose.
4. Target-stack research in three short passes (broad, deep, distill), distilled into sourced decisions – including the licence of every recommended package and, when the SDK is available, a short probe of transport, packaging and start-up.
5. CLAUDE.md guardrails built on those decisions: one architecture test per rule, every quality gate proven to turn red.
6. Slicing into one-session work packages, prompts in your language; each plan lists its assumptions for you to confirm.
7. Parity cases: business and interface contracts are kept, the rest may improve – no original needed afterwards.
8. Handover as a git repo (written directly in Claude Code on your machine, via the device shell from a cloud session) with `/rebuild` and `rebuild-loop` – no absolute paths, user, machine or personal names in the files, commit identity checked first.

## Running the rebuild

Open a terminal in the plan repo and choose:

- **Step by step:** run `claude`, type `/rebuild` – Claude picks the next slice, shows the plan, builds after your approval, and lands the slice as one squash commit on `main` (task commits stay on the branch `slice-NN`). Fresh session, `/rebuild` again for the next one. `/rebuild 07` builds exactly slice 07, `/rebuild status` shows done, in progress, ready and blocked slices, `/rebuild 07 direct` works without superpowers even if it is installed.
- **Hands-off:** run `pwsh .claude/scripts/rebuild-loop.ps1` (or `bash .claude/scripts/rebuild-loop.sh`). Every slice runs in its own fresh headless session (`claude -p --session-id …`) that writes the slice plan and stops; you approve it with Enter, type a change request, or stop with `q`; the same session (`--resume`) then builds, tests and closes the slice, the script checks that it is really ticked and moves on to the next ready slice until all are done. `-Yes` approves automatically but still stops on open decisions (`NEEDS-DECISION`), red slices and slices reported done without a tick; `-Parallel` builds independent slices side by side, each in its own worktree (experimental); `-DryRun` lists what is ready.

Good to know about the loop: headless sessions can't answer permission prompts, so they run with `--permission-mode auto` (set `REBUILD_PERMISSION_MODE` to choose another); logs per slice go to `.rebuild-loop/`, which the script keeps out of git; approvals need a terminal (without one, e.g. in CI, the script stops instead of approving silently); under the hood `/rebuild` prints marker lines the script reads (`PLAN:`, `NEEDS-DECISION:`, `SLICE-DONE:`, `SLICE-OPEN:`, `ALL-DONE`), and `/rebuild NN plan auto` is what the script sends.

Nothing is pushed, nothing is installed. Each slice ends the same way: the plan lists its assumptions for you to confirm, tests come first, and deviations and undocumented findings are written down in fixed places. When all slices are done, `/rebuild` offers to turn the plan README into the product README.

A complete run – plan, all slices, published result – is in [mcp-time-net](https://github.com/vompa/mcp-time-net).

Long steps are announced and status lines start with an overall percentage, so you always see that the run is moving. Works best with Claude Code and subagents; uses superpowers for execution if you have it installed.

## Privacy

No data collection, no network access of its own, no credentials – see [PRIVACY.md](PRIVACY.md).

## License

MIT – see [LICENSE](LICENSE). Source and issues: https://github.com/vompa/vibe-coding
