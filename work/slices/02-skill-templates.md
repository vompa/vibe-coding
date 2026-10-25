# Slice 02 – Skill and templates: session hints, check scope, findings marking

**Goal:** The skill, the templates and the command treat work/session-hints.md, the check scope per slice and the marking of a tracked findings list as part of every round.
**Round:** R01
**Source:** R01 – F-04, F-05, F-07
**Depends on:** 01
**Model:** sonnet

## Scope
- references/templates.md: a `## work/session-hints.md` template – repository-specific hints for slice sessions, grown round by round; example bullets marked as an open list (F-04)
- SKILL.md: section 2 creates work/session-hints.md in the first round and later rounds append to it; section 6 lists it among the committed files; the output structure shows it (F-04)
- references/slice-command.md: section 2 reads work/session-hints.md when it exists; the parallel prompts of section 7 name it (F-04)
- references/templates.md, conventions template, line `Checks for a slice`: distinguishes 'one screen touched: its test classes plus the cross-page scan tests' from 'shared code touched: full suite' and names the rule 'never two full suites at once'; SKILL.md section 2 asks for this split when discovering the conventions (F-05)
- SKILL.md section 3 and references/slice-command.md section 4: when the round's source is a tracked findings file, the record names the file and its marking format under `## Source`, and each slice marks its ids there as 'done in slice NN' in that format before the squash (F-07)
- plugins/vibe-coding/README.md 'What you get': work/session-hints.md in the tree
- tests/markers_test.py: contract tests first

## Patterns to mirror
- plugins/vibe-coding/skills/vibe-coding/references/templates.md:86 – how a template section introduces a file (heading, one paragraph, fenced example)
- plugins/vibe-coding/skills/vibe-coding/SKILL.md:135 – the write list every new file joins
- work/session-hints.md:1 – the first instance of the file, written for this repository

## NOT building
- The full-suite lock (slice 04)
- Changes to scripts/render_slices.py
- A script that marks findings automatically

## Prompt
```
Read CLAUDE.md, work/conventions.md, the round record work/rounds/R01-*.md and this slice file.
Implement slice 02 "Skill and templates: session hints, check scope, findings marking" (this file).
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
- [ ] Given templates.md When read Then it holds a section `## work/session-hints.md` with a purpose line and example bullets marked as an open list (F-04)
- [ ] Given SKILL.md When sections 2 and 6 are read Then the first round creates work/session-hints.md from the template, later rounds append to it, and `work/session-hints.md` appears in the committed-files list and in the output structure (F-04)
- [ ] Given slice-command.md When section 2 is read Then work/session-hints.md is in the read list, marked 'when it exists'; and When section 7 is read Then every parallel prompt names it (F-04)
- [ ] Given the conventions template When the `Checks for a slice` line is read Then it shows the cases 'one screen touched: its test classes plus the cross-page scan tests' and 'shared code touched: full suite' and the rule 'never two full suites at once'; and SKILL.md section 2 asks the user for this split (F-05)
- [ ] Given a round whose source is a tracked findings file When SKILL.md section 3 and slice-command.md section 4 are read Then the record names the file and its marking format, and each slice marks its ids as 'done in slice NN' in that format before the squash; a round whose source is the intake table marks nothing (F-07)
- [ ] Given the unchanged files When the new tests in tests/markers_test.py run Then they fail; afterwards `python tests/markers_test.py` passes and `claude plugin validate --strict plugins/vibe-coding` is green
- [ ] Manual: Read SKILL.md sections 2, 3 and 6 in one pass: the new sentences fit the phase table and the write list, nothing is said twice

## Non-goals
Changes to intake.md beyond a pointer; any loop change
