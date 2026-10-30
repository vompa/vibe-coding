---
description: Work the current round slice by slice – next slice, a given slice, status, or close the round
argument-hint: "[status | NN | close | quick <finding>] [plan] [auto | parallel] [direct]"
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
  work/_slices.json), state (done / in progress / ready to merge / ready / blocked by …; "in progress" = not done,
  but a branch slice-NN exists or the row has a ☑; "ready to merge" = a branch slice-NN whose row is ticked
  through Checks),
  then the round's check level and its next milestone (section 4, step 1), the number of open decisions in the round record, one line for a held .slice-loop/full-suite.lock
  (owner, since when) and one line "Ready now: …" – the ready slices, each with the slices it shares a path of
  its field "files" with ("70 shares src/EntryPreview.cs with 69"). Two or more
  ready: offer parallel sessions (section 7). Stop there.
- "close" → section 5.
- "quick" → section 8.
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
  slice, full check chain), check level, protocol file, documents that must change with a change, language,
  privacy rule
- the open round record work/rounds/Rnn-*.md – source, brief, decisions so far (a check level and milestones for
  the round), open decisions
- work/slices/NN-*.md – goal, source, model, check level, scope, patterns to mirror, NOT building, prompt,
  Definition of Done, non-goals
- CLAUDE.md (and AGENTS.md when present) – the repository's hard rules
- work/session-hints.md – the repository's hints for slice sessions, when it exists
- what the slice's Source names: the findings file or concept document (the round record only
  references it), work/research.md when the slice cites it
Before you change anything the working tree must be clean and the integration branch checked out;
otherwise say what to do (auto: "SLICE-OPEN: NN <reason>"). Generated files you did not touch that show as changed
or missing usually come from another session's build in this checkout: wait until no build or test process of
another session runs (at most 10 minutes), then look again; leave those files alone. Then create the slice's worktree
(recipe in section 3) and run the baseline check from work/conventions.md there, before your first change (a full suite
takes the lock of section 4): a build in the main checkout also picks up files of other slices' worktrees. Red → change nothing and ask whether to fix that first
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

Rules for plan and build (both paths):
- Assumptions: one numbered round, a recommendation per point, worded so that "yes" takes them all. Facts come
  from code and docs; only decisions are asked. An unambiguous task skips the round.
- Seams: the plan names the seams the tests hit; the review focus says per seam what the test catches and what it misses.
- Tests: expected values come from an independent source, not computed like the code (that is tautological).
  Red counts when the test checks exactly the fault or requirement. Red means the new test fails against the code
  before the change (stash the change, or run it in a second worktree on the integration branch); a test made to fail
  by a wrong expectation is not red – say this in every brief to a subagent. Write that red run to the checks proof
  (section 4) with its exit code and the SHA it ran on; tick Tests red only with such a line, so test and code are not
  written in one go. Run the type check and the single test file often, the checks of your check level (section 4)
  once at the end – a full suite once at the end only where the level asks for one; refactor after green.
- A screen's behaviour is tested through the real input (click, key, focus) where the repository's test harness can,
  not only by setting view-model state: a click path that breaks stays green otherwise.
- Generated outputs (screenshots, snapshots, generated clients): commit those the slice's change explains, reset the rest.
- Check scope beyond the slice's own screen: a rule added to an endpoint, a service or a base class → search every
  caller and run their tests, or (from check level 2) the full suite before "green"; a change to a shared control or base → run its own tests
  first, before changing it; a change to key bindings, focus or tab order → add the repository's focus-order tests. Every timeout or wait you raise in a test goes into
  the protocol entry (section 4) with its reason and the measured time.
- New finding ids: take them from the slice's reserved range (field "ids" in work/_slices.json, column "New ids" of
  "## Slices"). Without one, read the ids used on the integration branch (round record and findings file) and take
  the next free ones; after the merge of step 6a, renumber your own new ids that collide.
- Stop only for a real blocker: a missing dependency, a contradiction to the plan, or an ambiguity that would
  produce wrong code under a wrong assumption. Trivia the code answers, style questions (follow existing patterns)
  and anything a test can settle go on; no "subagent or inline?" question after the plan.
