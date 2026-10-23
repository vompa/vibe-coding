# Template: prompt for the target-stack research

Use this when delegating SKILL.md §5 to a subagent (or a deep-research skill). Replace the `<…>` placeholders. Fill `<areas>` from the headings and features in `analysis.md` – that keeps the research tied to this app without narrowing it to a few hand-picked topics.

```
Research how to build <app purpose in one sentence> on <target stack> following current best practice.
The app is being rebuilt from <source stack>; its areas are: <areas from analysis.md>.

Work in three passes and write everything to <path>/research.md in <user's language>:

1. BROAD – collect everything relevant before judging any of it:
   current stable versions and support windows, recommended project structure,
   how architecture rules are enforced, testing and approval/snapshot tooling,
   and the target-stack way of handling each area above.
   These are starting points, not a closed list: add every topic you find that a
   rebuild of this app on this stack should know about.
2. DEEP – from what pass 1 found, derive follow-up queries and go as deep as needed
   on each point that matters for this app: breaking changes, known pitfalls,
   migration guides from <source stack>, official recommendations vs. community practice.
3. DISTILL – end with "## Decisions for this rebuild": one line per decision,
   the finding it rests on, and its source. Mark anything not backed by a source [Unverified].

Rules:
- Prefer official documentation and release notes over blog posts; give a URL for every source.
- Search queries contain only generic technology terms – never code, internal names,
  customer data or secrets from the original.
- Do not design slices or write code; this is input for the plan.

Structure of research.md:
## Goal & scope
## Versions & support
## Findings by topic        (one subsection per topic, sources inline)
## Pitfalls & breaking changes
## Decisions for this rebuild
## Sources

Start your answer directly with the file content – no preamble. Your answer is saved
by the orchestrator; it is not shown to the end user.
```

## Notes
- The topic list in pass 1 is deliberately marked as open. Agents that get a short list of named topics tend to study exactly those and skip the rest.
- If no web access is available, write the same structure from model knowledge and mark every finding `[Unverified]`; tell the user in the final summary.
- After it returns, spot-check 2–3 version numbers or claims against their sources before they go into `CLAUDE.md`.
