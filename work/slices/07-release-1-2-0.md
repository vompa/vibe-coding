# Slice 07 – Release 1.2.0: version, changelog, READMEs

**Goal:** vibe-coding 1.2.0 is documented and consistent: version, changelog, both READMEs and the full check chain.
**Round:** R01
**Source:** R01 – all findings
**Depends on:** 06, 08
**Model:** sonnet

## Scope
- plugins/vibe-coding/.claude-plugin/plugin.json `version` and SKILL.md `metadata.version`: 1.2.0
- plugins/vibe-coding/CHANGELOG.md: `## 1.2.0 – <date>` with one bold-led bullet per theme – merge queue and SLICE-READY, full-suite lock, session hints, check scope, findings marking, command sweep (worktree recipe, conflict checklist, red under load, commit -F) – tests named
- plugins/vibe-coding/README.md: the tree with work/session-hints.md; `/slice NN parallel`; the loop table with `--merge`/`-Merge`; the marker list with `SLICE-READY:`; the lock and the merge queue under 'Good to know'
- Root README.md: the loop test paragraph names the merge-queue cases; the markers test paragraph the new contracts
- Full check chain from work/conventions.md, green

## Patterns to mirror
- plugins/vibe-coding/CHANGELOG.md:3 – the 1.1.0 entry: bold lead, what and why, tests named
- plugins/vibe-coding/README.md:76 – the hands-off section and its option table

## NOT building
- Changes to slice-board or vibe-rebuild
- Pushing, tagging or publishing

## Prompt
```
Read CLAUDE.md, work/conventions.md, the round record work/rounds/R01-*.md and this slice file.
Implement slice 07 "Release 1.2.0: version, changelog, READMEs" (this file).
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
- [ ] Given plugin.json and SKILL.md When read Then both say 1.2.0, and `claude plugin validate --strict plugins/vibe-coding` and `claude plugin validate --strict .` pass
- [ ] Given CHANGELOG.md When read Then `## 1.2.0 – <date>` lists every theme of slices 01–06 and names the tests that cover them
- [ ] Given plugins/vibe-coding/README.md When read Then it shows work/session-hints.md in the tree, `/slice NN parallel`, `--merge`/`-Merge`, `SLICE-READY:` and the full-suite lock; and the root README's loop test paragraph names the merge-queue cases
- [ ] Given the integration branch When the full check chain from work/conventions.md runs Then every step is green (skills-ref may be skipped locally and noted under Decisions)
- [ ] Manual: Read the plugin README top to bottom once: every option and marker it names exists in the command or the scripts

## Non-goals
New behaviour