Debugging (a slice that fixes a fault): start with a command that shows the fault red, before any hypothesis; list
three to five ranked hypotheses before testing one; put the regression test at a fitting seam – a missing seam is itself a finding.

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
and the reason goes into the round record under Decisions as a Build decision (section 4, step 2), so the row has no ☐ left.

Keep me posted: one short status line at least every few minutes (what finished, what runs next); with `auto` or
`parallel`, only the marker lines of section 6.
Long reports of subagents go to work/_raw/ (git-ignored), not into the chat.

## 4. Close the slice
Do 1–4 on slice-NN, so they land in the same commit as the code.
1. Run the checks that work/conventions.md names for a slice (always including every command of the baseline
   check); check the Definition of Done in the slice file, including "no test weakened or skipped" and "no new
   package without approval".
   Check level (how often and how thoroughly a slice is checked): 1 to 5, default 3. It comes from the line
   "- Check level" of work/conventions.md; the round record may set another level and name its milestones under
   Decisions, and the slice file's "Check level" sets one for this slice only (the most specific one wins). "Own
   checks" are the smallest fitting tier of work/conventions.md's checks for a slice; "shared code" is a shared UI
   control, style or the shell, middleware, a database trigger, or a new rule on an endpoint, service or base class.
   The baseline check runs on every level.
   1. Own checks without the scan tests; full suites stay out of the slice; the full check chain only at round close.
   2. Own checks including the scan tests; the full suite of an area only when the slice touches shared code; the full
      check chain only at round close.
   3. (default) Like 2, plus `slice-loop -Merge -Verify` at the round's milestones and at round close, not after
      every group.
   4. Like 3, plus `-Merge -Verify` after every group, and after merging the integration branch (step 6a) the full
      suites of the areas the integration branch changed since the old base.
   5. The full check chain in every slice on the tip and after every merge of the integration branch; `-Merge -Verify`
      after every group.
   A red test is first re-run alone; the whole suite runs again only when it stays red. A red test that is green when run
   alone or in a second unchanged run is load, not a regression: note it under Surprises as "load, not a fault" (test, both
   runs) and go on. Check commands never end in `| tail` or another pipe inside an `&&`
   chain: the pipe hides the exit code, so write the output to a file and read its exit code.
   The run that proves the slice is the last one: on the final tip, after steps 2–5 and the merge of step 6a when it runs. A run
   before a later commit must be repeated, so earlier runs cover what you changed and the full set runs once, at the end.
   Stopping a background check with the harness's stop tool leaves its child processes (test runners, builds) running:
   find them by the worktree path in their command line and end them, or the next build finds its files locked.
   Checks proof: write each check you run to .slice-loop/slice-NN.checks in the main checkout (the parent of
   `git rev-parse --git-common-dir`), one line per check: `<exit code> <commit SHA> <command>` – the command exactly
   as work/conventions.md writes it, the SHA of `git rev-parse HEAD` on slice-NN when it ran. Always append, so a stale
   run of an old session cannot wipe the proof. The merge queue reads only the lines with the branch tip, the last one
   per command; it squashes when each of them is green and every baseline command is listed.
   Review the whole branch diff with a fresh, read-only reviewer (a subagent that did not write the code), on two axes, kept apart: specification (every finding cites the plan line; ask about unrequested
   scope) and standards (the repository rule beats the general rule; what tools enforce stays out). The review
   also checks that every raised timeout or wait in a test is recorded with its reason.
   Full-suite lock (also for the baseline check of section 2): before a command that work/conventions.md names a full
   suite, take .slice-loop/full-suite.lock in the main checkout (the parent of `git rev-parse --git-common-dir`) with
   `mkdir` (PowerShell: `New-Item -ItemType Directory` without `-Force`), which fails when it exists, and write `owner`
   inside: `slice NN` and an ISO-8601 time. Remove it right after the suite, red or green. A lock held by a slice whose
   branch slice-MM exists and whose time is under 60 minutes old: retry every minute for at most 30 minutes. Any other
   lock (branch gone, older, or the wait ran out) is reported with owner and time (auto: `SLICE-OPEN: NN lock held by
   slice MM since <time>`); leave it untouched.
