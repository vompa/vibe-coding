# Slice 09 – Command rules: assumptions, seams, tests, stop criteria, review axes, ADR, debugging

**Goal:** The /slice command tells a session how to plan assumptions, cut and verify tests, when to stop, how to review and when an ADR is due, in nine short positive sentences, so sessions stop asking one question at a time, writing tautological tests and stopping for trivia.
**Round:** R01
**Source:** R01 – F-09
**Depends on:** 01
**Model:** sonnet

## Scope
- references/slice-command.md section 3, plan: assumptions as one numbered round with a recommendation per point, worded so that 'yes' takes the recommendations; facts come from code and docs, only decisions are asked; an unambiguous task skips the round (F-09.1)
- Section 3, plan: name the seams the tests hit; the review focus says per seam what the test catches and what it misses (F-09.2)
- Section 3, tests first: expected values from an independent source, never computed like the code (no tautological tests); red counts only when the test checks exactly the fault or requirement; type check and the single test file often, the full suite once at the end; refactor after green (F-09.3)
- Section 3, build: stop only for a real blocker – missing dependency, contradiction to the plan, an ambiguity that would produce wrong code under a wrong assumption; trivia the code answers, style questions (follow existing patterns) and things a test can settle go on; no 'subagent or inline?' question after the plan (F-09.4)
- Section 4, review on two separate axes: specification – every finding cites the plan line, unrequested scope is asked about – and standards – the repository rule beats the general rule, what tools enforce stays out (F-09.5)
- Section 4, before the squash (and before SLICE-READY once slice 03 adds it): merge the integration branch into slice-NN and run the checks after the merge; extends the F-03 line of slice 01 (F-09.6)
- Section 4, decisions: an ADR only when the decision is hard to reverse, would surprise without context or settled a real conflict of goals; everything else is a Ruling in the round record (F-09.7)
- New paragraph 'Debugging' for slices that fix a fault: first a command that shows the fault red, no hypothesis before it; three to five ranked hypotheses before one is tested; the regression test at a fitting seam, and a missing seam is itself a finding (F-09.8)
- tests/markers_test.py: the terms, the positive wording and the line budget, written first

## Patterns to mirror
- plugins/vibe-coding/skills/vibe-coding/references/slice-command.md:51 – section 3, where the plan and build rules live
- plugins/vibe-coding/skills/vibe-coding/references/slice-command.md:93 – section 4, the close-the-slice steps
- tests/markers_test.py:13 – how a test pins a section's wording

## NOT building
- A tracker duty, a glossary file, a sentinel folder or a lateral-thinking step (F-09.9)
- Changes to the loop scripts, templates or SKILL.md
- Installing or referencing the reviewed plugins

## Prompt
```
Read CLAUDE.md, work/conventions.md, the round record work/rounds/R01-*.md and this slice file.
Implement slice 09 "Command rules: assumptions, seams, tests, stop criteria, review axes, ADR, debugging" (this file).
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
- [ ] Given slice-command.md When tests/markers_test.py runs Then it finds 'assumptions' together with 'recommend', and the terms 'seam', 'tautolog', 'stop only', 'two axes' (or an equivalent the test names) and 'ADR' in the command
- [ ] Given section 3 When the plan rules are read Then assumptions form one numbered round with a recommendation per point that 'yes' accepts, facts are looked up rather than asked, an unambiguous task skips the round, and the plan names the seams with what each test catches and misses
- [ ] Given section 3 When the test rules are read Then expected values come from an independent source, red counts only for a test that checks the fault or requirement, type check and single file run often and the full suite once at the end, and refactoring follows green
- [ ] Given section 3 When the build rules are read Then a session stops only for a real blocker as defined, goes on for trivia, style and test-settled questions, and asks no 'subagent or inline?' question
- [ ] Given section 4 When read Then the review has two separate axes (specification citing the plan line, standards with repository rule first), the integration branch is merged into slice-NN and the checks run again before the squash or SLICE-READY, and an ADR is written only under the three named conditions
- [ ] Given the command When the debugging paragraph is read Then it demands a red-showing command before any hypothesis, three to five ranked hypotheses before testing one, and a regression test at a fitting seam
- [ ] Given the command before and after the slice When the lines are counted Then it grew by at most 25 lines, the new sentences are positive (no new 'never' list beyond those the command had), `python tests/markers_test.py` and `claude plugin validate --strict plugins/vibe-coding` pass
- [ ] Manual: Read sections 3 and 4 once in a row: the nine sentences read as rules of one voice, none repeats what slice 01 wrote, and the debugging paragraph is reachable from section 3

## Non-goals
Rules for the planning skill itself; wording changes outside the nine points
