# Slice 03 – SLICE-READY marker and the parallel argument

**Goal:** In auto and parallel runs /slice stops before the squash: it commits the finished branch, leaves the Commit column open, writes the squash message to a file and ends with SLICE-READY: NN, so one merge queue in the main checkout does every squash.
**Round:** R01
**Source:** R01 – F-01 (marker), F-08
**Depends on:** 02
**Model:** sonnet

## Scope
- references/slice-command.md front matter: the argument `parallel` – hint `[status | NN | close] [plan] [auto | parallel] [direct]`
- Section 4: with `auto` or `parallel`, after the task commit of step 5 the session writes the squash message (commit language and style of work/conventions.md, slice and ids) to `.slice-loop/slice-NN.msg` in the main checkout (the parent of `git rev-parse --git-common-dir`), does not merge, leaves Commit at ☐ and ends with `SLICE-READY: NN`; without both arguments it squashes itself as before and ends with the three closing lines
- Section 6: the marker `SLICE-READY: NN` – branch committed, checklist ticked through Checks, squash message written; waits for the merge queue
- Section 7: parallel prompts carry `/slice NN parallel` and say that the squash happens in the main checkout through the merge queue (`slice-loop --merge`, slice 05) or the running loop
- Section 1 `status`: a branch slice-NN whose checklist row is ticked through Checks shows the state 'ready to merge'
- tests/markers_test.py: `SLICE-READY:` in MARKERS, the new argument hint, the message file, the section 7 wording – written first

## Patterns to mirror
- plugins/vibe-coding/skills/vibe-coding/references/slice-command.md:154 – the marker list the new marker joins
- plugins/vibe-coding/skills/vibe-coding/references/slice-command.md:165 – the parallel prompts that change
- tests/markers_test.py:7 – the MARKERS list and the argument-hint assertion

## NOT building
- Reading the marker in the loop scripts (slice 05)
- Changes to the slice-board plugin (open decision)
- Removing SLICE-DONE: the loop keeps accepting it

## Prompt
```
Read CLAUDE.md, work/conventions.md, the round record work/rounds/R01-*.md and this slice file.
Implement slice 03 "SLICE-READY marker and the parallel argument" (this file).
1. First present a plan (files, classes, tests) with a section "Assumptions (confirm on approval)"
   for every open point and a short "Review focus", save it under work/plans/,
   and wait for approval.
2. Write this slice's acceptance tests as failing tests (RED).
3. Implement the minimum to get green. Follow every rule in CLAUDE.md and work/conventions.md.
4. Check the Definition of Done. Record decisions, surprises and deferred minors in the round
   record and in the protocol file that work/conventions.md names.
```

## Definition of Done
- [ ] Checks from work/conventions.md green
- [ ] No test weakened or skipped
- [ ] No new packages without approval
- [ ] Decisions recorded
- [ ] Given the front matter When read Then the argument hint is exactly `[status | NN | close] [plan] [auto | parallel] [direct]` and tests/markers_test.py asserts it
- [ ] Given a run with `auto` or `parallel` When section 4 is read Then after step 5 it writes `.slice-loop/slice-NN.msg` in the main checkout, never merges, leaves Commit at ☐ and ends with `SLICE-READY: NN` as the last line; a run with neither argument still squashes itself and ends with the three closing lines
- [ ] Given section 6 When read Then `SLICE-READY: NN` is listed with 'branch committed, checklist ticked through Checks, squash message written; waits for the merge queue'
- [ ] Given section 7 When read Then every parallel prompt starts with `/slice NN parallel` and names the merge queue in the main checkout
- [ ] Given `/slice status` When a branch slice-NN exists whose row has every tick but Commit Then the state column says 'ready to merge'
- [ ] Given the unchanged command When the new tests run Then they fail; afterwards `python tests/markers_test.py` passes and `python tests/loop_test.py` passes unchanged
- [ ] Manual: Run `/slice NN parallel` in a scratch repository with the copied command: the session ends with SLICE-READY, the branch slice-NN and the message file exist, the integration branch did not move

## Non-goals
The merge queue itself (slice 05)
