# Slice 06 – Rule-based resolution of checklist and round record

**Goal:** Conflicts that parallel slices always produce – in work/checklist.md and the round record – are resolved by rule inside the merge queue; both sides stay complete, no marker survives, and any other conflict still stops the loop with the file names.
**Round:** R01
**Source:** R01 – F-01 (resolution)
**Depends on:** 05
**Model:** opus

## Scope
- Both loop scripts: when every conflicted file is work/checklist.md or the open round record work/rounds/Rnn-*.md, resolve by rule; otherwise reset and stop as in slice 05
- work/checklist.md: start from the integration branch's version; for every row of the branch's version with the same slice number take the union of ticks per column (☑ when either side has it); rows only on one side are kept, new ones appended in the branch's order; then tick Commit for NN
- Round record: for every conflict hunk keep the integration branch's side first and the branch's side after it, drop the three marker lines
- Verification before the commit, both files: no line starts with `<<<<<<<`, `=======` or `>>>>>>>`; every line of `git show HEAD:<file>` and of `git show slice-NN:<file>` occurs in the result; the number of lines starting with `Result:` equals ours plus theirs minus the merge base; a failed check resets the merge and stops with the file name
- tests/loop_test.py: the fake claude appends a Surprises line and a manual-test block with `Result: ☐` to the round record on every build; new cases for parallel builds and for a foreign conflict beside the two round files

## Patterns to mirror
- plugins/vibe-coding/skills/vibe-coding/assets/slice-loop.sh:69 – is_done, how a checklist row is matched by its number
- plugins/vibe-coding/skills/vibe-coding/assets/slice-loop.ps1:49 – Test-Done, the PowerShell twin
- plugins/vibe-coding/skills/vibe-coding/references/slice-command.md section 4 step 6 after slice 01 – the same checklist, applied by hand

## NOT building
- Resolving conflicts in any other file
- Resolving a conflict inside one table row beyond the tick union
- A third runtime: the rules live in each shell

## Prompt
```
Read CLAUDE.md, work/conventions.md, the round record work/rounds/R01-*.md and this slice file.
Implement slice 06 "Rule-based resolution of checklist and round record" (this file).
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
- [ ] Given two ready slices built in parallel (`--yes --parallel`) whose branches tick adjacent rows and append different lines to the round record When the queue squashes both Then both rows are fully ticked, both appended lines are in the record, no marker line exists in either file, and the integration branch has two new commits
- [ ] Given a conflict in work/checklist.md where the integration branch has a new row the branch lacks When resolved Then the row is still there and the branch's row has the union of ticks
- [ ] Given both sides added a manual-test block ending in `Result: ☐` When resolved Then the record has the base count plus two such lines and both blocks are complete
- [ ] Given a conflict in shared.txt beside work/checklist.md When the queue runs Then it stops naming only shared.txt and resolves nothing
- [ ] Given both scripts When `python tests/loop_test.py` runs Then every case passes for bash and pwsh alike; `bash -n`, the PowerShell parse and `python tests/markers_test.py` are green
- [ ] Manual: Reproduce by hand in a scratch repository: two branches that both tick rows and append to the record; `slice-loop --merge` lands both, `git log -p` shows both appendices and no marker

## Non-goals
Merging the documents listed as 'must change with a change' (they still stop the loop)
