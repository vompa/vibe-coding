# Vibe coding plugins by vompa

**Plugins by vompa for AI-assisted software engineering: rebuild existing apps, run everyday coding in slices.**

```bash
claude plugin marketplace add vompa/vibe-coding
claude plugin install vibe-rebuild@vompa
claude plugin install vibe-coding@vompa
```
or inside a session: `/plugin install vibe-rebuild --marketplace vompa/vibe-coding` (likewise `vibe-coding`)

**Claude.ai / other agents:** upload `plugins/<plugin>/skills/<plugin>/` as a skill, or copy that folder into the agent's skills directory.

Two [Agent Skills](https://agentskills.io) and Claude Code plugins in one marketplace (`vompa`). They work the same way: the work is cut into vertical slices, every slice runs in its own fresh Claude session – plan first, tests first, one squash commit per slice, decisions kept in files – and a loop script can run them all hands-off. Nothing is pushed and nothing is installed for you. The plugins are independent; install either or both.

- **[vibe-rebuild](plugins/vibe-rebuild/README.md)** – Existing app → plan to rebuild it better with vibe coding – same or new stack, nothing users rely on gets lost.
- **[vibe-coding](plugins/vibe-coding/README.md)** – Findings or ideas in, one squash commit per slice out – fresh Claude session each, your repo's rules honoured.

A repository finished with vibe-rebuild continues with vibe-coding – see [Relationship to vibe-rebuild](plugins/vibe-coding/README.md#relationship-to-vibe-rebuild).

## Quality

- **vibe-rebuild, end-to-end reference: [mcp-time-net](https://github.com/vompa/mcp-time-net).** The official MCP [`time` server](https://github.com/modelcontextprotocol/servers/tree/51b6382/src/time) (~310 lines Python) rebuilt on .NET 10 with vibe-rebuild 2.2.0 – the plan and then all 5 slices via `/rebuild` with superpowers, one squash commit per slice. Result: 44 parity cases with exact values green, 202 tests, every deviation from the original logged as an improvement on purpose. Its README walks through both phases step by step; the git history shows the plan commit followed by one commit per slice.
- **Trigger eval.** Does the skill start when it should, and stay quiet when it should not? `tests/trigger_check.py` asks the installed skill English and German requests and counts the first tool call.
  - vibe-rebuild (`tests/trigger-eval.json`, 10 positive and 10 near-miss negative requests, 3 runs each): **20/20**, no false triggers.
    ```bash
    python3 tests/trigger_check.py tests/trigger-eval.json --runs 3
    ```
  - vibe-coding (`tests/trigger-eval-vibe-coding.json`, 10 positive requests – findings lists, test feedback, features to slice, setting up the loop – and 10 near-miss negatives – four rebuild requests, a single fix, a code review, a prompting question, a framework upgrade, unit tests, an architecture question; 3 runs each, plugin loaded from the checkout): **20/20**, no false triggers.
    ```bash
    python3 tests/trigger_check.py tests/trigger-eval-vibe-coding.json --skill vibe-coding --plugin-dir plugins/vibe-coding --runs 3
    ```
    The two skills stay apart: with both plugins loaded, none of the ten vibe-coding requests triggers vibe-rebuild (0 of 30 sessions) and none of the ten rebuild requests of `tests/trigger-eval.json` triggers vibe-coding (0 of 10 sessions).
- **Loop test** (`tests/loop_test.py`): the loop scripts of both plugins (`rebuild-loop` and `slice-loop`, PowerShell and bash) against a fake `claude` CLI – auto approval, parallel slices, red slice, open decision, no terminal, all done; for `slice-loop` also `--max-slices`, a three-digit slice number and the round close, the merge queue (sequential, three-digit and parallel runs, ready but not ticked, `SLICE-DONE` still accepted, the fallback message, three `--merge` cases) and rule-based resolution of `work/checklist.md` and the round record (a foreign conflict names only its own file, a failed resolution check stops); since vibe-coding 1.3.0 also append-only lines in any file, the round's status row merged per key, a real conflict left behind while the queue goes on, missing, red, stale and incomplete checks proofs, a duplicate finding id, manual test blocks kept in slice order and a malformed block refused, a parallel run that goes on past a slice it left behind, `SLICE-WAIT` checked back on and capped, and a locked worktree removed by a later `--merge`; since 1.3.1 a file another process holds – retried until free, or the slice left behind with its merge reset – and a refused squash commit that leaves a clean checkout; since 1.4.0 checks proofs with stale, rerun and regressed lines, worktree removal retried and link targets counted, glued record lines refused (text added to a line's end accepted), stale and live full-suite locks, `--merge --verify` (green, red, no squash, no chain, lock held, usage) and parallel batches capped and kept apart by shared files (at most two per batch since 1.6.0); since 1.5.0 a slice without a ready file, or with one of an older tip, left behind; since 1.5.1 a conventions file with a translated `Baseline check` key reported; since 1.7.0 a slice not ready yet listed without failing `--merge`, a slice cut from an older integration branch squashed as it is or left behind when it overlaps, a real conflict in a document, and decision lines in neither format refused. Runs in CI on every push to `main` and on pull requests.
- **Renderer test** (`tests/render_slices_test.py`): the vibe-coding slice renderer – all sections, defaults for optional fields, German headings, the reserved finding ids, the files a slice expects to change, a missing required field, LF line endings.
- **Markers test** (`tests/markers_test.py`): the `/slice` command, both `slice-loop` scripts and the templates agree on the marker lines (including `SLICE-READY:` and `SLICE-WAIT:`) and file formats, the merge option, the session hints, the full-suite lock, the check scope per slice, the checks proof, reserved finding ids, the manual test format and the collect mode; since 1.4.0 the hard list before `SLICE-READY:`, the meaning of red, the wider check scope, the Opus-at-low-effort orchestrator, files per slice, `-Merge -Verify`, the round-close cleanup and `/slice quick`; since 1.5.0 the ready file, the last checks run after tick and merge, the red proof line, the baseline in the worktree, real input in screen tests, generated outputs and the fresh reviewer; no absolute user path or private mail address in the vibe-coding skill.

## Development

Repository layout: each shipped plugin lives in `plugins/<name>/` (what the directory and installs see); `tests/` and CI stay outside the plugins.

```bash
claude plugin validate .                               # marketplace (not strict: slice-board has no version on purpose)
claude plugin validate --strict plugins/vibe-rebuild   # plugin
claude plugin validate --strict plugins/vibe-coding    # plugin
claude --plugin-dir plugins/vibe-rebuild --plugin-dir plugins/vibe-coding   # load both plugins for one session
python tests/markers_test.py && python tests/render_slices_test.py && python tests/loop_test.py   # needs bash and/or pwsh; the loop test takes about a minute
```
New version of a plugin: bump `version` in `plugins/<name>/.claude-plugin/plugin.json` and `metadata.version` in its `SKILL.md`, add an entry to `plugins/<name>/CHANGELOG.md`.

## License

MIT – see [LICENSE](LICENSE).
