# Slice 01 – Command sweep: worktree recipe, conflict checklist, red under load, commit -F

**Goal:** The /slice command spells out the worktree recipe, the conflict checklist before a squash, the load rule for red tests and commit messages from a file, so slice sessions stop improvising them.
**Round:** R01
**Source:** R01 – F-02, F-03, F-06, F-08 (command)
**Depends on:** –
**Model:** haiku

## Scope
- references/slice-command.md section 3: the worktree recipe – `git worktree add .claude/worktrees/slice-NN -b slice-NN <integration branch>`, enter that folder, `.claude/worktrees/` in `.git/info/exclude`; the squash always runs in the main checkout (F-02)
- references/slice-command.md section 4 step 6: the conflict checklist before the squash commit (F-03)
- references/slice-command.md section 4 step 1: a red test that is green alone or in a second unchanged run is load, not a regression; check commands never end in a pipe inside an && chain (F-06)
- references/slice-command.md sections 3 and 4: every commit message is passed with `git commit -F <file>` from a file or heredoc (F-08)
- tests/markers_test.py: one assertion per new phrase, written first

## Patterns to mirror
- tests/markers_test.py:13 – how a test pins a section's wording (split at the heading, assert the phrases)
- plugins/vibe-coding/skills/vibe-coding/references/slice-command.md:56 – the worktree line the recipe replaces
- plugins/vibe-coding/skills/vibe-coding/references/slice-command.md:111 – the squash step the checklist extends

## NOT building
- Changes to the loop scripts or to who squashes (slices 03, 05, 06)
- The session-hints file (slice 02)

## Prompt
```
Read CLAUDE.md, work/conventions.md, the round record work/rounds/R01-*.md and this slice file.
Implement slice 01 "Command sweep: worktree recipe, conflict checklist, red under load, commit -F" (this file).
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
- [ ] Given slice-command.md When section 3 is read Then it prescribes `git worktree add .claude/worktrees/slice-NN -b slice-NN <integration branch>`, entering that folder and `.claude/worktrees/` in `.git/info/exclude`, and says that superpowers:using-git-worktrees is used only where it follows this recipe (F-02)
- [ ] Given section 4 When the squash step is read Then it requires, in this order: merge the integration branch into slice-NN right before the squash; `grep '^<<<<<<<'` over the resolved files is empty; every line of both sides is still present; the number of `Result:` lines equals ours plus theirs minus the merge base; resolving and committing never run in one command (F-03)
- [ ] Given section 4 When the checks step is read Then a red test that is green when run alone or in a second unchanged run counts as load, is noted under Surprises and does not stop the slice; and check commands never end in `| tail` or another pipe inside an `&&` chain, because the pipe hides the exit code (F-06)
- [ ] Given sections 3 and 4 When a commit is described Then its message is passed with `git commit -F <file>` from a file or heredoc, never inline, because Git Bash rewrites a leading `/` into a path (F-08)
- [ ] Given the unchanged command When the new tests in tests/markers_test.py run Then they fail; after the edits `python tests/markers_test.py` and `claude plugin validate --strict plugins/vibe-coding` pass
- [ ] Manual: Read the four new paragraphs in one pass: each fits its section, none contradicts section 7 or the auto-mode rules

## Non-goals
New markers, loop changes, wording changes outside the four findings
