# Changelog

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
