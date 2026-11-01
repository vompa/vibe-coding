# Goal contract – what counts as success for this rebuild

Read this in §4 before writing the PRD. The goal contract answers the question every later phase takes for granted: **what must be true when the rebuild is done, for whom, within which limits – and how will anyone see it?** Loops and slices check against conditions; this file makes sure the conditions are the right ones and that nobody quietly moves them while building.

Why it matters in a rebuild: parity cases are themselves a stand-in for the goal. They also pin the original's flaws, and "all parity green" says nothing about what was supposed to get better. The contract separates the two: what must stay (invariants, proven by parity) and what must improve (requirements with acceptance criteria, proven by evidence).

The approach follows goal-oriented requirements engineering (KAOS, i*) as recently adapted for coding agents ("Agentic Goal Engineering", Provimedia, 2026). Its first pilot found one part clearly helpful – provenance tags cut wrong assumptions and invented requirements sharply – and two parts harmful as first designed: dropping unconfirmed points and asking as little as possible. This file keeps the first and reverses the other two.

## Rules

1. **Outcome, not solution.** "Search answers within 5 s with sources" is a goal; "use a vector database" is a solution. A solution the user names is recorded as a *constraint* only when they say it is fixed (existing infrastructure, company standard) – otherwise it is a hypothesis for the research phase.
2. **Every binding line has a provenance tag** (table below). An `AI_PROPOSED` line is never binding, however sensible it looks.
3. **Nothing unconfirmed disappears.** A point nobody confirmed stays in the contract under "Open" with its tag – it is not deleted to make the contract look finished. The PRD, slices and research may work with it as a marked `[Assumption]`, and it is listed again at approval.
4. **Ask – it pays.** Up to 8 questions in total, 1–3 per message, discovery questions before precision questions. Skip a question only when the inputs or `analysis.md` already answer it. A question belongs here only if its answer changes what counts as success – not how it is built (that is research and slicing).
5. **Questions don't lead.** No question may presuppose a technology or widen the scope the user asked for. The skill helps the user say what they want; it does not substitute its preferred solution.
6. **No pseudo-precision.** Where a number would be invented (perceived quality, design, business effect), the criterion is an agreed review with examples and a named decider, or a measurement after go-live kept apart from the product acceptance.
7. **The contract is not the plan.** No slices, tasks, classes or packages in it. Approving it approves the goal only – not the slices, spending or a deployment.

## Provenance tags

| Tag | Meaning | May be binding? |
|---|---|---|
| `USER_EXPLICIT` | the user said it | yes |
| `USER_CONFIRMED` | proposed by the skill, confirmed by the user | yes |
| `ORIGINAL` | behaviour of the original, taken from its tests, code or docs (`analysis.md`, `parity/`) | as an **invariant** (keep) – never as the target value of something the user wants improved |
| `EXTERNAL` | law, standard, contract or security requirement, with its source | yes, with source |
| `AI_PROPOSED` | the skill's proposal, not confirmed (incl. research decisions) | **never** |
| `UNKNOWN` | open, to be clarified or measured | no – stays under "Open" |

`[Assumption]` in the other plan files means: an `AI_PROPOSED` or `UNKNOWN` point the work proceeds on until the user decides.

## Seven dimensions (internal completeness check, not a form)

Fill in what the inputs and `analysis.md` already say; ask only where a gap matters.

| Dimension | Guiding question |
|---|---|
| Outcome | What should be different after the rebuild – which problem is solved then? |
| Beneficiary | For whom? Who decides what counts as success? |
| Observable behaviour | What can someone see, use or measure that is different? |
| Boundaries | What must not change, get worse or break (users, callers, data, operations)? |
| Quality | How good must it be? Which qualities pull against each other? |
| Evidence | Which observation, measurement or review will prove it? |
| Trade-offs | What is mandatory, what is negotiable when not everything fits? |

## Questions (examples, not a checklist – ask whatever else decides success for this app)

