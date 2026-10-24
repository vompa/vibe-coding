#!/usr/bin/env python3
"""Render slice files from a JSON list.

Usage: python3 render_slices.py <_slices.json> <output_dir> [--lang en|de]
Entry fields (see references/templates.md, _slices.json):
  required: nr, slug, name, goal, deps, scope (list), non_goals
  optional text (default: an en dash): round, source
  optional lists (rendered as "- item", an en dash when missing or empty):
    mirror (patterns to copy as file:line), not_building,
    acceptance (Given/When/Then, rendered as checkboxes in the Definition of Done),
    manual (manual check items, rendered as "Manual: ..." checkboxes there)
Unknown fields are ignored.
--lang sets the language of headings, prompt and Definition of Done (default: en).
Exit codes: 0 success, 1 missing required field, 2 usage error.
"""
import json
import pathlib
import sys

# The {checks} line carries its own trailing newline per item, so an entry without
# acceptance or manual items leaves exactly one blank line before "Non-goals".
TEMPLATES = {
    "en": """# Slice {nr} – {name}

**Goal:** {goal}
**Round:** {round}
**Source:** {source}
**Depends on:** {deps}

## Scope
{scope}

## Patterns to mirror
{mirror}

## NOT building
{not_building}

## Prompt
```
Read CLAUDE.md, work/conventions.md, the round record work/rounds/{round}*.md and this slice file.
Implement slice {nr} "{name}" (this file).
1. First present a plan (files, classes, tests) with a section "Assumptions (confirm on approval)"
   for every open point and a short "Review focus", save it under work/plans/,
   and wait for approval.
2. Write this slice's acceptance tests as failing tests (RED).
3. Implement the minimum to get green. Follow every rule in CLAUDE.md and work/conventions.md.
4. Check the Definition of Done. Record decisions, surprises and deferred minors in the round
   record and in the protocol file that work/conventions.md names.
```

## Definition of Done
- [ ] Checks from work/conventions.md green
- [ ] No test weakened or skipped
- [ ] No new packages without approval
- [ ] Decisions recorded
{checks}
## Non-goals
{non_goals}
""",
    "de": """# Slice {nr} – {name}

**Ziel:** {goal}
**Runde:** {round}
**Quelle:** {source}
**Hängt ab von:** {deps}

## Umfang
{scope}

## Muster übernehmen
{mirror}

## NICHT bauen
{not_building}

## Prompt
```
Lies CLAUDE.md, work/conventions.md, die Rundendatei work/rounds/{round}*.md und diese Slice-Datei.
Setze Slice {nr} "{name}" um (diese Datei).
1. Stelle zuerst einen Plan vor (Dateien, Klassen, Tests) mit einem Abschnitt
   „Annahmen (bei Freigabe bestätigen)“ für jeden offenen Punkt und einem kurzen „Review-Fokus“,
   speichere ihn unter work/plans/ und warte auf Freigabe.
2. Schreibe die Abnahmetests dieser Slice als fehlschlagende Tests (ROT).
3. Implementiere das Minimum bis grün. Halte jede Regel in CLAUDE.md und work/conventions.md ein.
4. Prüfe die Definition of Done. Halte Entscheidungen, Überraschungen und zurückgestellte
   Kleinigkeiten in der Rundendatei und in der Protokolldatei fest, die work/conventions.md nennt.
```

## Definition of Done
- [ ] Prüfungen aus work/conventions.md grün
- [ ] Kein Test abgeschwächt oder übersprungen
- [ ] Keine neuen Pakete ohne Freigabe
- [ ] Entscheidungen festgehalten
{checks}
## Nicht in dieser Slice
{non_goals}
""",
}

MANUAL_LABEL = {"en": "Manual", "de": "Manuell"}

REQUIRED = ("nr", "slug", "name", "goal", "deps", "scope", "non_goals")
OPTIONAL_TEXT = ("round", "source")
OPTIONAL_LISTS = ("mirror", "not_building")
EMPTY = "–"


def bullets(items) -> str:
    """Render items as '- item' lines, or a dash when there are none."""
    return "\n".join(f"- {item}" for item in items or []) or EMPTY


def checkboxes(items, prefix: str = "") -> str:
    """Render items as '- [ ] item' lines, each ending with a newline."""
    return "".join(f"- [ ] {prefix}{item}\n" for item in items or [])


def build_fields(entry: dict, lang: str) -> dict:
    """Return the template fields for one entry; unknown entry fields pass through."""
    manual_prefix = f"{MANUAL_LABEL[lang]}: "
    return {
        **entry,
        **{key: entry.get(key) or EMPTY for key in OPTIONAL_TEXT},
        "scope": bullets(entry["scope"]),
        **{key: bullets(entry.get(key)) for key in OPTIONAL_LISTS},
        "checks": checkboxes(entry.get("acceptance"))
        + checkboxes(entry.get("manual"), manual_prefix),
    }


def main() -> int:
    args = sys.argv[1:]
    lang = "en"
    if "--lang" in args:
        i = args.index("--lang")
        if i + 1 >= len(args):
            print(__doc__)
            return 2
        lang = args[i + 1]
        del args[i:i + 2]
    if len(args) != 2:
        print(__doc__)
        return 2
    if lang not in TEMPLATES:
        print(f"Unknown language '{lang}', available: {', '.join(TEMPLATES)}. "
              "Render with en and translate.", file=sys.stderr)
        return 2
    template = TEMPLATES[lang]
    slices = json.loads(pathlib.Path(args[0]).read_text(encoding="utf-8"))
    out = pathlib.Path(args[1])
    out.mkdir(parents=True, exist_ok=True)
    for s in slices:
        missing = [k for k in REQUIRED if k not in s]
        if missing:
            print(f"Slice {s.get('nr', '?')}: missing fields {missing}", file=sys.stderr)
            return 1
        text = template.format(**build_fields(s, lang))
        (out / f"{s['nr']}-{s['slug']}.md").write_text(text, encoding="utf-8")
    print(f"Wrote {len(slices)} slices to {out} ({lang})")
    return 0


if __name__ == "__main__":
    sys.exit(main())
