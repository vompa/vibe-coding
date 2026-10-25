Status: open

# Round R01 – field lessons: merge queue, suite lock, session hints

## Source
Notes from operating this skill in a target repository (two rounds, R01 with 29 and R02 with 27 slices, 2026-10-23 to 2026-10-25), relayed in chat as findings F-01 to F-08. No tracked findings file: the intake table below is the source the slices read. The target repository's own files are not part of this record.

## Intake
| id | where | observed → expected | size | source |
|---|---|---|---|---|
| F-01 | `/slice` section 4, both loop scripts, `tests/loop_test.py`, `tests/markers_test.py` | Every slice session squashes onto the integration branch itself and resolves the same conflicts in `work/checklist.md`, the round record, the protocol and the status page again; once conflict markers landed in a commit, once a foreign `git add` fell into an open squash → in auto and parallel runs `/slice` ends with a new marker `SLICE-READY: NN` (branch committed, checklist ticked through Checks, squash message in a file), and `slice-loop` squashes the finished branches one after another in the main checkout (merge queue) with rule-based resolution in `checklist.md` and the round record (keep both sides, union of ticks per row, every line of both sides kept, no marker left, else stop), stopping with the file names on a conflict anywhere else; plus a file lock under `.slice-loop/` for full test suites (owner, timestamp; an orphaned lock is reported, never overwritten) that `/slice` takes before a full suite | L → slices 03, 04, 05, 06 | field notes |
| F-02 | `/slice` section 3 | The section only says "superpowers:using-git-worktrees"; sessions in the desktop app failed with the harness's own worktree tool (its shell guard rejects every `git` command, the worktree branches from the wrong base) → the command prescribes `git worktree add .claude/worktrees/slice-NN -b slice-NN <integration branch>`, entering the folder, `.claude/worktrees/` in `.git/info/exclude`; the squash always runs in the main checkout | S | field notes |
| F-03 | `/slice` section 4 step 6 | "keep every tick and entry from both sides" is the only conflict rule → a checklist before the commit: no conflict marker (`grep '^<<<<<<<'` empty), every line of both sides still present, number of `Result:` blocks equals ours plus theirs minus the merge base; merge the integration branch into the slice branch right before the squash; never resolve and commit in one command | S | field notes |
| F-04 | SKILL.md sections 2 and 6, `templates.md`, `/slice` sections 2 and 7 | Only the slice-board pane reads `work/session-hints.md` and attaches it to start prompts → the skill creates the file at round start (template in `templates.md`: repository-specific hints for slice sessions, grown round by round), `/slice` reads it in section 2, the parallel prompts of section 7 name it, SKILL.md section 6 lists it among the written files | M | field notes |
| F-05 | `templates.md` conventions template, SKILL.md section 2 | "Checks for a slice" is one line → it distinguishes "one screen touched: its test classes plus the cross-page scan tests" from "shared code touched: full suite" and names the rule "never two full suites at once"; SKILL.md section 2 asks for the split when discovering conventions | S | field notes |
| F-06 | `/slice` section 4 | Several sessions blamed randomly red tests (load from parallel suites) on another slice → a red test that is green alone or in a second unchanged run counts as load, goes under Surprises and does not stop the slice; check commands never end in `\| tail` or another pipe inside an `&&` chain (exit code) | S | field notes |
| F-07 | SKILL.md section 3, `/slice` section 4 | Done findings in a tracked findings file are not marked → when the round's source is a tracked findings file, each slice marks its ids there as done ("done in slice NN" in the file's own format) when it closes | S | field notes |
| F-08 | `/slice` sections 3–4, both loop scripts | Git Bash rewrites a commit message with a leading `/` into a path ("C:/Program Files/Git/slice …") → `/slice` and the loop pass commit messages with `-F` from a file or heredoc | S | field notes |
| F-09 | `/slice` sections 3 and 4, a new debugging paragraph | The command says little about plan assumptions, test cut, review, stop criteria and when an ADR is due; sessions ask one question at a time, write tests whose expected values are computed like the code, mix specification and style review, stop for trivia or run on past real blockers → nine short, positively worded rules in the command: (1) section 3, plan: assumptions as one numbered round with a recommendation per point, worded so that "yes" takes the recommendations; facts come from code and docs, only decisions are asked; an unambiguous task skips the round; (2) section 3, plan: name the seams the tests hit; the review focus says per seam what the test catches and what it misses; (3) section 3, tests first: expected values from an independent source, never computed like the code; red counts only when the test checks exactly the fault or requirement; type check and the single test file often, the full suite once at the end; refactor after green; (4) section 3, build: stop only for a real blocker (missing dependency, contradiction to the plan, an ambiguity that would produce wrong code under a wrong assumption), not for trivia the code answers, style questions (follow existing patterns) or things a test can settle; no "subagent or inline?" question after the plan; (5) section 4, review on two separate axes: specification (every finding cites the plan line; ask about unrequested scope) and standards (repository rule beats general rule; what tools enforce stays out); (6) section 4, before the squash or SLICE-READY: merge the integration branch into slice-NN and run the checks after the merge; (7) section 4, decisions: an ADR only when the decision is hard to reverse, would surprise without context or settled a real conflict of goals, everything else a Ruling in the round record; (8) a new debugging paragraph for slices that fix a fault: first a command that shows the fault red, no hypothesis before; three to five ranked hypotheses before one is tested; the regression test at a fitting seam, and a missing seam is itself a finding; (9) not adopted: a tracker duty, a glossary file, a sentinel folder, a lateral-thinking step. Acceptance: `tests/markers_test.py` finds "assumptions" with "recommend", "seam", "tautolog", "stop only", "two axes" (or equivalent) and "ADR"; sentences are positive (no new "never" lists beyond where the command has them); the command grows by at most 25 lines | M → slice 09 | review of the plugins mattpocock-skills 1.3.1 and decibelsystems/superpowers, 2026-10-25 (both read in source, neither installed) |

