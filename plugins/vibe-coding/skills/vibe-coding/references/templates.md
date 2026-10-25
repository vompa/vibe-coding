# Templates

Text in `<angle brackets>` is filled in the repository's language. What the scripts and the `/slice` command read stays as written: the first line `Status: open|closed`, `Ruling:`, `NEEDS-DECISION:`, the checklist rows and the field names of `_slices.json`. Examples inside the templates are open lists, not checklists: drop what does not apply, add what does.

## work/conventions.md
A pointer file: one line per fact, the document it comes from after it (`← source`). Long rules stay in their document; this file never copies them. Created once per repository from `CLAUDE.md`, `AGENTS.md`, the README, working-method and contribution documents that `CLAUDE.md` links, protocol or changelog files, the CI workflow, formatter configuration and `git log`. The user confirms it once.
```
# Conventions – <repository>
> Pointers, not copies. One owner per fact: the document named after the arrow.

- Integration branch: <dev | main> ← <source>
- Slice branch: slice-NN, cut from the integration branch ← <source>
- Merge style: one squash commit per slice onto the integration branch; never push ← <source>
- Commit language and style: <language, prefix rule> ← <source: document or git log>
- Build: `<command>` ← <source>
- Test: `<command per project>` ← <source>
- Lint / format check: `<command>` ← <source>
- Baseline check (before every slice): `<command>` ← <source>
- Checks for a slice: one screen touched: `<its test classes plus the cross-page scan tests>`; shared code touched: `<full suite>`; never two full suites at once (the lock `.slice-loop/full-suite.lock/`, see /slice) ← <source>
- Full check chain (round close): `<commands in order>` ← <source>
- Decisions are recorded in: <file, section title format, fields it uses; fields that exist only for
  pull requests (number, URL) are left out because a slice lands as a local squash commit> ← <source>
- Must change with a change: <documents, e.g. status page, help, ADR when a principle changed> ← <source>
- Pull-request rule: <whether and when the integration branch becomes a pull request; noted only> ← <source>
- Language: UI <…>, docs <…>, tests <…> ← <source>
- Privacy rule for names in files: <names allowed | only "User, <date>"> ← <source>
- Start the app for manual testing: `<command>` ← <source>
- Work folder: work/
- Finding ids: <scheme or F-NN> ← <source>

## Conflicts between documents
<document A says …, document B says … – listed for the user, never resolved silently>
```
In a repository without rules the lines say `default` as their source: `main`, squash, `"User, <date>"`. Extend the repository's rules, never replace them.

## work/session-hints.md
Repository-specific hints for slice sessions, grown round by round: the first round writes what the repository's rules and tooling already teach, later rounds append what the previous round learned and change no existing bullet. `/slice` reads it in section 2 and the parallel prompts name it. The bullets below are an open list of examples, not a checklist: keep what applies, add what the repository needs.
```
# Hints for slice sessions
Repository-specific experience for the sessions that work a slice. They add to `.claude/commands/slice.md` and `work/conventions.md`; every round appends what it learned.

- <tool or hook that blocks a command until facts are stated, and how to satisfy it once>
- <shell quirk: path rewriting, line endings, quoting of commit messages>
- <the command that needs a long timeout or a background run, and where its log goes>
- <files that must change together, or must never be touched by a slice>
```

## work/rounds/Rnn-<slug>.md
The round record. Round ids are fixed-width (`R01`, `R02`, … `R99`), so the glob `work/rounds/R01-*.md` in the slice prompt is unambiguous. The first line is `Status: open`, set to `Status: closed` at round close; the loop reads only that line. Keep the section that fits the intake (Intake table for findings, Brief for ideas) and drop the other.
```
Status: open

# Round Rnn – <slug>

## Source
<tracked findings file (path) and its marking format ("done in slice NN" in the file's own style), notes from <date>, or the idea in one sentence;
concept documents by path – referenced, not copied>

## Brief          (ideas only, ≤ 1 page)
Purpose: <…>
Users: <…>
- AC-01 Given <…> When <…> Then <…>    (exact numbers)
Edge cases: <…>
Errors: <…>
Non-goals: <…>
NOT building: <…>
Assumptions: [Assumption] <…>

## Intake         (findings only)
| id | where | observed → expected | size | source |
|---|---|---|---|---|
| F-01 | <screen, file> | <what happens> → <what should happen> | S | <review list, notes> |
| F-02 | <…> | <…> | M | reopens F-01 |

## Slices
| Slice | Name | Findings / ACs |
|---|---|---|
| NN | <name> | <ids> |

## Decisions
Ruling: <decision> – User, <date>

## Surprises
<what a plan did not foresee>

## Deferred minors
<what was left out on purpose, with the slice>

## Open decisions
NEEDS-DECISION: <question>
NEEDS-DECISION: <question> (from Rnn)

## Manual test list    (drafted per slice, completed at round close; format: round-close.md)
### Slice NN – <name>
```
`size` is S, M or L (see `intake.md`). Finding ids continue the repository's own scheme; `F-NN` otherwise.