2. Append to the round record: under Decisions one line per decision in one of two formats – "Ruling: <decision> –
   User, <date>" for my answers and changes, "Build decision (slice NN): <decision> – Claude, <date>" for what you
   decided while building (a column that does not apply, a point the code settled); the merge queue refuses a slice
   that adds a line in another format there. Under Surprises what the plan did not foresee, under Deferred minors what
   you left out on purpose. Every question for me is a "NEEDS-DECISION: <question>" line under Open decisions,
   not only a note elsewhere. Under Manual test list insert the slice's block in slice-number order, in the
   format of section 5 (steps 1..n, one Expected: per step, one Closes: and one Result line per block).
   When "## Source" names a tracked findings file, mark the slice's ids there as "done in slice NN" in the
   marking format the record names, before the squash, and add new findings there in the file's own format.
   Decisions are recorded as "User, <date>" unless work/conventions.md allows names. No absolute
   paths, user or machine names in any file; personal names only where work/conventions.md allows.
3. Write the entry that work/conventions.md names for the decision protocol, if it names one, in
   that file's own format and with its fields; leave out fields that exist only for pull requests
   (number, URL): the slice lands as a local squash commit. Update the documents that work/conventions.md lists as
   "must change with a change" (status page, help). Write an ADR only when the decision is hard to reverse,
   would surprise without context or settled a real conflict of goals; everything else is a Ruling in the round record.
4. Tick Checks in the slice's row of work/checklist.md (replace ☐ by ☑), and Commit last, right
   before the squash commit, so the finished row lands in it. No ☐ may be left in the row: a column
   that does not apply is ticked too, with the reason under Decisions (see section 3).
5. Commit these edits on slice-NN (task commit) before merging; uncommitted edits are lost and the
   loop stops with "reported done but not ticked". Pass the message with `git commit -F <file>` (a file or
   a heredoc), never inline: Git Bash rewrites a leading `/` into a path.
   With `auto` or `parallel`, do 6a, then stop here: write the squash message (commit language and style of
   work/conventions.md, naming the slice and its ids) to .slice-loop/slice-NN.msg in the main checkout (the parent
   of `git rev-parse --git-common-dir`), check that the checks proof names the branch tip, do not merge, leave
   Commit at ☐; as the very last write, put the tip's SHA (`git rev-parse HEAD`) into .slice-loop/slice-NN.ready in the
   main checkout, and end with the last line SLICE-READY: NN. The merge queue squashes only a slice whose ready file
   names its tip, so it leaves a session alone while its last checks run.
   Before SLICE-READY, all of these hold – check each one, the queue leaves the slice behind otherwise:
   1. the slice's row in work/checklist.md on slice-NN is ticked through Checks (Commit stays ☐);
   2. .slice-loop/slice-NN.msg exists in the main checkout;
   3. .slice-loop/slice-NN.checks has a green line on the branch tip for every check and every baseline command;
   4. everything is committed on slice-NN (`git status` in the worktree is clean);
   5. .slice-loop/slice-NN.ready holds the tip's SHA – write it again after any later commit or merge on slice-NN.
   The orchestrating session reacts only to SLICE-READY, NEEDS-DECISION and SLICE-OPEN, so report nothing else: a
   fault found or a decision needed is said at once with its marker; "suite still running" is no report – background
   checks wake you anyway. Only when the harness ends your turn while checks still run, end with the one line
   "SLICE-WAIT: NN <what runs>" and no status text – not with SLICE-READY, and not with "I wait for …" without the marker.
   without both arguments go on with step 6.
