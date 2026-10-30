# tests/render_slices_test.py
import json, pathlib, subprocess, sys, tempfile
SCRIPT = pathlib.Path(__file__).resolve().parent.parent / "plugins/vibe-coding/skills/vibe-coding/scripts/render_slices.py"
FULL = {"nr": "05", "slug": "labels", "name": "Field labels", "goal": "Every field has a label.", "round": "R01",
        "source": "W-Muster 1, W1, W6", "deps": "–", "model": "haiku", "ids": "B84–B89", "scope": ["Login", "Join"],
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
    for heading in ("**Round:** R01", "**Source:** W-Muster 1, W1, W6", "**Model:** haiku", "## Patterns to mirror", "- Views/CustomerContactForm.axaml:40-58 FormField usage",
                    "## NOT building", "- New controls", "- [ ] Given the login screen When", "- [ ] Manual: Login: Tab through", "work/conventions.md", "work/rounds/R01"):
        assert heading in text, heading

def test_optional_fields_default_to_dash():
    code, files = render([MINIMAL])
    text = files["100-sweep.md"]
    assert code == 0 and "{" not in text
    assert "**Round:** –" in text and "**Source:** –" in text and "**Model:** –" in text
    assert "## Patterns to mirror\n–" in text and "## NOT building\n–" in text

def test_german_headings():
    code, files = render([FULL], "de")
    text = files["05-labels.md"]
    assert code == 0 and "## Muster übernehmen" in text and "## NICHT bauen" in text and "**Hängt ab von:** –" in text
    assert "**Modell:** haiku" in text

def test_reserved_ids_are_rendered():
    """The range of finding ids a slice may give new findings (parallel slices never pick the same id)."""
    code, files = render([FULL])
    assert code == 0 and "**Ids for new findings:** B84–B89" in files["05-labels.md"]
    code, files = render([FULL], "de")
    assert "**IDs für neue Befunde:** B84–B89" in files["05-labels.md"]
    code, files = render([MINIMAL])
    assert "**Ids for new findings:** –" in files["100-sweep.md"]

def test_check_level_is_rendered():
    """A slice may check more or less often than its round; a dash keeps the round's level."""
    code, files = render([{**FULL, "check_level": 4}])
    assert code == 0 and "**Check level:** 4" in files["05-labels.md"]
    code, files = render([{**FULL, "check_level": "2"}], "de")
    assert "**Prüfstufe:** 2" in files["05-labels.md"]
    code, files = render([MINIMAL])
    assert "**Check level:** –" in files["100-sweep.md"]

def test_expected_files_are_rendered():
    """The files a slice expects to change: parallel slices that share one are not started together."""
    entry = {**FULL, "files": ["src/Calendar/EntryPreview.cs", "web/src/help/"]}
    code, files = render([entry])
    assert code == 0 and "## Files expected to change\n- src/Calendar/EntryPreview.cs\n- web/src/help/" in files["05-labels.md"]
    code, files = render([entry], "de")
    assert "## Voraussichtlich geänderte Dateien\n- src/Calendar/EntryPreview.cs" in files["05-labels.md"]
    code, files = render([MINIMAL])
    assert "## Files expected to change\n–" in files["100-sweep.md"]

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
