# vibe-coding Plugin Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Add the `vibe-coding` plugin (skill, `/slice` command template, `slice-loop` scripts, renderer) as the second plugin of the `vompa` marketplace in this repository, finish the repository rename to `vibe-coding`, and prove it with validation, loop tests, a trigger eval and the first real round in the user's main project.

**Architecture:** Everything the plugin ships lives under `plugins/vibe-coding/` and mirrors the layout of `plugins/vibe-rebuild/` (`.claude-plugin/`, `skills/<name>/SKILL.md`, `references/`, `assets/`, `scripts/`). The skill text and references are the product; the two loop scripts and the renderer are derived from vibe-rebuild's and differ only in folder (`work/`), command (`/slice`), the `--max-slices` cap and the round close. Developer tooling (`tests/`, CI) stays outside the plugins; the loop test becomes one parametrised test that drives both plugins' scripts against the fake `claude` CLI.

**Tech Stack:** Markdown (Agent Skills spec), Python 3.10+ (renderer, tests), bash and PowerShell 7 (loop), GitHub Actions (`validate.yml`), Claude Code CLI (`claude plugin validate`, `claude -p` for the trigger eval).

**Spec:** `docs/superpowers/specs/2026-10-24-vibe-coding-design.md`

## Global Constraints

- Everything committed to this repository is in English: skill text, references, README, tests, commit messages (spec §5).
- Fixed names in target repositories: folder `work/`, command `/slice`, scripts `.claude/scripts/slice-loop.ps1` and `.sh`, logs `.slice-loop/` (spec §7, decision 11).
- Marker lines, exactly: `PLAN:`, `NEEDS-DECISION:`, `SLICE-DONE: NN`, `SLICE-OPEN: NN <reason>`, `ALL-DONE`, `ROUND-DONE: Rnn`, `ROUND-OPEN: Rnn <reason>` (spec §7.4, §7.5).
- `work/checklist.md` rows start with `| NN ` and hold only agent-ticked cells `☐`/`☑`; a slice is done when its row has a `☑` and no `☐` (spec §7, decision 12).
- Slice numbers have at least two digits and may have more; every regex that reads them must accept `[0-9]{2,}` (spec §9).
- `_slices.json` entries: required `nr, slug, name, goal, deps, scope, non_goals`; optional `round, source, mirror, not_building, acceptance, manual`; unknown fields are ignored (spec §9).
- The skill never installs plugins, never pushes, never deletes; loop sessions run with `--permission-mode` from `SLICE_PERMISSION_MODE` (default `auto`) and never `--bare` (spec §3, §5, §7.5).
- No absolute paths, user names, machine names, private e-mail addresses or personal names in any file of this repository or in the files the skill writes (spec §5).
- Line endings LF (`.gitattributes`: `* text=auto eol=lf`); `.bat`/`.cmd` would need `-text` – none are added.
- `claude plugin validate --strict` passes for `.` and both plugins; `skills-ref validate` passes for both skills; skill `name` equals its directory name.
- vibe-rebuild keeps version 2.3.x; only its repository links change (2.3.1). vibe-coding starts at 1.0.0.
- Pushing, tagging and the plugin-directory submission are the user's call at the time; the builder prepares and asks (spec §10).

## Review Focus

1. **Three-digit slice numbers** (`100`): `slice_deps`/`Get-Slices` in vibe-rebuild use two-digit patterns; the new scripts must tick, block and build slice `100` correctly – pinned in Task 5 (loop test case "three-digit slice").
2. **Several round records** (`R01` closed, `R02` open): the loop must run on the open one and exit with "no open round" when all are closed – Task 5 cases "second round open" and "no open round".
3. **`--max-slices` reached with slices left**: the loop exits 0 after exactly N builds and says how many remain, instead of dying – Task 5 case "max slices stops after one".
4. **Round close reports `ROUND-OPEN`**: the loop exits 1 and prints the reason; the round stays open – Task 5 case "close fails".
5. **Slice entry without optional fields**: the renderer writes `–` for `source`, `mirror`, `not_building`, `acceptance`, `manual`, `round` and leaves no `{placeholder}` in the output – Task 3 test `test_optional_fields_default_to_dash`.

---

### Task 1: Finish the repository rename in files; move the vibe-rebuild changelog

**Files:**
- Modify: `README.md` (install block lines 97–100; becomes the family README in Task 8, here only the URLs)
- Modify: `plugins/vibe-rebuild/.claude-plugin/plugin.json:10-11,24-27` (six URLs), `"version": "2.3.1"`
- Modify: `plugins/vibe-rebuild/PRIVACY.md:13`, `plugins/vibe-rebuild/README.md:62`
- Modify: `plugins/vibe-rebuild/skills/vibe-rebuild/SKILL.md` (`metadata.version: "2.3.1"`)
- Move: `CHANGELOG.md` → `plugins/vibe-rebuild/CHANGELOG.md` (`git mv`), add entry `## 2.3.1 – 2026-10-24` ("Repository renamed to vompa/vibe-coding; links updated. No functional change.")
- Modify: `.gitignore` (add `*.stackdump`)

**Interfaces:**
- Produces: repository URL `https://github.com/vompa/vibe-coding` used by every later task; marketplace install command `claude plugin marketplace add vompa/vibe-coding`.

- [ ] **Step 1: Write the failing check**

Run: `grep -rn "vompa/vibe-rebuild" --include=*.md --include=*.json . | grep -v "^./.git/"`
Expected now: 10 hits (README 2, plugin.json 6, PRIVACY 1, plugin README 1). Target: 0 hits.

