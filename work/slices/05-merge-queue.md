# Slice 05 – Merge queue in both loop scripts

**Goal:** Both loop scripts squash the finished branches one after another in the main checkout: they accept SLICE-READY, merge each branch, commit with the message from the file, tick Commit, remove the merged branch and worktree, and stop with the file names on any conflict; --merge runs that queue alone.
**Round:** R01
**Source:** R01 – F-01 (queue), F-08 (loop)
**Depends on:** 04
**Model:** opus

## Scope
- assets/slice-loop.sh and assets/slice-loop.ps1, functionally identical: a build turn that ends in `SLICE-READY: NN` (besides `SLICE-DONE: NN`) hands the slice to the merge queue
- Merge queue: in the main checkout, with a clean working tree, `git merge --squash slice-NN`; on any conflict reset the merge (`git reset --merge`), keep the branch, report the conflicted files (`git diff --name-only --diff-filter=U`) and exit 1
- Commit: tick the Commit column of row NN in work/checklist.md, stage, `git commit -F .slice-loop/slice-NN.msg`; when the file is missing, write `Slice NN: <name> (<source>)` from work/_slices.json to a temporary file and use that with -F (F-08); then the usual is_done check
- Cleanup: `git worktree remove <path>` without `--force` when `git worktree list --porcelain` shows the branch, then `git branch -d slice-NN`; a worktree that cannot be removed is reported and left
- `--parallel` / `-Parallel`: builds run side by side, squashes run one after another in the main process in finishing order
- `--merge` / `-Merge`: squash every branch slice-NN whose checklist row on the branch (`git show slice-NN:work/checklist.md`) has every column but Commit ticked, lowest number first, then exit 0 without starting a session; works without an open round
- tests/loop_test.py: the vibe-coding profile runs in a real git repository with a local test identity; the fake claude creates the worktree and branch, ticks the row through Checks, adds a file, commits, writes the message file and prints SLICE-READY; the vibe-rebuild profile is unchanged
- Script headers and usage lines: the new option

## Patterns to mirror
- plugins/vibe-coding/skills/vibe-coding/assets/slice-loop.sh:161 – build_slice, where the marker is read and is_done is checked
- plugins/vibe-coding/skills/vibe-coding/assets/slice-loop.ps1:115 – Assert-SliceDone, the PowerShell twin
- plugins/vibe-coding/skills/vibe-coding/assets/slice-loop.sh:32 – parse_args, how an option is added and documented
- tests/loop_test.py:16 – the fake claude; tests/loop_test.py:133 – make_repo; tests/loop_test.py:64 – the profile table with its expected tuples

## NOT building
- Rule-based conflict resolution (slice 06): in this slice every conflict stops the loop
- Changes to rebuild-loop.* or to the vibe-rebuild profile of the test
- A third runtime for the queue: the logic lives in each shell

## Prompt
```
Read CLAUDE.md, work/conventions.md, the round record work/rounds/R01-*.md and this slice file.
Implement slice 05 "Merge queue in both loop scripts" (this file).
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
- [ ] Given a round with ready slices When `slice-loop --yes` runs with the fake claude Then after each slice the integration branch has one new commit whose message is the content of `.slice-loop/slice-NN.msg`, the row is fully ticked, no branch slice-NN and no worktree remain, the working tree is clean, and the round closes
- [ ] Given two prepared branches slice-100 and slice-101 whose rows are ticked through Checks and which conflict in a file shared.txt When `slice-loop --merge` runs Then slice-100 is squashed, slice-101 stops the loop with exit 1 and `shared.txt` in the message, the working tree is clean and branch slice-101 still exists
- [ ] Given one prepared ready branch When `slice-loop --merge` runs Then it is squashed and the loop exits 0 without any claude call (stub-calls.log is empty)
- [ ] Given a branch slice-NN whose row still has Checks at ☐ When `slice-loop --merge` runs Then the branch is not merged
- [ ] Given a missing message file When a ready branch is squashed Then the commit message is `Slice NN: <name> (<source>)` from work/_slices.json, passed with -F
- [ ] Given both scripts When `python tests/loop_test.py` runs Then every case passes for bash and pwsh alike; `bash -n`, the PowerShell parse and `python tests/markers_test.py` (both loop scripts name `SLICE-READY:`) are green
- [ ] Manual: Run the loop against a scratch repository with the copied command: two slices in a row land as two squash commits, `git worktree list` shows only the main checkout afterwards

## Non-goals
Conflict resolution; merging into any branch but the one checked out in the main folder
