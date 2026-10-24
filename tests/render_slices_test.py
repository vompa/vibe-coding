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

if __name__ == "__main__":
    for name, fn in list(globals().items()):
        if name.startswith("test_"):
            fn(); print("ok  ", name)
