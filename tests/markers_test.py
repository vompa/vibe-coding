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
