# Changelog

## 2.3.0 – 2026-10-24
Lessons from the end-to-end run on [mcp-time-net](https://github.com/vompa/mcp-time-net) (plan with 2.2.0, all 5 slices via `/rebuild`, published as a NuGet tool).
- **Hands-off rebuild:** new `assets/rebuild-loop.ps1` and `assets/rebuild-loop.sh`, copied to `.claude/scripts/` in the target repo. They run each slice in a fresh headless Claude session (`claude -p --session-id`, then `--resume` after approval), stop for plan approval (Enter / change request / `q`), and continue with the next ready slice until all are ticked. `-Yes`/`--yes` approves automatically but still stops on `NEEDS-DECISION` or red slices; `-Parallel`/`--parallel` builds independent slices side by side (experimental); `-DryRun`/`--dry-run` lists ready slices. Never pushes. Tested with a fake `claude` CLI in CI (`tests/rebuild_loop_test.py`).
- `/rebuild` gains `plan` and `auto` and the marker lines `PLAN:`, `NEEDS-DECISION:`, `SLICE-DONE:`, `SLICE-OPEN:`, `ALL-DONE` for the loop; when every slice is done it offers to turn the plan README into the product README.
- Commit rule made explicit: task commits on `slice-NN`, one squash commit per green slice on `main`.
- Guardrails: one architecture test per dependency rule (mapping rule → test in `CLAUDE.md`); slice 00 proves every quality gate turns red on a deliberate violation (build flags can skip rule groups such as naming rules) and runs the format/lint check in CI; approved packages listed with their licence.
- Research: licence and terms of every recommended package (some packages break the build until a sponsorship declaration is made); a short **probe** in the target stack for transport, packaging, start-up and logging, because reading-only research found no pitfalls while the slices hit several; new sections "Licences & terms" and "Findings per slice".
- Plans and closing: slice prompts ask for "Assumptions (confirm on approval)" and a "Review focus"; deviations from the plan, from the original and undocumented findings are recorded in fixed places; PRD template gets an edge-case checklist per input (range and overflow, wrong type, missing/null/empty, control characters, several invalid inputs at once).
- Privacy: no absolute paths, user or machine names, private e-mail addresses or personal names in any file (the full path appears only in the chat handover; decisions are "User, <date>"); the commit identity is checked before the plan's first commit; the final check scans committed files.
- README: new "Origin" section with the full link to the original and the vibe-rebuild version; checklist format (`| NN …` rows with ☐/☑) fixed so command and script can read it; `*.sh text eol=lf` for the copied bash script.

## 2.2.0 – 2026-10-23
- New phase §5 "Target-stack research" → `rebuild/research.md`: state the goal openly, research broad first, derive follow-up queries and go deep, then distill "Decisions for this rebuild" with sources. Guardrails (`CLAUDE.md`), slicing and the rebuild-vs-refactor assessment now build on it instead of training-data defaults. New template `references/research-prompt.md`; fallback without web access marks findings `[Unverified]`. Search queries never contain code, internal names or secrets from the original.
- New rule: examples in prompts are open lists, not checklists – agents take named examples literally. The explorer prompt now says so explicitly.
- New section "Keep the user posted": long steps are announced with a rough duration, no silent stretch longer than ~5 minutes, long work is cut into pieces that each report progress (counts of topics, sources, tests). The research runs as three separate passes (broad, deep, distill) with a status line after each; the research agent appends each finished topic to `research.md` and logs it in `_raw/research-progress.md`.
- Status lines start with an overall percentage, estimated from fixed phase weights (inventory 5, analysis 25, PRD 10, research 20, guardrails 5, slicing 15, parity 15, handover 5) plus counted units inside the running phase; monotonic, never 100 % before delivery.
- Where the plan goes, in this order: local git repo (full path asked and shown back), GitHub if local is not possible, files only on request. Remote file tools that may not write `.git` are handled by building the repo in a scratch folder and copying `.git` in – no delete rights on parent folders.
- Repo layout: only `CLAUDE.md`, `README.md` and `.gitignore` at the root; all plan documents in `rebuild/` (detailed per-slice plans in `rebuild/plans/`), so the root stays free for `src/` and `tests/`. Slice prompts and templates point to the new paths.
- Not a copy: the original is the template, not the yardstick. The rebuild keeps the business contract and the interface contract external callers depend on, and improves everything else based on legacy findings and research. Parity kinds reworded accordingly (implementation-bound includes message wording – cases pin the information, not the exact text); PRD section "Legacy bugs fixed on purpose" becomes "Improvements on purpose". Taglines in READMEs and manifests updated.
- Environment-aware handover: in Claude Code on the user's machine the repo (incl. `.git/` and `.claude/`) is written directly; in a cloud session linked to the machine, plain files go through file transfer and `.git/`/`.claude/` are created via the device shell (scratch repo, then copy; `core.filemode=false` on Windows mounts); without access, GitHub or files. A final check confirms commit, clean status and `/rebuild`.
- Slice dependency graph in the README as Mermaid plus rendered images, sized by plan: one compact top-down diagram up to ~6 slices; otherwise a ~2:1 lane diagram for the README and a portrait version for the side panel.
- `render_slices.py --lang en|de`: slice files and prompts in the plan's language.
- Self-contained plans: the rebuild never needs the original's code or a running original. Parity cases are written into `rebuild/parity/` with exact expected values from the original's tests and code; recording against a running original is gone, and the inputs round no longer asks whether the original runs locally. Free prose such as description texts is rewritten from the PRD, not copied.
- New `/rebuild` command (`references/rebuild-command.md`) written to `.claude/commands/rebuild.md` in every target repo: picks the next ready slice from the dependency graph and checklist, or `/rebuild NN`, `/rebuild status`, `direct`; uses superpowers when installed, the slice prompt otherwise; ends each slice with the next ready ones.
- README gets a full "Getting started" section (`references/getting-started.md`): prerequisites, the `/rebuild` flow step by step, commands, parallel work, troubleshooting, where things are.
- Handover ends with the location in full, how to start slice 00, and both ways to start slice 00 as ready-to-paste blocks – the slice prompt directly in Claude Code, and the superpowers command (after the repo, or as an example below the files); the skill never installs the plugin.
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