- Discovery: "Why rebuild now – what does the current app fail to do for whom?" · "What would disappoint you even if every parity test were green?" · "What must users and callers not notice at all?"
- Precision: "You said 'faster' – which screen or call, and how fast is fast enough?" · "Should the new app say openly when it cannot do something, or keep the old behaviour?"
- Boundaries: "Which data, interfaces or habits of the old app must survive unchanged?"
- Priority: "If speed and data freshness collide, which wins?"
- Evidence: "What would you need to see to call this goal reached?"

Not here: database, framework, packages, slice order, agents, retries. Those come later.

## States

`DRAFT` → `NEEDS_CLARIFICATION` (back to questions) → `READY_FOR_APPROVAL` → `APPROVED` (frozen) · later superseded by a newer approved version (the old file stays unchanged), or `CANCELLED`.
None of these means "reached". Whether a criterion is met is decided per slice by evidence (`evidence.py`, cold review) – never by the contract, and never by the agent that built it.

## Before asking for approval – check the draft

| Check | Question |
|---|---|
| Intent fidelity | Does it say what the user meant, in their words – or a reinterpretation? |
| Specific outcome | Is the target state concrete enough to recognise? |
| Completeness | Is a success-critical property, boundary or expectation missing? |
| Consistency | Do requirements contradict each other ("instant" vs. "hourly refresh")? |
| Verifiability | Does every MUST criterion have an agreed way to check it? |
| Solution neutrality | Any technical choice the user did not fix? |
| Traceability | Does every binding line have a provenance tag that allows binding? |
| Boundaries | Are invariants and non-goals named? |
| Authorisation | Is it clear who approves – and has that happened for this exact version? |

A failed check means `NEEDS_CLARIFICATION`: back to the questions, not forward to the PRD.

## Template – `rebuild/goal/contract-v001.md`

```
# Goal contract v001 – <product> (rebuild)
Status: READY_FOR_APPROVAL
> Frozen once approved. Changes: rebuild/goal/change-requests.md → new version, approved by the user.

## Intent (verbatim)
> "<the user's own words about why and what – unedited>"

## Outcome
<2–3 sentences: what is different afterwards, for whom>

## Beneficiaries & decider
<roles>; success is decided by: <role> (User, <date>)

## Requirements
| ID | Must/Should | Requirement (outcome, not solution) | Provenance |
| REQ-01 | Must | … | USER_EXPLICIT |

## Acceptance criteria
AC-01 | Must | REQ-01 | Given: … | When: … | Then: … (exact values) | Check: <test, script, review> | Evidence: <log, measurement file, report> | Checked by: cold reviewer, not the builder | Provenance: …

## Invariants (keep – proven by parity)
| ID | What must stay | Parity cases | Provenance |
| INV-01 | … | BC-03…BC-07 | ORIGINAL |

## Constraints
| ID | Constraint | Why | Provenance |

## Non-goals
- …

## Trade-offs
- When <A> and <B> collide, <A> wins. (USER_EXPLICIT)

## Open (not confirmed – stays visible)
| ID | Point | Working assumption | Provenance |
| OPEN-01 | Max. age of dashboard figures? | 60 s [Assumption] | AI_PROPOSED |

## Approval
<filled in only after the user approved this exact version in chat:
"Status: APPROVED – User, <date>" replaces the status line above>
```

`rebuild/goal/change-requests.md` (agents may append, never approve):
```
# Goal change requests
| CR | Date | Raised by (slice/phase) | What | Why | REQ/AC/INV affected | Decision (User, <date>) | New version |
```

## Approval and freeze

At the end of §5 the user sees a short summary: intent, outcome, MUST criteria, invariants, non-goals, trade-offs, open points, and every research decision that would become binding. They approve **this version** ("looks good" before they saw it is not an approval). Only then the status line becomes `Status: APPROVED – User, <date>`. From the handover on, `.claude/hooks/protect-goal.py` blocks agents from changing an approved version or approving one themselves.

Later changes: an agent appends a change request and may draft the next version (`contract-v002.md`, status `READY_FOR_APPROVAL`, the change marked). The user approves it by setting its status line themselves; the previous version stays as it is, and its status line is never edited – the highest approved version applies.
