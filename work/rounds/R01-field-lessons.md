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
Ruling: slice 01 plan approved with its six assumptions as recommended (recipe by hand, both section 3 branches, privacy scan by hand, CHANGELOG 1.2.0 started, no README change, loop test as a check) – User, 2026-10-25
Ruling: slice 09 plan approved with its six assumptions as recommended (rule block in section 3, review axes and ADR filter in section 4, step 6a gains the re-check after the merge without naming SLICE-READY, budget pinned as at most 220 lines and at most 16 "never", privacy scan by hand, CHANGELOG bullet, no README change) – User, 2026-10-25
Ruling: slice 02 plan approved with its nine assumptions as recommended (hints template after the conventions template, creation and appending in SKILL.md section 2, read line and parallel-prompt clause in the command, check scope split on the `Checks for a slice` line, findings marking in SKILL.md section 3 plus the command, command budget kept at 220 lines and 16 "never", phrase tests, README tree line, CHANGELOG bullet with a manual privacy scan) – User, 2026-10-25
Ruling: slice 03 plan approved with all nine assumptions (hint `[auto | parallel]`, step 5 stops with the message file and SLICE-READY, loop scripts untouched until slice 05, section 6 meaning, parallel prompts, "ready to merge" in status, budget, phrase tests) – User, 2026-10-25 (via the orchestrating session)
Ruling: slice 04 plan approved with all ten assumptions (lock paragraph at the end of step 1 with a clause in section 2, `mkdir` / `New-Item` without `-Force` plus an `owner` file, wait 30 minutes for a live slice under 60 minutes old and report anything else, `status` line, template and SKILL.md pointers, line limit 230, slice 08 untouched and merged in before the squash, phrase tests) – User, 2026-10-25 (via the orchestrating session)
Ruling: Slice 08 – plan approved with all six assumptions (merge queue named as `slice-loop --merge` or the running loop, rules sentence without the conflict clause, three new assertions in the existing Start test, README Ready paragraph and request sentence, command/loop scripts/tests untouched, slice-board and baseline checks) – User, 2026-10-25 (via the orchestrating session)

## Surprises
- `CLAUDE.md` does not exist at the repository root, although the slice command names it. The rules came from `work/conventions.md` and the workspace note; nothing changed for that.
- The first run of the tests after the command edits failed on one case mismatch: the test looked for "the squash always runs" while the command says "The squash always runs". The test was corrected to the command's wording; it had been red before the edit and was not weakened.
- The Bash tool turns a doubled backslash in an inline Python command into one; the privacy scan was written with `chr(92)` instead (already in the pitfall list).
- Slice 09: the command grew by 16 lines (195 → 211) and the word "never" still occurs 16 times, as before: no new prohibition. The gate `test_command_stays_short_and_positive` was green before the edit by design; the other seven new tests were red first and went green with the edit.
- Slice 09: the ADR clause of step 3 replaced "ADR when a principle changed" instead of adding a second sentence, so the rule has one voice. This repository has no ADR folder (CHANGELOG is its decision record); the clause is for the target repositories.
- Slice 02: `claude plugin validate --strict .` (marketplace) fails on the integration branch already, before any edit: `plugins[2]` (slice-board) has no `version` in its `plugin.json`, and `--strict` treats the warning as an error. Not caused by this slice (it touches no manifest); the conventions list this command among the checks when `SKILL.md` changes, so the failure is recorded here. Plugin-level `claude plugin validate --strict plugins/vibe-coding` is green.
- Slice 02: the command grew by 3 lines (211 → 214), "never" count unchanged; no limit had to move. The five new tests were red first for the intended reasons (missing sections and phrases) and green after the edits.
- Slice 02: the repository's own `work/session-hints.md` was written in this round before the template existed (F-04 anticipated it); the template now matches its shape (title, purpose paragraph, bullets), the file itself is unchanged.
- Slice 03: the command grew by 6 lines (214 → 220), not the 8 the plan estimated, so assumption 8 (raise the size limit to 230) was not needed: the guard stays at 220 lines and 16 "never". The six new tests were red first for the intended reasons; the two changed assertions (`MARKERS`, the argument hint) follow the contract. The step for the squash message sits at the end of step 5 (as a paragraph, not a new numbered step) so the numbering of 6a to 6d stays as other documents cite it.
- Slice 04: the command grew by 8 lines (220 → 228) and the guard moved from 220 to 230 lines as planned; "never" count unchanged (16). The four new tests were red first for the intended reasons. The numbers of the lock (60 minutes age, 30 minutes wait) are this slice's choice, documented in the command and in the plan.
- Slice 04: `claude plugin validate --strict .` fails for the known slice-board warning only (see slice 02); the plugin-level validation is green.
- Slice 08: the Start test was red for the intended reason (the request said `"/slice NN"` and the old conflict clause). The request text is generic (`NN`), not per slice, so the test asserts `"/slice NN parallel"`; it went green with the one edit of `requestStart`. `claude plugin test plugins/slice-board`: 5 of 5 pass. The slice-board plugin-level validation keeps its warning about the missing `version`.

