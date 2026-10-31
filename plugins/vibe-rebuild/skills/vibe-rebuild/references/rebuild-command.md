# Template: the `/rebuild` command

Write this file unchanged to `.claude/commands/rebuild.md` in the target repo. It is project-independent: everything slice-specific comes from `rebuild/slices/NN-*.md`, `rebuild/_slices.json` and `rebuild/checklist.md`, so the command never needs editing when the plan changes.

The words `plan` and `auto` are used by `.claude/scripts/rebuild-loop.*` (`assets/rebuild-loop.*`), which runs each slice in a fresh headless session: first `/rebuild NN plan auto`, then – after the user approved – a resumed session that builds and closes the slice. The marker lines (`PLAN:`, `NEEDS-DECISION:`, `SLICE-DONE:`, `SLICE-OPEN:`, `ALL-DONE`) are what the script reads; keep them exactly as written.

````markdown
---
description: Rebuild slice by slice – next slice, a given slice, or status
argument-hint: "[status | NN] [plan] [auto] [direct]"
---
You drive the rebuild described in this repo. Arguments: "$ARGUMENTS".
Answer the user in the language of rebuild/README or README.md.
"auto" means a script drives this session headless: nobody can answer questions mid-run.
Never stop to ask in auto mode – decide on the documented default, or end with the marker
lines below so the script can ask the user.

## 1. Decide what to do
- "status" → read rebuild/checklist.md, rebuild/_slices.json and the git branches named slice-*.
  Show one table: slice, name, state (done / in progress / ready / blocked by …),
  then one line "Ready next: …". Stop there.
- a two-digit number NN → work on slice NN. If a slice it depends on (field "deps" in
  rebuild/_slices.json) is not ticked in rebuild/checklist.md, say which one and ask before going on
  (auto: print "SLICE-OPEN: NN blocked by <deps>" and stop).
- nothing → pick the lowest-numbered slice that is not ticked and whose dependencies are all ticked.
  Say which one you picked and why, then go on.
- every slice ticked → say "All slices done", print "ALL-DONE", and offer one next step: turn the plan
  README into the product README (origin with full link to the original, what was built, how it was
  built with the plan and /rebuild, build/test/run/publish commands; plan documents stay in rebuild/).
  Do it only after a yes. Stop there.
