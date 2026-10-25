---
description: Work the current round slice by slice – next slice, a given slice, status, or close the round
argument-hint: "[status | NN | close] [plan] [auto] [direct]"
---
You work the open round of this repository slice by slice. Arguments: "$ARGUMENTS".
Answer me in the language of CLAUDE.md or README.md.
"auto" means a script drives this session headless: nobody can answer questions mid-run.
Never stop to ask in auto mode – decide on the documented default, or end with the marker
lines of section 6 so the script can ask me.
Everything specific to this repository comes from work/ and CLAUDE.md; this command never needs editing.

## 1. Decide what to do
The open round is the record in work/rounds/ whose first line is exactly "Status: open"; its id
Rnn is the start of the file name. A slice belongs to a round by the field "round" in
work/_slices.json. A slice is done when its row in work/checklist.md has a ☑ and no ☐.
- no open round → say "No open round – start one with the vibe-coding skill" and stop; change nothing.
  More than one → name them and stop (auto: "SLICE-OPEN: NN more than one round is open – close one
  first"; with "close": "ROUND-OPEN: Rnn more than one round is open").
- "status" → read work/checklist.md, work/_slices.json and the git branches named slice-*.
  Show one table for the slices of the open round: slice, name, model (field "model" in
  work/_slices.json), state (done / in progress / ready / blocked by …; "in progress" = not done,
  but a branch slice-NN exists or the row has a ☑),
  then the number of open decisions in the round record and one line "Ready next: …". Two or more
  ready: offer parallel sessions (section 7). Stop there.
- "close" → section 5.
- a number NN (two or more digits) → work on slice NN. Already done: say so and stop. A slice it
  depends on (field "deps") is not done: say which one and ask before going on
  (auto: print "SLICE-OPEN: NN blocked by <deps>" and stop).
- nothing → pick the lowest-numbered slice of the open round that is not done and whose
  dependencies are all done. Say which one and why; if others are ready too, offer them parallel
  sessions first (section 7), then go on with yours. Slices are left but none is ready:
  show the status table and stop. Every slice of the round is done: say "All slices of Rnn done",
  propose "/slice close" (auto: print "ALL-DONE") and stop.

## 2. Read first, then check the baseline
- work/conventions.md – integration branch, merge style, the commands (baseline check, checks for a
  slice, full check chain), protocol file, documents that must change with a change, language,
  privacy rule
- the open round record work/rounds/Rnn-*.md – source, brief, decisions so far, open decisions
- work/slices/NN-*.md – goal, source, model, scope, patterns to mirror, NOT building, prompt,
  Definition of Done, non-goals
- CLAUDE.md (and AGENTS.md when present) – the repository's hard rules
- what the slice's Source names: the findings file or concept document (the round record only
  references it), work/research.md when the slice cites it
Before you change anything the working tree must be clean and the integration branch checked out;
otherwise say what to do (auto: "SLICE-OPEN: NN <reason>"). Then run the baseline check from
work/conventions.md. Red → change nothing and ask whether to fix that first
(auto: "SLICE-OPEN: NN baseline red: <check>" and stop). No baseline check listed: only a slice
that creates the checks itself may go on; otherwise stop ("SLICE-OPEN: NN no baseline check").

## 3. Plan and build the slice
A branch slice-NN or a worktree for it may exist already (normal after a red slice and a re-run):
continue on it, never create a second one and never delete or reset it silently. Re-read its plan in
work/plans/ (and the superpowers ledger, if there is one) and the round record, and resume where they say.
If the superpowers skills are available and "direct" is not in the arguments:
1. worktree recipe: `git worktree add .claude/worktrees/slice-NN -b slice-NN <integration branch>`, then enter
   that folder; `.claude/worktrees/` goes into `.git/info/exclude` once. Use superpowers:using-git-worktrees
   only where it follows this recipe. The squash always runs in the main checkout.
2. superpowers:writing-plans – save the plan as work/plans/<YYYY-MM-DD>-slice-NN.md with a section
   "Assumptions (confirm on approval)" and a "Review focus"; mirror the slice's patterns, leave out
   its NOT-building list, and name the failing test for every acceptance case (the test name
   carries the Given/When/Then). Review the plan and show it to me before writing any code.
