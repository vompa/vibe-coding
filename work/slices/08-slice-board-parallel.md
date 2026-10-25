# Slice 08 – slice-board starts sessions with /slice NN parallel

**Goal:** Sessions started from the slice-board pane end with SLICE-READY instead of squashing themselves, so the merge queue in the main checkout does every squash of a parallel round.
**Round:** R01
**Source:** R01 – F-01 (parallel sessions from the pane); Ruling of 2026-10-25
**Depends on:** 03
**Model:** sonnet

## Scope
- plugins/slice-board/hooks/register.tsx, requestStart: the request briefs each session with `/slice NN parallel`, and its rules sentence says the session ends with `SLICE-READY: NN` and that the squash happens through the merge queue in the main checkout (`slice-loop --merge`, or the running loop), never in the session itself
- plugins/slice-board/hooks/register.test.tsx: the Start test asserts `/slice NN parallel`, `SLICE-READY` and `slice-loop --merge` in the prompt-box text – written first
- plugins/slice-board/README.md: the Ready paragraph names `/slice NN parallel` and the merge queue

## Patterns to mirror
- plugins/slice-board/hooks/register.tsx:262 – requestStart, the text the pane writes into the prompt box
- plugins/slice-board/hooks/register.test.tsx:139 – the Start test that reads the prompt box

## NOT building
- A pane state for slices that await the merge queue
- Starting the merge queue from the pane
- Changes to vibe-coding files (slices 01–07)

## Prompt
```
Read CLAUDE.md, work/conventions.md, the round record work/rounds/R01-*.md and this slice file.
Implement slice 08 "slice-board starts sessions with /slice NN parallel" (this file).
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
- [ ] Given the pane's Start When the request lands in the prompt box Then it briefs each session with `/slice NN parallel` and says the squash happens through the merge queue in the main checkout (`slice-loop --merge` or the running loop), and register.test.tsx asserts both
- [ ] Given the unchanged register.tsx When `claude plugin test plugins/slice-board` runs with the new assertions Then the Start test fails; afterwards every slice-board test passes and `claude plugin validate plugins/slice-board` is green
- [ ] Given plugins/slice-board/README.md When the Ready paragraph is read Then it names `/slice NN parallel` and the merge queue
- [ ] Manual: Open the pane in a repository with an open round and two ready slices, press Start: the prompt-box text carries `/slice NN parallel` for each slice and names the merge queue

## Non-goals
The pane's state model; the vibe-coding command and scripts