## Deferred minors
- Slice 04: the lock is a protocol in prose; nothing executes it in the loop scripts (slice 05 decides whether the queue uses it for its own checks). A lock left by a crashed session is only reported, never removed: the user removes the directory by hand.
- Slice 08: the request names `slice-loop --merge`, which slice 05 introduces; until then the phrase "or the running loop" is the only working path.
- Slice 02: the marketplace validation warning (slice-board without `version`) is not fixed here; slice 07 (release) is the natural place, or a separate fix to the slice-board manifest.
- Slice 03: the loop scripts do not read `SLICE-READY` yet (slice 05); until then a loop run with `auto` ends at the new marker and is reported as stopped. `SLICE-DONE:` stays defined for runs without `auto` and `parallel`.
- A scan test over `work/` in `tests/markers_test.py` (conventions: extend when round files change) is a follow-up; this slice's acceptance cases name phrase tests only, and the scan ran by hand.
- The privacy regex line of `tests/markers_test.py` (line 51) matches its own pattern in a manual scan of `tests/`; expected, not a leak.

## Open decisions

## Manual test list    (drafted per slice, completed at round close; format: round-close.md)
### Slice 01 – Command sweep: worktree recipe, conflict checklist, red under load, commit -F
Start: `python tests/markers_test.py`
1. Read sections 3 and 4 of `plugins/vibe-coding/skills/vibe-coding/references/slice-command.md` in one pass.
Expected: the new paragraphs (worktree recipe, squash checklist, load and pipe rules, `git commit -F`) each fit their section, and none contradicts section 7 or the auto-mode rules.
Closes: F-02, F-03, F-06, F-08
Result: ☐

### Slice 09 – Command rules: assumptions, seams, tests, stop criteria, review axes, ADR, debugging
Start: `python tests/markers_test.py`
1. Read sections 3 and 4 of `plugins/vibe-coding/skills/vibe-coding/references/slice-command.md` in one pass.
Expected: the nine rules read in one voice, none repeats what slice 01 wrote, and the Debugging paragraph in section 3 is easy to find.
Closes: F-09
Result: ☐

### Slice 02 – Skill and templates: session hints, check scope, findings marking
Start: `python tests/markers_test.py`
1. Read sections 2, 3 and 6 of `plugins/vibe-coding/skills/vibe-coding/SKILL.md` in one pass.
Expected: the session-hints, check-scope and findings-marking sentences fit the phase table and the write list, and nothing is said twice.
Closes: F-04, F-05, F-07
Result: ☐

### Slice 03 – SLICE-READY marker and the parallel argument
Start: `claude --plugin-dir plugins/vibe-coding` in a scratch repository with the command copied to `.claude/commands/slice.md`
1. Run `/slice NN parallel` for a ready slice and approve its plan.
Expected: the session ends with the line `SLICE-READY: NN`; the branch `slice-NN` is committed, `.slice-loop/slice-NN.msg` exists in the main checkout, the Commit column stays ☐ and the integration branch did not move.
Closes: F-01 (marker), F-08
Result: ☐

### Slice 04 – Full-suite lock
Start: `claude --plugin-dir plugins/vibe-coding` in a scratch repository with the command copied to `.claude/commands/slice.md`
1. Create `.slice-loop/full-suite.lock/` by hand with an `owner` file naming another slice and the current time, then run `/slice NN` on a slice whose checks include a full suite.
Expected: the session reports the lock with owner and time, waits and retries every minute while the owner's branch exists, and stops with `SLICE-OPEN: NN lock held by slice MM since <time>` in auto mode when the branch is gone; it never removes the lock.
Closes: F-01 (lock), F-05
Result: ☐

### Slice 08 – slice-board starts sessions with /slice NN parallel
Start: `claude plugin test plugins/slice-board`, then open the pane in a repository with an open round and two ready slices
1. Press Start in the pane.
Expected: the prompt box holds a request that briefs each session with `/slice NN parallel`, says it ends with `SLICE-READY: NN` and names the merge queue (`slice-loop --merge`, or the running loop).
Closes: F-01 (parallel sessions from the pane)
Result: ☐
