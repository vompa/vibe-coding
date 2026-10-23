# Template: README section "Getting started"

Put this section into the plan's `README.md` in the user's language, after the slice graph. Fill the `<…>` placeholders from the plan – especially the prerequisites (SDKs and tools for the target stack; the original is not needed) and the parallel strands from the slice graph. It must let someone who has never seen the plan start without asking.

```markdown
## Getting started

The whole rebuild runs through one Claude Code command: **`/rebuild`**. It picks the next slice, shows you a plan, builds tests and code after your approval, and ticks the slice off at the end.

### Prerequisites (once)

| What | Why | Check with |
|---|---|---|
| Claude Code | runs `/rebuild` | `claude --version` |
| <target SDK> | builds the rebuild | <command> |
| optional: superpowers plugin | finer plans, one subagent per task, reviews in between | install via `/plugin` in Claude Code; `/rebuild` detects it |

If something is missing, `/rebuild` says exactly what and how to fix it before slice 00. The original app is not needed – everything the rebuild must match is written down in `rebuild/`.

### Each slice

1. **Start Claude Code in the repo folder** – open a terminal there and run `claude`.
2. **Type `/rebuild`.** Claude names the slice that is next and why.
3. **Check the plan.** Claude saves it under `rebuild/plans/` and shows it (files, classes, tests). Approve it ("looks good, go") or say what to change.
4. **Claude builds the slice** – failing tests first, then code until everything is green, including the parity cases from `rebuild/parity/`. Short status lines in between.
5. **Done.** Claude ticks the slice in `rebuild/checklist.md` and ends with three lines: what is done, which slices are ready now, and "start a fresh session, `/rebuild`".
6. **Fresh session** (new terminal or `/clear`), `/rebuild` again – one session per slice keeps the context clean.

### Commands

| Input | What happens |
|---|---|
| `/rebuild` | next open slice whose dependencies are done |
| `/rebuild 07` | exactly slice 07; asks if a dependency is missing |
| `/rebuild status` | overview: done, in progress, ready, blocked |
| `/rebuild 07 direct` | without superpowers, even if it is installed |

### Working in parallel

<strands from the slice graph that can run side by side>. Open one terminal per strand and type `/rebuild` with the slice number, e.g. `/rebuild <NN>` and `/rebuild <MM>`. Each slice works on its own branch.

### When something goes wrong

- **Tests stay red** – the slice is not ticked; fresh session, `/rebuild NN`, Claude resumes on the existing branch and plan.
- **A parity case fails** – Claude records it in `rebuild/parity/deviations.md` (bug in the rebuild or deliberate deviation with reason).
- **An open domain question** – it is in `rebuild/open-questions.md`; answer Claude directly, the decision goes into the plan and spec.
- **Where am I?** – `/rebuild status`.

### Where things are

| Folder/file | Contents |
|---|---|
| `CLAUDE.md` | rules for Claude: architecture, hard rules, commands (loaded automatically) |
| `.claude/commands/rebuild.md` | the `/rebuild` command |
| `rebuild/slices/` | one file per slice: goal, scope, Definition of Done |
| `rebuild/plans/` | the detailed plans each `/rebuild` creates |
| `rebuild/checklist.md` | progress |
| `rebuild/PRD.md`, `rebuild/GLOSSARY.md` | intended behaviour, binding terms |
| `rebuild/research.md` | technical decisions with sources |
| `rebuild/parity/` | expected behaviour taken from the original (cases with exact values), deviation log |
| `src/`, `tests/` | the new code (from slice 00 on) |
```