## work/checklist.md
```
# Checklist
| Slice | Plan | Tests red | Green | Checks | Commit |
|---|---|---|---|---|---|
| NN name | ☐ | ☐ | ☐ | ☐ | ☐ |
```
One row per slice; numbers continue across rounds. The agent replaces `☐` by `☑` as each step is done; a slice is done when its row has a `☑` and no `☐`. Manual acceptance is never a column: the human works through the round record's manual test list.

## work/_slices.json
Input for `scripts/render_slices.py` (`python3 scripts/render_slices.py work/_slices.json work/slices --lang <en|de>`). The JSON below is an example – replace its entries with the round's own slices.
```json
[
  {
    "nr": "07", "slug": "message-bars", "name": "Message bars",
    "goal": "Every message bar shows severity, text and a way to dismiss it the same way.",
    "round": "R01", "source": "R01 – F-03, F-09",
    "deps": "–", "model": "sonnet",
    "scope": ["Shared MessageBar component", "Replace the bars on the order and customer screens"],
    "mirror": ["src/components/Dialog.tsx:12 – how shared components take their variants"],
    "not_building": ["Toast notifications"],
    "acceptance": [
      "Given a failed save When the order screen shows the error Then the bar is red, names the field and can be dismissed",
      "Given a dismissed bar When the screen is reloaded Then the bar is gone"
    ],
    "manual": ["Open an order, clear the customer, save: the red bar appears; dismiss it with the cross"],
    "non_goals": "New wording of the messages"
  },
  {
    "nr": "08", "slug": "customer-list", "name": "Customer list",
    "goal": "The list shows the filter state and an empty-state message.",
    "round": "R01", "deps": "07", "model": "haiku",
    "scope": ["Filter chips", "Empty state"],
    "non_goals": "Paging"
  }
]
```
Required: `nr`, `slug`, `name`, `goal`, `deps`, `scope`, `non_goals`. Optional text: `round`, `source`, `model` (the cheapest model tier that does the slice reliably – `haiku`, `sonnet` or `opus`, see `intake.md`; the loop passes it as `claude --model`, `/slice` starts parallel sessions on it, and a slice without it runs on the caller's default model – so set it on every entry). Optional lists: `mirror`, `not_building`, `acceptance` (Given/When/Then, rendered as checkboxes in the Definition of Done), `manual` (rendered as `Manual:` checkboxes). Unknown fields are ignored. `nr` is a string of at least two digits and continues across rounds (after the highest number in `rebuild/_slices.json` when a rebuild repository continues here). `deps` lists slice numbers or `–`. `round` is the id of the round record. Set `round` on every entry in a vibe-coding repository – a slice without it is invisible to `/slice status` and to the round close. Keep `"nr"` and `"deps"` quoted in every entry: the loop reads them as text.

## CLAUDE.md (only for a repository without one)
Lean; an existing `CLAUDE.md` is never replaced, its facts go into `work/conventions.md` by pointer.
```
# CLAUDE.md – <repository>
<purpose in 2–3 sentences>. How this repository works: work/conventions.md. The open round: work/rounds/.

## Hard rules
- <the few rules that must never break, e.g. no secrets in files, no new packages without asking,
  no test weakened or skipped, no absolute paths or machine names in files>

## Commands
- Build `<…>` · Test `<…>` · Lint / format check `<…>` · Run `<…>`

## Way of working
- One slice per session: read the slice file → plan with assumptions → failing tests → the minimum
  to get green → Definition of Done → record decisions.
- Task commits on slice-NN are fine; one squash commit per slice onto <integration branch>; never push.
- Unclear → ask. A marked assumption beats a silent invention.
```
