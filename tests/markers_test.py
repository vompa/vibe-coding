# tests/markers_test.py
"""Contracts between files, no wording: what the command prints, the scripts read, the skill copies and the release says."""
import json, pathlib, re
ROOT = pathlib.Path(__file__).resolve().parent.parent
SKILL = ROOT / "plugins/vibe-coding/skills/vibe-coding"
COMMAND = SKILL / "references/slice-command.md"
SCRIPTS = ("assets/slice-loop.sh", "assets/slice-loop.ps1")
LOOP_MARKERS = ["PLAN:", "NEEDS-DECISION:", "SLICE-DONE:", "SLICE-READY:", "SLICE-WAIT:", "SLICE-OPEN:", "ROUND-DONE:", "ROUND-OPEN:"]
COPIED = {"round-close.md": ".claude/slice/close.md", "slice-parallel.md": ".claude/slice/parallel.md", "slice-quick.md": ".claude/slice/quick.md"}

def read(name):
    return (SKILL / name).read_text(encoding="utf-8")

def test_command_defines_every_marker():
    text = COMMAND.read_text(encoding="utf-8")
    for marker in LOOP_MARKERS + ["ALL-DONE"]: assert marker in text, marker
    assert "QUICK-DONE:" in text and "QUICK-DONE:" in read("references/slice-quick.md")

def test_loop_scripts_read_the_same_markers():
    for script in SCRIPTS:
        text = read(script)
        for marker in LOOP_MARKERS: assert marker in text, (script, marker)
        assert "rebuild" not in text.lower(), script

def test_command_files_are_copied_and_read_under_one_path():
    command = COMMAND.read_text(encoding="utf-8")
    skill = read("SKILL.md")
    for source, target in COPIED.items():
        assert (SKILL / "references" / source).is_file(), source
        assert target in command, target
        assert f"`references/{source}` → `{target}`" in skill, source

def test_command_stays_short():
    """A slice session loads this file whole; close, parallel and quick live in files of their own."""
    lines = len(COMMAND.read_text(encoding="utf-8").splitlines())
    assert lines <= 250, lines

def test_loop_scripts_define_no_function_twice():
    """A second slice_numbers() silently replaced the first and the bash loop read branches instead of the slice list."""
    for script, pattern in (("assets/slice-loop.sh", r"^([a-z_]+)\(\) \{"), ("assets/slice-loop.ps1", r"^function ([A-Za-z-]+)")):
        names = re.findall(pattern, read(script), re.M)
        assert len(names) == len(set(names)), (script, sorted(n for n in set(names) if names.count(n) > 1))

def test_every_slice_runs_on_its_own_model():
    assert '"model"' in COMMAND.read_text(encoding="utf-8") and "claude --model" in read("references/slice-parallel.md")
    for script in SCRIPTS: assert "--model" in read(script), script
    assert '"model"' in read("scripts/render_slices.py") and '"model"' in read("references/templates.md")

def test_no_personal_or_absolute_paths():
    for path in SKILL.rglob("*"):
        if path.is_file():
            assert not re.search(r"[A-Za-z]:\\Users|/home/|/Users/|@gmail", path.read_text(encoding="utf-8", errors="ignore")), path

def test_release_version_is_consistent():
    manifest = json.loads((ROOT / "plugins/vibe-coding/.claude-plugin/plugin.json").read_text(encoding="utf-8"))["version"]
    skill = re.search(r'^\s+version: "([^"]+)"', read("SKILL.md"), re.M).group(1)
    changelog = re.search(r"^## (\S+) – \d{4}-\d{2}-\d{2}", (ROOT / "plugins/vibe-coding/CHANGELOG.md").read_text(encoding="utf-8"), re.M).group(1)
    assert manifest == skill == changelog, (manifest, skill, changelog)

def test_marketplace_validation_is_not_strict_but_the_plugins_are():
    """slice-board carries no version on purpose (every commit is an update), so only the marketplace check tolerates warnings."""
    workflow = (ROOT / ".github/workflows/validate.yml").read_text(encoding="utf-8")
    assert "claude plugin validate . &&" in workflow
    assert "claude plugin validate --strict plugins/vibe-rebuild" in workflow and "claude plugin validate --strict plugins/vibe-coding" in workflow
    assert "validate --strict ." not in workflow

if __name__ == "__main__":
    for name, fn in list(globals().items()):
        if name.startswith("test_"): fn(); print("ok  ", name)
