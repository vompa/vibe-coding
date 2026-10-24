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
- **Loop test** (`tests/loop_test.py`): the loop scripts of both plugins (`rebuild-loop` and `slice-loop`, PowerShell and bash) against a fake `claude` CLI – auto approval, parallel slices, red slice, open decision, no terminal, all done; for `slice-loop` also `--max-slices`, a three-digit slice number and the round close. Runs in CI on every push to `main` and on pull requests.
- **Renderer test** (`tests/render_slices_test.py`): the vibe-coding slice renderer – all sections, defaults for optional fields, German headings, a missing required field, LF line endings.
- **Markers test** (`tests/markers_test.py`): the `/slice` command, both `slice-loop` scripts and the templates agree on the marker lines and file formats; no absolute user path or private mail address in the vibe-coding skill.

## Development

Repository layout: each shipped plugin lives in `plugins/<name>/` (what the directory and installs see); `tests/` and CI stay outside the plugins.

```bash
claude plugin validate --strict .                      # marketplace
claude plugin validate --strict plugins/vibe-rebuild   # plugin
claude plugin validate --strict plugins/vibe-coding    # plugin
claude --plugin-dir plugins/vibe-rebuild --plugin-dir plugins/vibe-coding   # load both plugins for one session
python tests/markers_test.py && python tests/render_slices_test.py && python tests/loop_test.py   # needs bash and/or pwsh; the loop test takes about a minute
```
New version of a plugin: bump `version` in `plugins/<name>/.claude-plugin/plugin.json` and `metadata.version` in its `SKILL.md`, add an entry to `plugins/<name>/CHANGELOG.md`.

## License

MIT – see [LICENSE](LICENSE).
