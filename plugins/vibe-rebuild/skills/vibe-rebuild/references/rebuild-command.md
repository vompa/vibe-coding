# Template: the `/rebuild` command

Write this file unchanged to `.claude/commands/rebuild.md` in the target repo. It is project-independent: everything slice-specific comes from `rebuild/slices/NN-*.md`, `rebuild/_slices.json` and `rebuild/checklist.md`, so the command never needs editing when the plan changes.

````markdown
---
description: Rebuild Slice für Slice – nächste Slice, bestimmte Slice oder Status
argument-hint: "[status | NN] [direct]"
---
You drive the rebuild described in this repo. Arguments: "$ARGUMENTS".
Answer the user in the language of rebuild/README or README.md.

## 1. Decide what to do
- "status" → read rebuild/checklist.md, rebuild/_slices.json and the git branches named slice-*.
  Show one table: slice, name, state (done / in progress / ready / blocked by …),
  then one line "Ready next: …". Stop there.
- a two-digit number NN → work on slice NN. If a slice it depends on (field "deps" in
  rebuild/_slices.json) is not ticked in rebuild/checklist.md, say which one and ask before going on.
- nothing → pick the lowest-numbered slice that is not ticked and whose dependencies are all ticked.
  Say which one you picked and why, then go on.
- Before slice 00: check the prerequisites listed in README.md ("Voraussetzungen" / "Prerequisites").
  If one is missing (SDK, built original, its path), say exactly what is missing and how to fix it, then stop.

## 2. Read before planning
- rebuild/slices/NN-*.md – goal, scope, PRD reference, parity cases, Definition of Done, non-goals
- CLAUDE.md – architecture, hard rules, commands, way of working
- rebuild/PRD.md – the sections named in the slice file
- rebuild/research.md – the technical decisions, especially those the slice file cites
- rebuild/parity/ – the cases named in the slice file, plus README.md (harness, normalization)
- rebuild/GLOSSARY.md – use only these terms

## 3. Build the slice
If the superpowers skills are available and "direct" is not in the arguments:
1. superpowers:using-git-worktrees – worktree on a new branch "slice-NN"
2. superpowers:writing-plans – save the plan as rebuild/plans/<YYYY-MM-DD>-slice-NN.md,
   review it, and show it to me before writing any code
3. after my approval: superpowers:subagent-driven-development – tests first (red),
   then the minimum to get green, every rule in CLAUDE.md
4. superpowers:finishing-a-development-branch

Otherwise (no superpowers, or "direct"):
1. new branch "slice-NN"
2. follow the prompt in the slice file: present the plan (files, classes, tests),
   save it as rebuild/plans/<YYYY-MM-DD>-slice-NN.md and wait for my approval
3. failing tests first, then the minimum to get green, then refactor
4. one commit for the green slice

Keep me posted: one short status line at least every few minutes (what finished, what runs next).

## 4. Close the slice
Run the full test suite, check the Definition of Done in the slice file, record deviations
in rebuild/parity/deviations.md, tick the slice in rebuild/checklist.md.
End with exactly three lines:
- "Slice NN done" (or what is still open and why)
- "Ready next: …" (e.g. "07, 08, 09 – can run in parallel in separate sessions")
- "Next step: start a fresh session and type /rebuild"
````
