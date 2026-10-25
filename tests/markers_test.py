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

def test_command_offers_parallel_sessions_outside_auto():
    text = (SKILL / "references/slice-command.md").read_text(encoding="utf-8")
    section = text.split("## 7. Parallel slices", 1)[1]
    assert text.count("(section 7)") >= 3, "status, nothing and the close of a slice point to section 7"
    assert "never in auto mode" in section and "Offer, never start unasked" in section
    assert "Never two sessions on one slice" in section and "ready-to-paste prompt" in section

def test_loop_scripts_read_the_same_markers():
    for name in ("slice-loop.sh", "slice-loop.ps1"):
        text = (SKILL / f"assets/{name}").read_text(encoding="utf-8")
        for m in ("PLAN:", "NEEDS-DECISION:", "SLICE-DONE:", "SLICE-OPEN:", "ROUND-DONE:", "ROUND-OPEN:"): assert m in text, (name, m)
        assert "/slice" in text and "work/_slices.json" in text and "rebuild" not in text.lower()

def test_every_slice_runs_on_its_own_model():
    """A slice runs on the model of its "model" field in _slices.json – never on the model of the session that starts it."""
    command = (SKILL / "references/slice-command.md").read_text(encoding="utf-8")
    assert '"model"' in command and "work/_slices.json" in command
    parallel = " ".join(command.split("## 7. Parallel slices", 1)[1].split())  # the command is hard-wrapped
    assert "never the model of this session" in parallel and "claude --model" in parallel
    for name in ("slice-loop.sh", "slice-loop.ps1"):
        assert "--model" in (SKILL / f"assets/{name}").read_text(encoding="utf-8"), name
    skill = (SKILL / "SKILL.md").read_text(encoding="utf-8")
    assert "`model`" in skill and "cheapest" in skill and "claude --model" in skill
    intake = (SKILL / "references/intake.md").read_text(encoding="utf-8")
    assert "## Model per slice" in intake and "`haiku`" in intake and "`sonnet`" in intake and "`opus`" in intake
    templates = (SKILL / "references/templates.md").read_text(encoding="utf-8")
    assert '"model"' in templates
    renderer = (SKILL / "scripts/render_slices.py").read_text(encoding="utf-8")
    assert '"model"' in renderer

def test_templates_fix_the_formats():
    text = (SKILL / "references/templates.md").read_text(encoding="utf-8")
    assert "Status: open" in text and "| NN " in text and '"round"' in text and "work/conventions.md" in text

def test_no_personal_or_absolute_paths():
    for p in SKILL.rglob("*"):
        if p.is_file():
            t = p.read_text(encoding="utf-8", errors="ignore")
            assert not re.search(r"[A-Za-z]:\\Users|/home/|/Users/|@gmail", t), p

def _section(start, end=None):
    """The command text between two headings, whitespace normalised (the command is hard-wrapped)."""
    text = (SKILL / "references/slice-command.md").read_text(encoding="utf-8")
    body = text.split(start, 1)[1]
    if end: body = body.split(end, 1)[0]
    return " ".join(body.split())

def test_worktree_recipe_is_prescribed_in_section_3():
    section = _section("## 3. Plan and build the slice", "## 4. Close the slice")
    assert "git worktree add .claude/worktrees/slice-NN -b slice-NN <integration branch>" in section
    assert ".git/info/exclude" in section and "only where it follows this recipe" in section
    assert "The squash always runs in the main checkout" in section

def test_squash_checklist_runs_in_order_in_section_4():
    section = _section("## 4. Close the slice", "## 5. Close the round")
    steps = ["merge the integration branch into slice-NN", "git merge --squash slice-NN", "<<<<<<<", "every line of both sides", "Result:", "never run in one command"]
    for step in steps: assert step in section, step
    positions = [section.index(step) for step in steps]
    assert positions == sorted(positions), "the squash checklist runs out of order"

def test_red_under_load_is_load_and_pipes_hide_exit_codes():
    section = _section("## 4. Close the slice", "## 5. Close the round")
    assert "green when run alone" in section and "is load, not a regression" in section and "Surprises" in section
    assert "`| tail`" in section and "&&" in section and "exit code" in section

def test_commit_messages_are_passed_with_commit_f():
    assert "git commit -F <file>" in _section("## 3. Plan and build the slice", "## 4. Close the slice")
    section = _section("## 4. Close the slice", "## 5. Close the round")
    assert "git commit -F <file>" in section and "never inline" in section

if __name__ == "__main__":
    for name, fn in list(globals().items()):
        if name.startswith("test_"): fn(); print("ok  ", name)
