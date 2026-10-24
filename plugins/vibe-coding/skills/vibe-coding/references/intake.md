# Intake

How an input becomes a round: a findings list (A) or an idea (B). Both end in the same output: a round record, `work/_slices.json`, rendered slices, checklist rows. Ceremony scales with size: a one-line finding gets no brief, only an idea gets a brief, research runs only for new technology or packages. Formats of the files: `templates.md`.

## A. Findings list
Input: a file (a review list with ids, rule, fix, classification, effort) or chat notes from trying a build, possibly with screenshots.

1. **Capture without copying.** A structured file is referenced from `## Source`; only its ids go into the round record. Unstructured notes become rows of the intake table: `id | where (screen, file) | observed → expected | size | source`. Ids continue the repository's own scheme when it has one (see `Finding ids` in `work/conventions.md`), otherwise `F-NN`. A finding that reopens an earlier one says so: `reopens F-12`. Notes, an untracked file and a file outside the repository are not visible to fresh sessions: their findings go into the intake table (summarised when the repository is public). A copy in `work/_raw/` is only the controller's working copy – that folder is git-ignored, so slice worktrees do not contain it; the round record carries what the slices need.
2. **Group into slices** by screen or by cross-cutting theme (all message bars, all field labels). Order by dependency: shared components first, then screens, then the items the user still has to decide. One slice is about one session (1–2 hours). Trivial items go into one sweep slice. A finding classified "the user decides" becomes a `NEEDS-DECISION:` line under `## Open decisions` and is not sliced until it is answered.
3. **Acceptance per finding.** The observable fix (observed → expected) becomes a Given/When/Then line in the slice's `acceptance` field. Every UI finding also gets a `manual` check item – what to click, what to see – because automated tests alone miss what the eye sees.

## B. Idea
Input: a sentence, a concept document, screenshots, a competitor comparison.

1. **Brief** (at most one page) in the round record: purpose, users, acceptance criteria `AC-NN` as Given/When/Then with exact numbers, edge cases, errors, non-goals, NOT building, assumptions marked `[Assumption]`. When `superpowers:brainstorming` is installed, use it to sharpen the idea; otherwise ask up to five questions in one go. Existing concept documents are referenced by path, not copied.
2. **Research**, only if the brief brings technology or packages the repository does not use yet. Three short passes, one status line after each:
   - *Broad* – current stable versions and support windows, how the repository's stack handles each area of the brief, alternatives.
   - *Deep* – follow-up queries on every point that matters: breaking changes, known pitfalls, the official recommendation against community practice. For every package you would recommend: licence, paid tiers, and any sponsorship, registration or declaration a build enforces.
   - *Distill* – a decision table: decision | rests on | source.
   Append the result to `work/research.md` under `## Round Rnn – <slug>` with the subsections Versions & support, Findings by topic, Licences & terms (package | licence | paid tiers or build-enforced declarations | source), Pitfalls, Decisions, Sources. Prefer official documentation; give a URL for every source; queries contain only generic technology terms, never code, internal names or secrets; without web access write from model knowledge and mark each finding `[Unverified]`. A package that costs money or needs a licence decision goes to the user, not into `CLAUDE.md`.
   Decisions that change architecture or cost go to the user before slicing, as `NEEDS-DECISION:` lines.
3. **Slices**: vertical (each cuts through every layer needed for one observable behaviour), dependency-ordered, MVP first – the first slice is the smallest one the user can try. Each slice has an independent test: it can be verified without the slices after it. Sizing as in A.2.

## Both
- Slice numbers continue across rounds (`07`, `08`, …); slices carry the round id in the field `round`.
- A repository without a build or test command gets a harness slice first (test project, check chain, CI hook); when it changes the stack, propose it as a `NEEDS-DECISION:` line.
- Open decisions of the previous round are copied into the new record's `## Open decisions` (see `round-close.md`).

## Size classes
- **S** – one place, a few lines, no new behaviour: no slice of its own, goes into a sweep slice.
- **M** – one screen or one component with its tests: fits a slice, alone or with its neighbours.
- **L** – more than one session: split by screen, layer or acceptance criterion before it is sliced.

The examples in the templates are open lists, not checklists: take what fits the repository and the input, leave out the rest.