6. Integrate: superpowers:finishing-a-development-branch (or by hand) – ONE squash commit on the
   integration branch named in work/conventions.md. Before the squash, in this order:
   a. merge the integration branch into slice-NN only when needed: `git merge-tree --write-tree <integration branch>
      slice-NN` reports a conflict, or `git diff --name-only <old base> <integration branch>` (old base: `git merge-base
      slice-NN <integration branch>`) lists a file the slice also changes, documents (*.md) and work/ aside. Otherwise
      keep your tip and its proof: the queue squashes a slice cut from an older integration branch as it is, and leaves
      it behind ("integration branch moved and touches <files>") when such a file turns up later – then merge here.
      After a merge, repeat the baseline check and your own checks on the merged tip before the squash or SLICE-READY;
      full suites only when your check level asks for them (step 1) or the overlap lists a file; the interplay of
      slices is covered by `-Merge -Verify` as the level asks; append these runs to the checks proof (the merged tip);
   b. in the main checkout, `git merge --squash slice-NN`;
   c. check the resolved files before committing: `grep '^<<<<<<<'` finds nothing, every line of both sides
      (`git show HEAD:<file>` and `git show slice-NN:<file>`) is still present, and the number of `Result:`
      lines equals ours plus theirs minus the merge base;
   d. commit in a separate command with `git commit -F <file>`, the message in the commit language and style
      of work/conventions.md, naming the slice and its finding or AC ids; resolving and committing never run
      in one command. Never push. Run the merge in the checkout of the integration branch so its
      work/checklist.md shows the tick. If the branch moved or the merge conflicts in work/checklist.md or the round record,
   keep every tick and entry from both sides; lines both sides only added (protocol entries, findings) keep both,
   a table row both changed (the round's status row) becomes one row with both changes. In auto mode take this
   option without asking, then remove the merged slice-NN branch and its own worktree, nothing else.
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
3. Write the manual test list into the round record under "## Manual test list": first check the drafted
   blocks – in slice-number order, steps numbered 1..n, exactly one Expected: per step, exactly one Closes: and
   one Result: per block. A block that breaks this is not repaired: end with "ROUND-OPEN: Rnn manual test list:
   <slice and problem>". Then add the slices that have no block yet, taking the items from the "manual" fields of
   this round's slices, one block per slice with a manual check, in slice order. One action per step;
   "Expected" names something observable; I tick "Result" or write what I saw. Write each block
   without indentation, in this form:
```
### Slice NN – <name>
Start: <command from work/conventions.md>
1. <what to click or type>
Expected: <what must be visible or happen>
2. <next step>
Expected: <what must be visible or happen>
Closes: <finding or AC ids>
Result: ☐
```
4. Set the first line of the round record to "Status: closed". Commit the round record in the commit
   language and style of work/conventions.md ("Round Rnn closed: <slug>"); never push.
5. List the open decisions – the entries under "## Open decisions" in the round record, plus every place
   outside that section that leaves a decision to me ("user decides", "<name> decides", "<Name> entscheidet",
   "decision pending", "to be decided") – as bullets in your closing message, never as lines starting with
   "NEEDS-DECISION:" (that marker belongs to plan runs, section 6): the next round inherits them. Tell me where the manual test list is and
   how to report: answer in chat or add to the round record; the next round starts from my notes.
6. Leftover worktrees and branches: `git worktree list` and the branches slice-*, agent-* and worktree-* whose work is
   on the integration branch – this step lists them with their tip SHA. Outside auto mode, offer to remove the safe ones: only
   without changes (clean worktree, no commit missing from the integration branch); write each tip SHA into the
   round-close message first, remove links first (junctions, symlinks such as node_modules – git follows them and
   empties their target), then `git worktree remove`, then the branch. In auto mode only list them.
   End with "ROUND-DONE: Rnn".

## 6. Marker lines
The loop script (.claude/scripts/slice-loop.*) reads these lines. Print each on a line of its own,
from the first column, exactly as written – no bullet, quote or code format, nothing before it:
- "PLAN: <path of the plan file>" – last line of a "plan" run
- "NEEDS-DECISION: <question>" – one per open point, before the PLAN line
- "SLICE-DONE: NN" – the slice is green, ticked and on the integration branch
- "SLICE-READY: NN" – branch committed, checklist ticked through Checks, squash message and ready file written; waits for the merge queue
- "SLICE-WAIT: NN <what runs>" – the harness ends the turn while checks still run in the background: the slice is still
  running, not done; one line, no report; the loop checks back in this session, an orchestrating chat does not answer it
- "SLICE-OPEN: NN <reason>" – anything else that stops the slice
- "ALL-DONE" – every slice of the round is done, the round is still open
- "ROUND-DONE: Rnn" – the round is closed
- "ROUND-OPEN: Rnn <reason>" – the round could not be closed
- "QUICK-DONE: <commit>" – a quick fix (section 8) is committed on the integration branch

## 7. Parallel slices
Ready = not done, no branch slice-NN, every slice in "deps" done. When two or more slices are ready
(not counting the one this session works on), offer to start one separate session per ready slice,
unasked and once per run; never in auto mode (the loop script starts the next run itself).
- Offer, never start unasked: list the ready slices with name and kind (app, web, docs), name the ones that
  share a file (field "files" in work/_slices.json: equal paths or a folder prefix) – those run one after the
  other, not side by side –, suggest at most two at once (three sessions on one machine made unrelated tests red
  under load and queued at the full-suite lock), and ask which ones to start.
- On a yes, start each chosen slice in its own session in this repository's main checkout, with
  your harness's tool for separate sessions if it has one (sharing this checkout, not a worktree of
  the harness: the slice creates its own worktree in section 3), on the slice's model: the field
  "model" of its entry in work/_slices.json goes into that tool's model parameter, never the model of
  this session. Without such a tool, print one ready-to-paste prompt per slice instead, each headed
  by the command line that starts it: `claude --model <model of the slice>`.