## Slices
| Slice | Name | Findings / ACs |
|---|---|---|
| 01 | Command sweep: worktree recipe, conflict checklist, red under load, commit -F | F-02, F-03, F-06, F-08 (command) |
| 02 | Skill and templates: session hints, check scope, findings marking | F-04, F-05, F-07 |
| 03 | SLICE-READY marker and the `parallel` argument | F-01 (marker), F-08 |
| 04 | Full-suite lock | F-01 (lock), F-05 |
| 05 | Merge queue in both loop scripts | F-01 (queue), F-08 (loop) |
| 06 | Rule-based resolution of checklist and round record | F-01 (resolution) |
| 07 | Release 1.2.0: version, changelog, READMEs | all |
| 08 | slice-board starts sessions with `/slice NN parallel` | F-01 (parallel sessions from the pane) |
| 09 | Command rules: assumptions, seams, tests, stop criteria, review axes, ADR, debugging (runs after 01, before 02) | F-09 |

## Decisions
Ruling: F-09 joins the round as slice 09 of its own, right after slice 01 and before slice 02 (both change the command, so 02 now depends on 09); slice 01 keeps its four findings and its model – User, 2026-10-25 (mapping chosen by the planning session as the user allowed)
Ruling: conventions and slice map taken as proposed; slice 08 (slice-board starts sessions with `/slice NN parallel`) is part of this round, after slice 03 – User, 2026-10-25
[Assumption] The tests of F-01 are not a slice of their own: each slice writes its own tests first (`tests/markers_test.py`, `tests/loop_test.py`), as the Definition of Done demands.
[Assumption] The merge queue and its resolution rules live in each loop script (bash and PowerShell, functionally identical); no third runtime or helper file is copied into target repositories.
[Assumption] `work/session-hints.md` is written in this round already (F-04 anticipates it) so the slice sessions of this round get the repository's own hints.
[Assumption] The round's source stays in chat; the intake table summarises it without naming the target repository (this repository is public).

## Surprises

## Deferred minors

## Open decisions

## Manual test list    (drafted per slice, completed at round close; format: round-close.md)