- Before slice 00: check the prerequisites listed in README.md ("Voraussetzungen" / "Prerequisites").
  If one is missing (SDK, tool), say exactly what is missing and how to fix it, then stop.
  If the highest goal contract in rebuild/goal/ is not "Status: APPROVED", show its summary (intent,
  MUST criteria, invariants, non-goals, open points) and ask me to approve that version by changing its
  status line to "Status: APPROVED – User, <date>" myself – the goal guard stops agents from doing it
  (auto: plan as usual and add "NEEDS-DECISION: goal contract <file> is not approved – set its status
  line yourself, then answer"). Do not build any slice while it is unapproved.

## 2. Read before planning
- rebuild/goal/ – the highest approved contract version (read-only) and change-requests.md;
  the criteria named under "Goal criteria" in the slice file are what this slice must prove
- rebuild/slices/NN-*.md – goal, scope, PRD reference, parity cases, Definition of Done, non-goals
- CLAUDE.md – architecture, hard rules, commands, way of working
- rebuild/PRD.md – the sections named in the slice file
- rebuild/research.md – the technical decisions, especially those the slice file cites,
  and "Findings per slice" from earlier slices
- rebuild/parity/ – the cases named in the slice file, plus README.md (harness, normalization)
- rebuild/GLOSSARY.md – use only these terms

## 3. Build the slice
If the superpowers skills are available and "direct" is not in the arguments:
1. superpowers:using-git-worktrees – worktree on a new branch "slice-NN"
2. superpowers:writing-plans – save the plan as rebuild/plans/<YYYY-MM-DD>-slice-NN.md with a section
   "Assumptions (confirm on approval)", "Goal criteria and how each is proven" and a "Review focus",
   review it, and show it to me before writing any code
3. after my approval: `python3 .claude/scripts/evidence.py start NN`, then
   superpowers:subagent-driven-development – tests first (red, logged with `evidence.py run NN red -- <test>`),
   then the minimum to get green, every rule in CLAUDE.md; task commits on slice-NN are fine
4. superpowers:finishing-a-development-branch – integrate as ONE squash commit on main
   (`git merge --squash slice-NN`); never push. In auto mode take this option without asking,
   then remove the worktree and the branch.

Otherwise (no superpowers, or "direct"):
1. new branch "slice-NN"
2. follow the prompt in the slice file: present the plan (files, classes, tests, assumptions,
   goal criteria and how each is proven, review focus), save it as
   rebuild/plans/<YYYY-MM-DD>-slice-NN.md and wait for my approval
3. `python3 .claude/scripts/evidence.py start NN`; failing tests first (red run logged with
   `evidence.py run NN red -- <test>`), then the minimum to get green, then refactor
4. one squash commit for the green slice on main; never push

"plan" in the arguments → stop right after the plan is saved and shown. End with the line
"PLAN: <path of the plan file>", plus one line "NEEDS-DECISION: <question>" for each point that
changes architecture, scope, cost or licences and that the plan cannot settle by an assumption.
The approval (or a change request) arrives as the next message in this same session.

Keep me posted: one short status line at least every few minutes (what finished, what runs next).

## 4. Close the slice
Done is what is evidenced, not what is claimed – never report a criterion or the slice as met on your own word.
1. Full suite through the evidence script: `evidence.py run NN suite -- <test command>`; each goal criterion
   of the slice: `evidence.py run NN ac:<id> -- <check>` (or `add NN ac:<id> --sha <commit>`, or
   `--waived "<reason>"` when a parity case or another node already proves it – say which).
2. Cold review: start a fresh subagent that did not build this slice and has not seen its plan. Give it
   only the goal contract, the slice file, the slice's changes (`git diff main...slice-NN`, or
   `git show HEAD` when the squash commit is already on main) and the evidence logs. It writes
   rebuild/evidence/NN/review.md: per goal criterion one line "AC-xx: PASS|FAIL|UNVERIFIED – <evidence>",
   findings with origin (this slice / pre-existing / unclear), one line on drift ("does the result still
   serve the verbatim intent, not just the tests?"), and as its last line "verdict=pass" or
   "verdict=fail". Register it: `evidence.py add NN review --file rebuild/evidence/NN/review.md`.
   Fix and review again on fail – at most 3 review rounds; after the third, stop and rethink the
   approach with me (auto: "SLICE-OPEN: NN review cap reached").
3. `evidence.py check NN` must print "EVIDENCE OK: NN". If it prints NOT DONE, run the calls it names.
   A criterion that turns out unreachable or wrong: append a change request to
   rebuild/goal/change-requests.md and ask me (auto: "SLICE-OPEN: NN goal change request <id>"); never
   weaken the test or touch the contract.
4. Check the Definition of Done in the slice file, record deviations from the plan at the top of the
   plan file, deviations from the original in rebuild/parity/deviations.md, and what the docs did not
   say under "Findings per slice" in rebuild/research.md. Decisions are recorded as "User, <date>" –
   no personal names, no absolute paths, user or machine names in any file. Commit
   rebuild/evidence/NN.json and the review report with the slice.
5. Only after "EVIDENCE OK: NN": tick the slice in rebuild/checklist.md (replace ☐ by ☑ in its row).
End with exactly three lines:
- "Slice NN done" (or what is still open and why)
- "Ready next: …" (e.g. "07, 08, 09 – can run in parallel in separate sessions")
- "Next step: start a fresh session and type /rebuild"
  (auto: instead "SLICE-DONE: NN" when everything is green and ticked, else "SLICE-OPEN: NN <reason>")
````
