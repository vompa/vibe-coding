# Slice 04 – Full-suite lock

**Goal:** Two slice sessions never run a full test suite at the same time: before a full suite /slice takes a lock under .slice-loop/ in the main checkout and releases it afterwards; an orphaned lock is reported, never overwritten.
**Round:** R01
**Source:** R01 – F-01 (lock), F-05
**Depends on:** 03
**Model:** sonnet

## Scope
- references/slice-command.md section 4 (and section 2 when the baseline check is a full suite): before a command that work/conventions.md names a full suite, create `.slice-loop/full-suite.lock/` in the main checkout atomically – a directory, `mkdir` in bash, `New-Item -ItemType Directory` without `-Force` in PowerShell – and write `owner` with `slice NN` and an ISO-8601 timestamp
- Held lock: wait and retry every minute up to a documented limit; orphaned lock (the owner's branch slice-MM is gone, or the timestamp is older than a documented age): report it to the user, in auto `SLICE-OPEN: NN lock held by slice MM since <time>`, and never remove or overwrite another session's lock; release the own lock right after the suite, red or green
- Section 1 `status`: one line for a held lock (owner, since when)
- references/templates.md, conventions template: the rule 'never two full suites at once' points to the lock
- SKILL.md section 6: `.slice-loop/full-suite.lock/` among the local, never committed files
- tests/markers_test.py: contract tests first

## Patterns to mirror
- plugins/vibe-coding/skills/vibe-coding/references/slice-command.md:93 – the close-the-slice steps the lock protocol joins
- plugins/vibe-coding/skills/vibe-coding/assets/slice-loop.sh:16 – `.slice-loop` as the loop's local folder, kept out of git through .git/info/exclude

## NOT building
- A lock helper script
- Locks for anything but full suites
- Changes to the loop scripts (slice 05)

## Prompt
```
Read CLAUDE.md, work/conventions.md, the round record work/rounds/R01-*.md and this slice file.
Implement slice 04 "Full-suite lock" (this file).
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
- [ ] Given section 4 When read Then before a full suite it creates `.slice-loop/full-suite.lock/` in the main checkout with `mkdir` (bash) or `New-Item -ItemType Directory` without `-Force` (PowerShell), writes `owner` with the slice number and an ISO-8601 timestamp, and releases it right after the suite, red or green
- [ ] Given a lock held by another slice When its branch slice-MM exists and the timestamp is younger than the documented age Then the session waits and retries every minute up to the documented limit
- [ ] Given a lock whose owner branch is gone or whose timestamp is older than the documented age When found Then the session reports it (auto: `SLICE-OPEN: NN lock held by slice MM since <time>`) and never removes or overwrites it
- [ ] Given `/slice status` When a lock is held Then one line names the owner and the time
- [ ] Given templates.md When the conventions template is read Then 'never two full suites at once' points to the lock; and SKILL.md section 6 lists `.slice-loop/full-suite.lock/` as local
- [ ] Given the unchanged files When the new tests in tests/markers_test.py run Then they fail; afterwards `python tests/markers_test.py` passes
- [ ] Manual: In a scratch repository create the lock directory by hand with an owner file, then run `/slice NN` on a slice whose checks include a full suite: the session reports the lock and waits or stops as described

## Non-goals
Locks across repositories; detecting running test processes