- A session cannot start a session on a stronger model than its own: the tool silently falls back. So the
  orchestrating session (the one that only dispatches and squashes) runs on `opus` at low effort – the strongest tier
  any slice may name, cheap because it writes no code. After each start, check the model it actually runs on with the
  harness's session tool and switch it to the slice's model when it differs.
- Each prompt is short: the line "/slice NN parallel auto", then the slice's goal and acceptance cases from
  work/_slices.json in a few lines, and one line with the facts a hook asks for before a session's first command
  or edit (the request in one sentence, what the command checks) when the repository runs such a hook. When the
  tool asks for a background text, give two or three sentences: round, slice, branch slice-NN, what done looks like.
  Nothing else is pasted: the command reads work/conventions.md,
  work/session-hints.md when it exists, the round record and the slice file itself, works only on its own branch
  and worktree, and ends with SLICE-READY: NN or SLICE-WAIT; the squash happens in the main checkout through the merge
  queue (`slice-loop --merge`) or the running loop.
- `slice-loop -Merge` (`--merge`) squashes the ready slices. Add `-Verify` (`--verify`) – the full check chain once on
  the integration branch – as the check level asks (section 4, step 1): at the round's milestones on level 3, after every
  group on levels 4 and 5; round close runs the chain on every level. A desktop
  harness may refuse to start sessions from background events; for long autonomous runs suggest `slice-loop -Parallel`.
- The orchestrating session acts only on SLICE-READY (run the queue), NEEDS-DECISION (ask me) and SLICE-OPEN (look
  at the reason); a SLICE-WAIT needs no answer. `-Merge` lists a slice whose session has not reported ready yet as
  "not ready yet" and still exits 0; a non-zero exit means a slice was left behind for a real reason.
- Never two sessions on one slice: a slice with a branch slice-NN is in progress, not ready.

## 8. Quick fix ("quick <finding>")
For a small change outside a slice, typically after a round is closed (a finding from the manual test, a review of a
screen). Too big for one session or a decision needed → say so and propose it for the next round instead.
1. Section 2 first: read, clean tree, baseline check. Work on the integration branch or a branch quick-<slug>.
2. Record the finding with the next free id (section 3) in work/quick-fixes.md (create it with the header
   `| Date | Id | Finding | Test | Commit |`), and in the findings file when the open or last round names one.
3. A failing test first (red as in section 3), then the minimum to get green; the check scope of section 3 applies.
4. The full check chain from work/conventions.md, green; the protocol entry work/conventions.md names (section 4, 3)
   and the documents that must change with a change.
5. One commit on the integration branch with `git commit -F <file>`; fill in the row's Commit cell. Never push.
End with "QUICK-DONE: <short commit SHA>". The next round's intake reads work/quick-fixes.md.
