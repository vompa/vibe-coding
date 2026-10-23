# Changelog

## 2.2.0 – 2026-10-23
- New phase §5 "Target-stack research" → `vibe-plan/research.md`: state the goal openly, research broad first, derive follow-up queries and go deep, then distill "Decisions for this rebuild" with sources. Guardrails (`CLAUDE.md`), slicing and the rebuild-vs-refactor assessment now build on it instead of training-data defaults. New template `references/research-prompt.md`; fallback without web access marks findings `[Unverified]`. Search queries never contain code, internal names or secrets from the original.
- New rule: examples in prompts are open lists, not checklists – agents take named examples literally. The explorer prompt now says so explicitly.
- New section "Keep the user posted": long steps are announced with a rough duration, no silent stretch longer than ~5 minutes, long work is cut into pieces that each report progress (counts of topics, sources, tests). The research runs as three separate passes (broad, deep, distill) with a status line after each; the research agent appends each finished topic to `research.md` and logs it in `_raw/research-progress.md`.
- Status lines start with an overall percentage, estimated from fixed phase weights (inventory 5, analysis 25, PRD 10, research 20, guardrails 5, slicing 15, parity 15, handover 5) plus counted units inside the running phase; monotonic, never 100 % before delivery.
- Where the plan goes, in this order: local git repo (full path asked and shown back), GitHub if local is not possible, files only on request. Remote file tools that may not write `.git` are handled by building the repo in a scratch folder and copying `.git` in – no delete rights on parent folders.
- Handover ends with the location in full, how to start slice 00, and a ready-to-paste superpowers command (after the repo, or as an example below the files); the skill never installs the plugin.
- Slice prompt reads `research.md` and looks up current docs for any library or pattern it does not cover.
- Phases after the PRD renumbered (Guardrails §6, Slicing §7, Parity §8, Handover §9).

## 2.1.1 – 2026-10-23
- Plugin moved to `plugins/vibe-rebuild/`; developer tooling (`tests/`, CI) is no longer part of the shipped bundle. Install command unchanged.
- Directory listing fields: icon, documentation, support, privacy policy and terms (MIT license) links; added PRIVACY.md and a plugin README.

## 2.1.0 – 2026-10-23
- New section "Keep the chat clean": subagent reports and `<task-notification>`/`<result>` markup are never echoed into the chat; reports are saved to `vibe-plan/_raw/<area>.md`, the chat gets at most one status line per step and a short final summary.
- Explorer prompt: answer starts directly with the first heading, no preamble; the report is marked as orchestrator-only.
- Inputs: target stack is asked with concrete options, avoiding a second question round.

## 2.0.0 – 2026-10-23
- Skill, references, scripts, README and manifests fully in English.
- The generated plan now follows the user's language (default English) instead of always German.
- Trigger description rewritten in English; trigger test set now mostly English with German cases kept for multilingual coverage.

## 1.0.0 – 2026-10-23
- First published version (German).
- Phases: inventory, parallel analysis, PRD/glossary, CLAUDE.md, slicing, parity, handover.
- Scripts `inventory.py` and `render_slices.py`; templates for explorer prompt, PRD, CLAUDE.md, parity harness.
- Lessons from the trial run on OPCAgentSample: existing spec as primary source, three kinds of parity cases, spot-checking agent numbers, LLM parts only with a fake model, rebuild-vs-refactor assessment.