3. after my approval: superpowers:subagent-driven-development (superpowers:executing-plans without
   subagents) – tests first (red), then the minimum to get green, every rule in CLAUDE.md and
   work/conventions.md; task commits on slice-NN are fine, each passed with `git commit -F <file>` (section 4)

Otherwise (no superpowers, or "direct"):
1. the worktree recipe above (new branch "slice-NN" in its own worktree)
2. follow the prompt in the slice file: present the plan (files, classes, tests, assumptions, review
   focus), save it as work/plans/<YYYY-MM-DD>-slice-NN.md and wait for my approval
3. failing tests first, then the minimum to get green, then refactor

"plan" in the arguments → stop right after the plan is saved and shown. End with the line
"PLAN: <path of the plan file>", plus one line "NEEDS-DECISION: <question>" for each point that
changes architecture, scope, cost or licences, or adds a package the repository does not use yet,
and that the plan cannot settle by an assumption. The next message in this same session either approves ("build
and close it"), carries answers to the questions (record each as a Ruling, section 4), or is a change
request (revise the plan, save it, end again with the PLAN line).
Without "plan" and with "auto": go on with the plan's assumptions; a point that needs a decision ends
the run with its NEEDS-DECISION line and nothing built.

The slice's model is the field "model" of its entry in work/_slices.json: the cheapest model that does
this slice reliably, and the model this session was started on (by the loop or by section 7). Subagents
of this slice (explorers, implementers) run on that model or a cheaper one; only a reviewing pass may use
a stronger one, and only when work/conventions.md asks for it.

As each step finishes, tick its column in the slice's row of work/checklist.md on slice-NN: Plan when
the plan is approved, Tests red when the new tests fail for the right reason, Green when they pass.
A column that does not apply (for example Tests red in a harness or docs-only slice) is ticked too,
and the reason goes into the round record under Decisions, so the row has no ☐ left.

Keep me posted: one short status line at least every few minutes (what finished, what runs next).
Long reports of subagents go to work/_raw/ (git-ignored), not into the chat.

## 4. Close the slice
Do 1–4 on slice-NN, so they land in the same commit as the code.
1. Run the checks that work/conventions.md names for a slice; check the Definition of Done in the
   slice file, including "no test weakened or skipped" and "no new package without approval".
   A red test that is green when run alone or in a second unchanged run is load, not a regression: note it
   under Surprises and go on. Check commands never end in `| tail` or another pipe inside an `&&` chain:
   the pipe hides the exit code, so write the output to a file and read its exit code.
2. Append to the round record: under Decisions the "Ruling: <decision> – User, <date>" lines (my
   answers and changes), under Surprises what the plan did not foresee, under Deferred minors what
   you left out on purpose; under Manual test list a draft of the slice's manual check items.
   Decisions are recorded as "User, <date>" unless work/conventions.md allows names. No absolute
   paths, user or machine names in any file; personal names only where work/conventions.md allows.
3. Write the entry that work/conventions.md names for the decision protocol, if it names one, in
   that file's own format and with its fields; leave out fields that exist only for pull requests
   (number, URL): the slice lands as a local squash commit. Update the documents that work/conventions.md lists as
   "must change with a change" (status page, help, ADR when a principle changed).
4. Tick Checks in the slice's row of work/checklist.md (replace ☐ by ☑), and Commit last, right
   before the squash commit, so the finished row lands in it. No ☐ may be left in the row: a column
   that does not apply is ticked too, with the reason under Decisions (see section 3).
5. Commit these edits on slice-NN (task commit) before merging; uncommitted edits are lost and the
   loop stops with "reported done but not ticked". Pass the message with `git commit -F <file>` (a file or
   a heredoc), never inline: Git Bash rewrites a leading `/` into a path.
6. Integrate: superpowers:finishing-a-development-branch (or by hand) – ONE squash commit on the
   integration branch named in work/conventions.md. Before the squash, in this order:
   a. merge the integration branch into slice-NN;
   b. in the main checkout, `git merge --squash slice-NN`;
   c. check the resolved files before committing: `grep '^<<<<<<<'` finds nothing, every line of both sides
      (`git show HEAD:<file>` and `git show slice-NN:<file>`) is still present, and the number of `Result:`
      lines equals ours plus theirs minus the merge base;
   d. commit in a separate command with `git commit -F <file>`, the message in the commit language and style
      of work/conventions.md, naming the slice and its finding or AC ids; resolving and committing never run
      in one command. Never push. Run the merge in the checkout of the integration branch so its
      work/checklist.md shows the tick. If the branch moved or the merge conflicts in work/checklist.md or the round record,
   keep every tick and entry from both sides. In auto mode take this option without asking, then
   remove the merged slice-NN branch and its own worktree, nothing else.
7. Two or more slices are ready now: offer parallel sessions for them (section 7) before the lines below.
End with exactly three lines:
- "Slice NN done" (or what is still open and why)
- "Ready next: …" (e.g. "07, 08, 09 – can run in parallel in separate sessions"; all done: "none –
  type /slice close")
- "Next step: start a fresh session and type /slice"
  (auto: instead "SLICE-DONE: NN" when everything is green, ticked and on the integration branch,
  else "SLICE-OPEN: NN <reason>")

## 5. Close the round ("close")
Only the open round; none → section 1. Never ask in auto mode.
1. Every slice whose field "round" names this round must be done. Otherwise list the missing ones
   and end with "ROUND-OPEN: Rnn <reason>". Likewise when the working tree is not clean or the
   integration branch is not checked out.
2. Run the full check chain from work/conventions.md on the integration branch. Red → change nothing
   and end with "ROUND-OPEN: Rnn <failing check>".
3. Write the manual test list into the round record under "## Manual test list": complete the
   drafted items, take missing items from the "manual" fields of this round's slices, and add the
   slices that have none yet, one block per slice with a manual check. One action per step;
   "Expected" names something observable; I tick "Result" or write what I saw. Write each block
   without indentation, in this form:
```
### Slice NN – <name>
Start: <command from work/conventions.md>
1. <what to click or type>
Expected: <what must be visible or happen>
Closes: <finding or AC ids>
Result: ☐
```
4. Set the first line of the round record to "Status: closed". Commit the round record in the commit
   language and style of work/conventions.md ("Round Rnn closed: <slug>"); never push.
5. List the open decisions – the entries under "## Open decisions" in the round record – as bullets
   in your closing message, never as lines starting with "NEEDS-DECISION:" (that marker belongs to
   plan runs, section 6): the next round inherits them. Tell me where the manual test list is and
   how to report: answer in chat or add to the round record; the next round starts from my notes. End with "ROUND-DONE: Rnn".

## 6. Marker lines
The loop script (.claude/scripts/slice-loop.*) reads these lines. Print each on a line of its own,
from the first column, exactly as written – no bullet, quote or code format, nothing before it:
- "PLAN: <path of the plan file>" – last line of a "plan" run
- "NEEDS-DECISION: <question>" – one per open point, before the PLAN line
- "SLICE-DONE: NN" – the slice is green, ticked and on the integration branch
- "SLICE-OPEN: NN <reason>" – anything else that stops the slice
- "ALL-DONE" – every slice of the round is done, the round is still open
- "ROUND-DONE: Rnn" – the round is closed
- "ROUND-OPEN: Rnn <reason>" – the round could not be closed

## 7. Parallel slices
Ready = not done, no branch slice-NN, every slice in "deps" done. When two or more slices are ready
(not counting the one this session works on), offer to start one separate session per ready slice,
unasked and once per run; never in auto mode (the loop script starts the next run itself).
- Offer, never start unasked: list the ready slices with name and kind (app, web, docs), say that
  slices touching the same files collide when merged, suggest at most three at once (parallel builds
  and test suites turn each other red under load; four were almost too many), and ask which ones to start.
- On a yes, start each chosen slice in its own session in this repository's main checkout, with
  your harness's tool for separate sessions if it has one (sharing this checkout, not a worktree of
  the harness: the slice creates its own worktree in section 3), on the slice's model: the field
  "model" of its entry in work/_slices.json goes into that tool's model parameter, never the model of
  this session. Without such a tool, print one ready-to-paste prompt per slice instead, each headed
  by the command line that starts it: `claude --model <model of the slice>`.
- Each prompt carries: "/slice NN"; the round, the slice's name, model, goal, scope, not-building list
  and acceptance cases from work/_slices.json; that other slices run in parallel sessions, so the merge
  in section 4 may conflict in work/checklist.md, the round record and the documents that change with
  a change, and every tick and entry of both sides stays; that it touches only its own branch and
  worktree, never pushes, and ends with the three lines of section 4.
- Never two sessions on one slice: a slice with a branch slice-NN is in progress, not ready.