- [ ] **Step 2: Replace the URLs, bump 2.3.0 → 2.3.1 in `plugin.json` and `SKILL.md`, move the changelog and add the 2.3.1 entry, add `*.stackdump` to `.gitignore`**

Install block in the root README becomes:

```bash
claude plugin marketplace add vompa/vibe-coding
claude plugin install vibe-rebuild@vompa
```

- [ ] **Step 3: Verify**

Run: `grep -rn "vompa/vibe-rebuild" --include=*.md --include=*.json . | grep -v "^./.git/"` → no output.
Run: `claude plugin validate --strict . && claude plugin validate --strict plugins/vibe-rebuild` → both report valid.
Run: `test -f plugins/vibe-rebuild/CHANGELOG.md && ! test -f CHANGELOG.md` → exit 0.

- [ ] **Step 4: Commit**

```bash
git add -A
git commit -m "Rename references to vompa/vibe-coding; vibe-rebuild 2.3.1; changelog moves into the plugin"
```

---

### Task 2: Plugin skeleton for vibe-coding that validates

**Files:**
- Create: `plugins/vibe-coding/.claude-plugin/plugin.json`
- Create: `plugins/vibe-coding/.claude-plugin/icon.png` (copy of `plugins/vibe-rebuild/.claude-plugin/icon.png`; a distinct icon is a follow-up)
- Create: `plugins/vibe-coding/LICENSE` (copy of `plugins/vibe-rebuild/LICENSE`)
- Create: `plugins/vibe-coding/PRIVACY.md` (from vibe-rebuild's, adapted: scripts `render_slices.py`, `slice-loop.*`; the skill writes `work/` and `.claude/` in the repository you name; no research step unless new technology is involved)
- Create: `plugins/vibe-coding/CHANGELOG.md` (`## 1.0.0 – unreleased`)
- Create: `plugins/vibe-coding/README.md` (one paragraph placeholder; filled in Task 8)
- Create: `plugins/vibe-coding/skills/vibe-coding/SKILL.md` (frontmatter final, body one line "Filled in Task 7")
- Modify: `.claude-plugin/marketplace.json` (second entry)

**Interfaces:**
- Produces: plugin name `vibe-coding`, skill name `vibe-coding` (invoked `/vibe-coding:vibe-coding`), version `1.0.0`; the frontmatter `description` used by the trigger eval (Task 9).

- [ ] **Step 1: Write the failing check**

Run: `claude plugin validate --strict plugins/vibe-coding` → fails (folder missing).

- [ ] **Step 2: Create the manifests**

`plugin.json` mirrors vibe-rebuild's fields with: `"name": "vibe-coding"`, `"displayName": "Vibe Coding"`, `"version": "1.0.0"`, description "Turns findings lists and feature ideas into rounds of vertical slices and runs them one per fresh Claude session: plan first, tests first, one squash commit per slice, hands-off loop, decisions in files – in any repository, honouring its own rules.", keywords `["vibe-coding", "slices", "feedback-loop", "tdd", "squash", "superpowers", "claude-code"]`, URLs under `https://github.com/vompa/vibe-coding` with `plugins/vibe-coding/PRIVACY.md` and `LICENSE`.

`SKILL.md` frontmatter:

```yaml
---
name: vibe-coding
description: Runs everyday coding work the vibe-rebuild way – turns a findings list (UI review, user test notes, bug reports) or a feature idea into a round of vertical slices with ready-to-run prompts and a Definition of Done, then executes them one per fresh Claude session via /slice – plan first, tests first, one squash commit per slice on the repo's own branch, a hands-off loop, and a manual test list at the end of each round. Honours the repository's existing CLAUDE.md and working rules. Use whenever someone has a list of changes, review findings or test feedback to work through, wants to slice a feature into agent-sized work packages with fewer pull requests, or wants a feedback loop of build → test → findings → next round with Claude Code. Not for rebuilding or migrating an existing app (that is vibe-rebuild), not for a single quick fix, a code review or a prompting guide.
license: MIT
compatibility: Designed for Claude Code with file access and subagents; render script needs Python 3.10+; the slice-loop needs the claude CLI plus PowerShell 7 or bash; uses the superpowers plugin when installed.
metadata:
  author: vompa
  version: "1.0.0"
---
```

Marketplace entry: `{"name": "vibe-coding", "source": "./plugins/vibe-coding", "description": "Everyday coding in rounds of vertical slices – findings or ideas in, one squash commit per slice out, fresh session each, your repo's rules honoured."}`

- [ ] **Step 3: Verify**

Run: `claude plugin validate --strict . && claude plugin validate --strict plugins/vibe-coding` → valid.
Run: `python -c "import re,pathlib;t=pathlib.Path('plugins/vibe-coding/skills/vibe-coding/SKILL.md').read_text(encoding='utf-8');print(re.search(r'^name: (.+)$',t,re.M).group(1))"` → `vibe-coding`.

- [ ] **Step 4: Commit**

```bash
git add plugins/vibe-coding .claude-plugin/marketplace.json
git commit -m "vibe-coding: plugin skeleton, manifests and marketplace entry"
```

---

### Task 3: Renderer with the new slice fields

**Files:**
- Create: `plugins/vibe-coding/skills/vibe-coding/scripts/render_slices.py` (start from vibe-rebuild's copy)
- Test: `tests/render_slices_test.py`

**Interfaces:**
- Consumes: `_slices.json` entry fields from Global Constraints.
- Produces: `python3 render_slices.py <_slices.json> <output_dir> [--lang en|de]` writes `<nr>-<slug>.md` per entry; exit 0 on success, 1 on a missing required field, 2 on usage errors. Headings (en): `# Slice {nr} – {name}`, `**Goal:**`, `**Round:**`, `**Source:**`, `**Depends on:**`, `## Scope`, `## Patterns to mirror`, `## NOT building`, `## Prompt`, `## Definition of Done`, `## Non-goals`; (de): `**Ziel:**`, `**Runde:**`, `**Quelle:**`, `**Hängt ab von:**`, `## Umfang`, `## Muster übernehmen`, `## NICHT bauen`, `## Prompt`, `## Definition of Done`, `## Nicht in dieser Slice`.

- [ ] **Step 1: Write the failing tests**

```python
# tests/render_slices_test.py
import json, pathlib, subprocess, sys, tempfile
SCRIPT = pathlib.Path(__file__).resolve().parent.parent / "plugins/vibe-coding/skills/vibe-coding/scripts/render_slices.py"
FULL = {"nr": "05", "slug": "labels", "name": "Field labels", "goal": "Every field has a label.", "round": "R01",
        "source": "W-Muster 1, W1, W6", "deps": "–", "scope": ["Login", "Join"],
        "mirror": ["Views/CustomerContactForm.axaml:40-58 FormField usage"], "not_building": ["New controls"],
        "acceptance": ["Given the login screen When a screen reader reads field 1 Then it hears the label, not the placeholder"],
        "manual": ["Login: Tab through the form, every field is announced with its label"], "non_goals": "Colours"}
MINIMAL = {"nr": "100", "slug": "sweep", "name": "Sweep", "goal": "g", "deps": "05", "scope": ["a"], "non_goals": "n", "extra": "ignored"}

def render(entries, lang="en"):
    with tempfile.TemporaryDirectory() as tmp:
        src = pathlib.Path(tmp, "s.json"); src.write_text(json.dumps(entries, ensure_ascii=False), encoding="utf-8")
        out = pathlib.Path(tmp, "out")
        proc = subprocess.run([sys.executable, str(SCRIPT), str(src), str(out), "--lang", lang], capture_output=True, text=True)
        files = {p.name: p.read_text(encoding="utf-8") for p in out.glob("*.md")} if out.exists() else {}
        return proc.returncode, files

def test_full_entry_renders_all_sections():
    code, files = render([FULL])
    text = files["05-labels.md"]
    assert code == 0
    for heading in ("**Round:** R01", "**Source:** W-Muster 1, W1, W6", "## Patterns to mirror", "- Views/CustomerContactForm.axaml:40-58 FormField usage",
                    "## NOT building", "- New controls", "- [ ] Given the login screen When", "- [ ] Manual: Login: Tab through", "work/conventions.md", "work/rounds/R01"):
        assert heading in text, heading

def test_optional_fields_default_to_dash():
    code, files = render([MINIMAL])
    text = files["100-sweep.md"]
    assert code == 0 and "{" not in text
    assert "**Round:** –" in text and "**Source:** –" in text
    assert "## Patterns to mirror\n–" in text and "## NOT building\n–" in text

def test_german_headings():
    code, files = render([FULL], "de")
    text = files["05-labels.md"]
    assert code == 0 and "## Muster übernehmen" in text and "## NICHT bauen" in text and "**Hängt ab von:** –" in text

def test_missing_required_field_fails():
    code, files = render([{k: v for k, v in MINIMAL.items() if k != "goal"}])
    assert code == 1 and not files

def test_round_less_prompt_points_to_open_round():
    code, files = render([MINIMAL])
    text = files["100-sweep.md"]
    assert code == 0 and "rounds/–" not in text
    assert 'the open round record in work/rounds/ (first line "Status: open")' in text
    code, files = render([FULL])
    assert "work/rounds/R01-*.md" in files["05-labels.md"]

def test_output_uses_lf_line_endings():
    with tempfile.TemporaryDirectory() as tmp:
        src = pathlib.Path(tmp, "s.json"); src.write_text(json.dumps([MINIMAL]), encoding="utf-8")
        out = pathlib.Path(tmp, "out")
        subprocess.run([sys.executable, str(SCRIPT), str(src), str(out)], check=True)
        assert b"\r" not in (out / "100-sweep.md").read_bytes()

if __name__ == "__main__":
    for name, fn in list(globals().items()):
        if name.startswith("test_"):
            fn(); print("ok  ", name)
```

- [ ] **Step 2: Run the tests to verify they fail**

Run: `python tests/render_slices_test.py`
Expected: FAIL (script not found).

- [ ] **Step 3: Implement the renderer**

Copy `plugins/vibe-rebuild/skills/vibe-rebuild/scripts/render_slices.py`, then: `REQUIRED = ("nr", "slug", "name", "goal", "deps", "scope", "non_goals")`; `OPTIONAL_TEXT = ("round", "source")` default `–`; `OPTIONAL_LISTS = ("mirror", "not_building", "acceptance", "manual")` rendered as `- item` lines or `–` when missing/empty; acceptance items render as `- [ ] <item>`, manual items as `- [ ] Manual: <item>` inside the Definition of Done. The prompt block (en) tells the implementer to read `CLAUDE.md`, `work/conventions.md`, the round record (`work/rounds/{round}-*.md`, or the open round record in `work/rounds/` when the entry has no round) and this slice file; plan with "Assumptions (confirm on approval)" and "Review focus", save to `work/plans/`; failing tests first; the minimum to go green; follow every rule in `CLAUDE.md` and `work/conventions.md`; record decisions, surprises and deferred minors in the round record and the repository's protocol file named in `conventions.md`. Definition of Done fixed lines: checks from `work/conventions.md` green; no test weakened or skipped; no new packages without approval; decisions recorded. German template mirrors it. Build the format dict with `{**defaults, **s, "scope": …, lists…}` so unknown fields pass through harmlessly. Write each slice file with `open(path, "w", encoding="utf-8", newline="\n")` so the output is LF on every platform.

- [ ] **Step 4: Run the tests to verify they pass**

Run: `python tests/render_slices_test.py` → six `ok` lines, exit 0.
Run: `python -m py_compile plugins/vibe-coding/skills/vibe-coding/scripts/render_slices.py`.

- [ ] **Step 5: Commit**

```bash
git add plugins/vibe-coding/skills/vibe-coding/scripts/render_slices.py tests/render_slices_test.py
git commit -m "vibe-coding: slice renderer with round, source, mirror, not-building, acceptance and manual fields"
```

---

### Task 4: Loop test parametrised for both plugins (red for vibe-coding)

**Files:**
- Move: `tests/rebuild_loop_test.py` → `tests/loop_test.py` (`git mv`), then modify
- Modify: `.github/workflows/validate.yml` ("Check rebuild-loop scripts" step calls `python tests/loop_test.py`)
- Modify: `README.md` Quality/Development sections mentioning `rebuild_loop_test.py`

**Interfaces:**
- Produces: `PROFILES` list in `tests/loop_test.py`; each profile is a dict `{"plugin": "vibe-rebuild"|"vibe-coding", "script": "rebuild-loop"|"slice-loop", "folder": "rebuild"|"work", "command": "/rebuild"|"/slice", "slices": [...], "cases": [...]}`; `make_repo(base, profile, done, rounds=None)` writes `<folder>/_slices.json`, `<folder>/checklist.md` and, for `work`, `work/rounds/<id>-test.md` files whose first line is `Status: <open|closed>` (`rounds` defaults to `[("R01", "open")]`); the stub answers `/<command> NN plan auto`, `Build slice NN and close it`, `/<command> close auto` (prints `ROUND-DONE: R01`, or `ROUND-OPEN: R01 checks red` when `STUB_CLOSE_FAIL=1`). The stub's slice-number patterns use `\d{2,}`.
- Stub rule for ticking stays: replace `☐` by `☑` in the row starting `| NN`; the lock file lives in `<folder>/checklist.lock`.

- [ ] **Step 1: Rename and parametrise**

`slices` per profile: rebuild keeps the five entries 00–04; vibe-coding uses `[{"nr":"05","deps":"–","round":"R01"},{"nr":"06","deps":"05","round":"R01"},{"nr":"07","deps":"06","round":"R01"},{"nr":"100","deps":"07","round":"R01"},{"nr":"101","deps":"07","round":"R01"}]`. `outcome()` counts ticks in `<folder>/checklist.md`, build turns via `Build slice`, and close turns via `close auto` in `stub-calls.log`; expected tuples become `(exit, ticked, builds, closes)`.

Cases for the rebuild profile: the existing eight, with `closes` = 0.

Cases for the vibe-coding profile (name, done, options, env, rounds, expected):

```python
("dry run lists ready slices", 3, ["--dry-run"], {}, None, (0, 3, 0, 0)),          # stdout.split() == ["100", "101"]
("auto approve runs all slices then closes the round", 1, ["--yes"], {}, None, (0, 5, 4, 1)),
("three-digit slice is ticked and built", 3, ["--yes", "--max-slices", "1"], {}, None, (0, 4, 1, 0)),
("parallel builds both ready slices", 3, ["--yes", "--parallel"], {}, None, (0, 5, 2, 1)),
("red slice stops the loop", 3, ["--yes"], {"STUB_FAIL": "100"}, None, (1, 3, 1, 0)),
("done but not ticked stops instead of rebuilding", 3, ["--yes"], {"STUB_NO_TICK": "100"}, None, (1, 3, 1, 0)),
("decision without terminal does not build", 3, ["--yes"], {"STUB_DECISION": "100"}, None, (1, 3, 0, 0)),
("approval without terminal does not build", 3, [], {}, None, (1, 3, 0, 0)),
("max slices stops after one with slices left", 1, ["--yes", "--max-slices", "1"], {}, None, (0, 2, 1, 0)),
("close fails keeps the round open", 4, ["--yes"], {"STUB_CLOSE_FAIL": "1"}, None, (1, 5, 1, 1)),
("second round open runs on it", 3, ["--yes", "--max-slices", "1"], {}, [("R01", "closed"), ("R02", "open")], (0, 4, 1, 0)),
("no open round exits without building", 3, ["--yes"], {}, [("R01", "closed")], (0, 3, 0, 0)),
("all done and closed exits cleanly", 5, [], {}, [("R01", "closed")], (0, 5, 0, 0)),
```

`PWSH_FLAGS` gains `"--max-slices": "-MaxSlices"` (the value is passed as the following argument in both shells).

- [ ] **Step 2: Run the test to verify the rebuild profile passes and the vibe-coding profile fails**

Run: `python tests/loop_test.py`
Expected: rebuild cases `ok`, vibe-coding cases `FAIL` (script missing), exit 1.

- [ ] **Step 3: Update `validate.yml` and the README references to the new test name**

- [ ] **Step 4: Commit**

```bash
git add -A tests .github/workflows/validate.yml README.md
git commit -m "Loop test parametrised for rebuild-loop and slice-loop (slice cases red)"
```

---

### Task 5: `slice-loop.sh` and `slice-loop.ps1`

**Files:**
- Create: `plugins/vibe-coding/skills/vibe-coding/assets/slice-loop.sh` (from `rebuild-loop.sh`)
- Create: `plugins/vibe-coding/skills/vibe-coding/assets/slice-loop.ps1` (from `rebuild-loop.ps1`)
- Test: `tests/loop_test.py` (Task 4)

**Interfaces:**
- Consumes: `work/_slices.json` (`nr`, `deps`, `round`), `work/checklist.md`, `work/rounds/*.md` (`Status:` first line), the `/slice` markers.
- Produces: `bash .claude/scripts/slice-loop.sh [--yes] [--parallel] [--dry-run] [--max-slices N]`; `pwsh .claude/scripts/slice-loop.ps1 [-Yes] [-Parallel] [-DryRun] [-MaxSlices N]`; env `SLICE_PERMISSION_MODE`; logs `.slice-loop/slice-NN-<timestamp>.log` and `.slice-loop/close-<timestamp>.log`; exit 0 after `ROUND-DONE`, after `--max-slices` is reached, or when no round is open; exit 1 on any stop.

- [ ] **Step 1: Write both scripts**

Changes against the rebuild scripts, same in both languages:
- constants: `work/_slices.json`, `work/checklist.md`, `.slice-loop`, `SLICE_PERMISSION_MODE`, command `/slice`; usage header rewritten (no "rebuild").
- number patterns: bash `slice_deps` uses `grep -o '[0-9][0-9]*'`; PowerShell `Get-Slices` uses `'\d{2,}'`.
- `open_round()` / `Get-OpenRound`: the first file in `work/rounds/*.md` whose first line is `Status: open`; prints its round id (`R\d+` from the file name) or nothing. `main`: if none → print `slice-loop: no open round in work/rounds – start a round with the vibe-coding skill first` and exit 0 (after the file checks, before the `claude` check).
- `--max-slices N` (`-MaxSlices`): N must be a positive integer, else die with the usage line; count built slices; when the count reaches N and slices remain, print `slice-loop: stopped after N slice(s) – M still open` and exit 0.
- the parallel note names `work/checklist.md` and "the integration branch" instead of `main`.
- after `all_done`: `close_round` runs `claude -p --permission-mode … --session-id <new> "/slice close auto"` into `.slice-loop/close-<timestamp>.log`; `ROUND-DONE:` line → print it and exit 0; otherwise die with the `ROUND-OPEN:` line (or "no ROUND-DONE line").
- final message after ROUND-DONE: `Round closed. Next: test with the manual test list in work/rounds/, then start the next round with the vibe-coding skill.`

- [ ] **Step 2: Run the loop test**

Run: `python tests/loop_test.py` → all cases `ok` for bash and pwsh, exit 0.
Run: `bash -n plugins/vibe-coding/skills/vibe-coding/assets/slice-loop.sh`
Run: `pwsh -NoProfile -Command "\$null = [scriptblock]::Create((Get-Content -Raw plugins/vibe-coding/skills/vibe-coding/assets/slice-loop.ps1))"`

- [ ] **Step 3: Add the vibe-coding script checks to `validate.yml`** (same three commands as for rebuild-loop; `loop_test.py` already covers both).

- [ ] **Step 4: Commit**

```bash
git add plugins/vibe-coding/skills/vibe-coding/assets .github/workflows/validate.yml
git commit -m "vibe-coding: slice-loop scripts with max-slices cap and round close"
```

---

### Task 6: References: `/slice` command, templates, intake, round close; marker contract test

**Files:**
- Create: `plugins/vibe-coding/skills/vibe-coding/references/slice-command.md`
- Create: `plugins/vibe-coding/skills/vibe-coding/references/templates.md`
- Create: `plugins/vibe-coding/skills/vibe-coding/references/intake.md`
- Create: `plugins/vibe-coding/skills/vibe-coding/references/round-close.md`
- Test: `tests/markers_test.py`

**Interfaces:**
- Produces: the `/slice` command text that Task 7's SKILL.md tells the skill to copy unchanged to `.claude/commands/slice.md`; template texts for `work/conventions.md`, `work/rounds/Rnn-<slug>.md`, `work/checklist.md`, `_slices.json`, lean `CLAUDE.md`; the manual test list format.

- [ ] **Step 1: Write the failing contract test**

```python
# tests/markers_test.py
import pathlib, re
ROOT = pathlib.Path(__file__).resolve().parent.parent
SKILL = ROOT / "plugins/vibe-coding/skills/vibe-coding"
MARKERS = ["PLAN:", "NEEDS-DECISION:", "SLICE-DONE:", "SLICE-OPEN:", "ALL-DONE", "ROUND-DONE:", "ROUND-OPEN:"]

def test_command_defines_every_marker():
    text = (SKILL / "references/slice-command.md").read_text(encoding="utf-8")
    for m in MARKERS: assert m in text, m
    assert 'argument-hint: "[status | NN | close] [plan] [auto] [direct]"' in text
    assert "work/conventions.md" in text and "git merge --squash" in text and "never push" in text.lower()

def test_loop_scripts_read_the_same_markers():
    for name in ("slice-loop.sh", "slice-loop.ps1"):
        text = (SKILL / f"assets/{name}").read_text(encoding="utf-8")
        for m in ("PLAN:", "NEEDS-DECISION:", "SLICE-DONE:", "SLICE-OPEN:", "ROUND-DONE:", "ROUND-OPEN:"): assert m in text, (name, m)
        assert "/slice" in text and "work/_slices.json" in text and "rebuild" not in text.lower()

def test_templates_fix_the_formats():
    text = (SKILL / "references/templates.md").read_text(encoding="utf-8")
    assert "Status: open" in text and "| NN " in text and '"round"' in text and "work/conventions.md" in text

def test_no_personal_or_absolute_paths():
    for p in SKILL.rglob("*"):
        if p.is_file():
            t = p.read_text(encoding="utf-8", errors="ignore")
            assert not re.search(r"[A-Za-z]:\\Users|/home/|/Users/|@gmail", t), p

if __name__ == "__main__":
    for name, fn in list(globals().items()):
        if name.startswith("test_"): fn(); print("ok  ", name)
```

- [ ] **Step 2: Run it to verify it fails**

Run: `python tests/markers_test.py` → FAIL (files missing).

- [ ] **Step 3: Write `slice-command.md`**

Start from `plugins/vibe-rebuild/skills/vibe-rebuild/references/rebuild-command.md` and apply spec §7.4: frontmatter `description: Work the current round slice by slice – next slice, a given slice, status, or close the round`, `argument-hint: "[status | NN | close] [plan] [auto] [direct]"`; §1 decides between `status`, `NN`, nothing, `close`, no open round; §2 reads `work/conventions.md`, the open round record, `work/slices/NN-*.md`, `CLAUDE.md`, and runs the baseline check from `conventions.md` before any change (red → `SLICE-OPEN: NN baseline red: <check>`; interactive: ask); §3 superpowers path (`using-git-worktrees` on `slice-NN`, `writing-plans` saved to `work/plans/<date>-slice-NN.md` with "Assumptions (confirm on approval)" and "Review focus", approval, `subagent-driven-development` or `executing-plans`, `finishing-a-development-branch` with `git merge --squash slice-NN` onto the integration branch named in `conventions.md`, never push) and direct path; `plan`/`auto` semantics and markers as in `/rebuild`; §4 close the slice: checks for a slice from `conventions.md`, tick the checklist row, append `Ruling:` / surprises / deferred minors / manual check items to the round record, write the protocol entry `conventions.md` names in that file's own format (leave out pull-request-only fields), update the documents listed as "must change with a change", end with the three lines or `SLICE-DONE: NN` / `SLICE-OPEN: NN <reason>`; §5 `close`: only the open round, all its slices (field `round`) ticked else `ROUND-OPEN: Rnn <reason>`, full check chain (red → `ROUND-OPEN`), manual test list into the round record (format from `round-close.md`), `Status: closed`, open decisions listed, `ROUND-DONE: Rnn`. Decisions recorded as "User, <date>" unless `conventions.md` allows names.

- [ ] **Step 4: Write `templates.md`**

Sections: `work/conventions.md` (the bullet list of spec §8 as a template with `<source>` after each line, plus the fixed lines `Work folder: work/` and `Finding ids: <scheme or F-NN>`); `work/rounds/Rnn-<slug>.md` (first line `Status: open`, then `## Source`, `## Brief` (ideas only: purpose, users, `AC-NN` Given/When/Then, edge cases, errors, non-goals, NOT building, assumptions), `## Intake` table `id | where | observed → expected | size | source`, `## Slices` table `NN | name | findings/ACs`, `## Decisions` (`Ruling:` lines, "User, <date>"), `## Surprises`, `## Deferred minors`, `## Open decisions` (NEEDS-DECISION), `## Manual test list` (filled at close)); `work/checklist.md` header `| Slice | Plan | Tests red | Green | Checks | Commit |` with rows `| NN name | ☐ | ☐ | ☐ | ☐ | ☐ |`; `_slices.json` example with every field including `"round": "R01"`; lean `CLAUDE.md` for a repository without one (purpose, hard rules, commands, way of working: one slice per session, plan → failing tests → code, one squash commit per slice, never push).

- [ ] **Step 5: Write `intake.md`**

Two sections from spec §7.1 and §7.2: findings (capture without copying, id scheme, `reopens`, grouping by screen or theme, dependency order, one slice ≈ one session, sweep slice for trivial items, "user decides" → open decision, acceptance line per finding, manual check item for UI findings) and ideas (brief ≤ 1 page, `superpowers:brainstorming` when installed else up to five questions in one go, reference existing concept documents, research trigger and the broad/deep/distill pass with licences appended to `work/research.md`, decisions that change architecture or cost go to the user before slicing, MVP-first vertical slices with an independent test). Close with the size classes S/M/L and the sentence that examples in the templates are open lists, not checklists.

- [ ] **Step 6: Write `round-close.md`**

Close steps (mirrors §5 of the command), the manual test list format (`### Slice NN – name` then `Start: <command from conventions.md>`, numbered steps, `Expected:` line, `Closes: <ids>`), the handover message (where the list is, how to report findings: "answer in chat or add to the round record; the next round starts from your notes"), and how the next round inherits open decisions and reopened findings.

- [ ] **Step 7: Run the contract test and the validators**

Run: `python tests/markers_test.py` → four `ok`.
Run: `claude plugin validate --strict plugins/vibe-coding` → valid.

- [ ] **Step 8: Commit**

```bash
git add plugins/vibe-coding/skills/vibe-coding/references tests/markers_test.py
git commit -m "vibe-coding: /slice command template, templates, intake and round-close references; marker contract test"
```

---

### Task 7: `SKILL.md`

**Files:**
- Modify: `plugins/vibe-coding/skills/vibe-coding/SKILL.md` (body)
- Modify: `.github/workflows/validate.yml` (`skills-ref validate plugins/vibe-coding/skills/vibe-coding`, `python tests/render_slices_test.py`, `python tests/markers_test.py`)

**Interfaces:**
- Consumes: the references of Task 6, scripts of Tasks 3 and 5.
- Produces: the skill procedure the dry run (Task 10) follows.

- [ ] **Step 1: Write the body**, under 260 lines, in vibe-rebuild's voice, with these sections in this order:
  1. Title and purpose (spec §1, two paragraphs: what, why; one sentence that this is a "how to run the work" skill, not a prompting guide; plan files in the user's language).
  2. "Keep the chat clean" and "Keep the user posted" (copy the rules from vibe-rebuild's SKILL.md, agent reports to `work/_raw/`, phase weights of spec §7.6).
  3. "0. Pick your tools" table: superpowers skills used when installed (brainstorming for ideas; worktrees, writing-plans, subagent-driven-development, finishing-a-development-branch inside `/slice`), fallbacks; never install.
  4. "1. Inputs (one round, then go)": findings file or notes, or an idea; integration branch confirmation; clean tree; language.
  5. "2. Conventions → `work/conventions.md`" (spec §8; first round only; user confirms once; lean `CLAUDE.md` when none).
  6. "3. Intake" → `references/intake.md` (A findings, B idea, research trigger).
  7. "4. Slicing → `work/_slices.json`, `work/slices/`" with the render command `python3 scripts/render_slices.py work/_slices.json work/slices --lang <lang>`, checklist rows, continuous numbering (after `rebuild/_slices.json` when present), one open round.
  8. "5. Handover" (spec §7.0): copy `references/slice-command.md` to `.claude/commands/slice.md` and `assets/slice-loop.*` to `.claude/scripts/` with a file copy, `.gitignore` (`work/_raw/`, `.slice-loop/`), `.gitattributes` (`*.sh text eol=lf`), one commit "Round Rnn: <slug> – N slices" on the integration branch in the repository's commit language, identity check, then the handover message: `/slice` step by step, the loop command, the slice map, open decisions.
  9. "6. After the round": the user tests with the manual test list, answers; the next round starts with those notes (reopened ids).
  10. "Rules" (never push, never install, extend never replace, fixed names and conflicts, no personal or machine data unless the repository allows it, marked assumptions, examples are open lists).
  11. "Output structure" tree from spec §7.

- [ ] **Step 2: Verify**

Run: `claude plugin validate --strict plugins/vibe-coding` → valid.
Run: `python -c "import pathlib;print(len(pathlib.Path('plugins/vibe-coding/skills/vibe-coding/SKILL.md').read_text(encoding='utf-8').splitlines()))"` → ≤ 260.
Run (when `skills-ref` is installed locally; otherwise CI): `skills-ref validate plugins/vibe-coding/skills/vibe-coding`.
Run: `python tests/markers_test.py` → ok (the privacy scan now includes SKILL.md).

- [ ] **Step 3: Commit**

```bash
git add plugins/vibe-coding/skills/vibe-coding/SKILL.md .github/workflows/validate.yml
git commit -m "vibe-coding: SKILL.md – rounds, conventions, intake, slicing, handover"
```

---

### Task 8: READMEs, PRIVACY, CHANGELOG, family README

**Files:**
- Modify: `plugins/vibe-coding/README.md` (sections as in `plugins/vibe-rebuild/README.md`: tagline, What you get (tree from spec §7), How to use it (three example requests: a review findings file, pasted test notes, a feature idea; explicit `/vibe-coding:vibe-coding <file or idea>`), How it works (conventions → intake → slices → handover), Running a round (`/slice`, `/slice 07`, `/slice status`, `/slice close`, loop with options and `--max-slices`), After the round, Relationship to vibe-rebuild (one paragraph, spec §9), Privacy, License)
- Modify: `plugins/vibe-coding/PRIVACY.md` (final text), `plugins/vibe-coding/CHANGELOG.md` (`## 1.0.0 – <date>` with the feature list)
- Modify: `README.md` (root → family README: one line per plugin with its tagline and link to its README, one install block `claude plugin marketplace add vompa/vibe-coding` + `claude plugin install vibe-rebuild@vompa` / `vibe-coding@vompa`, Development section with the commands for both plugins and the three tests, License)
- Modify: `.claude-plugin/marketplace.json` description of the marketplace ("Plugins by vompa for AI-assisted software engineering: rebuild existing apps, run everyday coding in slices")

- [ ] **Step 1: Write the texts**; keep the install command the first thing a reader can copy.

- [ ] **Step 2: Verify**

Run: `grep -rn "vompa/vibe-rebuild" --include=*.md --include=*.json . | grep -v "^./.git/"` → no output.
Run: `claude plugin validate --strict . && claude plugin validate --strict plugins/vibe-coding && claude plugin validate --strict plugins/vibe-rebuild` → valid.
Run: `python tests/markers_test.py && python tests/render_slices_test.py && python tests/loop_test.py` → all ok.

- [ ] **Step 3: Commit**

```bash
git add README.md plugins/vibe-coding .claude-plugin/marketplace.json
git commit -m "vibe-coding: README, privacy and changelog; family README for both plugins"
```

---

### Task 9: Trigger eval for vibe-coding (and no cross-trigger with vibe-rebuild)

**Files:**
- Create: `tests/trigger-eval-vibe-coding.json` (10 `should_trigger: true`, 10 `false`; same format as `tests/trigger-eval.json`)
- Modify: `tests/trigger_check.py` (option `--plugin-dir <path>` passed through as `--plugin-dir` to `claude -p`; docstring)
- Modify: `README.md` Quality section (both eval results, once measured)

**Interfaces:**
- Consumes: SKILL.md frontmatter description (Task 2).

- [ ] **Step 1: Write the eval set**

Positive (English and German mixed): a pasted list of five UI findings from a design review "work these through"; "here is my test feedback after trying the build: …"; "slice the pos-readiness feature into agent-sized work packages with fewer PRs"; "turn docs/review-2026-10-23.md into a round of slices and run it"; "I want build → I test → findings → next round with Claude Code, set it up in this repo"; "plan the next package (import, duplicates, GDPR export) as slices with acceptance criteria"; "nimm die Änderungsliste und arbeite sie in Slices ab, je ein Squash-Commit"; "ich habe getestet, hier meine Punkte je Maske, mach daraus die nächste Runde"; "wir brauchen die Kassa startfähig – zerlege das in Slices mit Given/When/Then und /slice"; "set up the hands-off loop so each slice runs in a fresh session and I only approve plans".
Negative: four rebuild/migration requests taken from the positives of `tests/trigger-eval.json`, plus: "fix the null reference in InvoiceService.cs line 120"; "review PR #482 for security"; "what is vibe coding and how do I prompt well?"; "upgrade the project from .NET 8 to .NET 10"; "write unit tests for the KPI module"; "explain the architecture of this repo".

- [ ] **Step 2: Run against the local plugin, one run first**

Run: `python tests/trigger_check.py tests/trigger-eval-vibe-coding.json --skill vibe-coding --plugin-dir plugins/vibe-coding --runs 1`
Expected: ≥ 18/20; every negative that is a rebuild request must not trigger `vibe-coding`.
Then: `--runs 3` and record the result; if below 18/20, sharpen the description (the "Use whenever … Not for …" sentences) and re-run.

- [ ] **Step 3: Cross-check vibe-rebuild** (installed plugin): `python tests/trigger_check.py tests/trigger-eval-vibe-coding.json --skill vibe-rebuild --runs 1` → 0 of the 10 vibe-coding positives trigger `vibe-rebuild`.

- [ ] **Step 4: Record the numbers in both READMEs' Quality sections and commit**

```bash
git add tests/trigger-eval-vibe-coding.json tests/trigger_check.py README.md plugins/vibe-coding/README.md
git commit -m "vibe-coding: trigger eval set and results; trigger_check supports --plugin-dir"
```

---

### Task 10: First real round in the user's main project (dry run of the whole chain)

**Files:**
- In the user's main project (private, on its `dev` branch; not in this repository): `work/conventions.md`, `work/rounds/R01-<slug>.md`, `work/_slices.json`, `work/slices/*.md`, `work/checklist.md`, `.claude/commands/slice.md`, `.claude/scripts/slice-loop.*`, `.gitignore`, `.gitattributes`
- This repository: `plugins/vibe-coding/CHANGELOG.md` (lessons, if any)

**Interfaces:**
- Consumes: the plugin via `claude --plugin-dir <this repo>/plugins/vibe-coding` in a fresh session started in the main project's folder; the existing UI change list in that project's docs as the findings file.

- [ ] **Step 1: Start a fresh Claude Code session in the main project on `dev` with the plugin loaded and invoke `/vibe-coding:vibe-coding <path of the change list>`**
- [ ] **Step 2: Review `work/conventions.md` with the user** – expected: integration branch `dev`, squash onto `dev`, no push, the project's check chain, the protocol file and its section format, the "must change with a change" documents (status page, help, ADR rule), German docs, names allowed as the project does.
- [ ] **Step 3: Review the slice map in `work/rounds/R01-*.md`** – expected: slices by cross-cutting pattern first, then screens, user-decides items as open decisions; one slice ≈ one session.
- [ ] **Step 4: After the user's confirmation, let the skill commit the round start on `dev`; run `/slice status`; run `/slice <first> plan` and show the plan** – no product code changes before the user's go.
- [ ] **Step 5: Record lessons** in `plugins/vibe-coding/CHANGELOG.md` (and fix the skill/references if the dry run showed a gap; re-run Tasks 6–8 checks), commit.

---

### Task 11: Release preparation (the user pushes and tags)

**Files:**
- Modify: `plugins/vibe-coding/CHANGELOG.md` (date), `plugins/vibe-rebuild/CHANGELOG.md`
- No other changes.

- [ ] **Step 1: Full local CI equivalent**

Run from the repo root: `claude plugin validate --strict . && claude plugin validate --strict plugins/vibe-rebuild && claude plugin validate --strict plugins/vibe-coding && python -m py_compile plugins/*/skills/*/scripts/*.py tests/*.py && python tests/render_slices_test.py && python tests/markers_test.py && python tests/loop_test.py` → exit 0.
Run: `bash -n` and the pwsh parse check for all four loop scripts.

- [ ] **Step 2: Privacy scan over committed files**

Run: `git ls-files -z | xargs -0 grep -lE "C:\\\\Users|/home/[a-z]|@gmail|jorda"` → no output (the fixture `trigger-eval.json` paths like `C:\src\lagerapp` are synthetic examples and are allowed; adjust the pattern if it hits them).

- [ ] **Step 3: Ask the user** to push `main` to `vompa/vibe-coding`, watch CI, and decide on tags `vibe-rebuild-2.3.1` / `vibe-coding-1.0.0` and the plugin-directory "Check for new commits". Do not push or tag without the answer.

- [ ] **Step 4: After the push, update the user's knowledge base** (`projects.md`: repository state, versions, test results; `log/`: one line) and remind that the local folder is renamed in a fresh session.
