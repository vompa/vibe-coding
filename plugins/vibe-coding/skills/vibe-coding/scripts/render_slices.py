#!/usr/bin/env python3
"""Render slice files from a JSON list.

Usage: python3 render_slices.py <_slices.json> <output_dir> [--lang en|de]
Entry fields (see references/templates.md, _slices.json):
  required: nr, slug, name, goal, deps, scope (list), non_goals
  optional text (default: an en dash): round, source, model, ids
    (round also names the round record the prompt points to; without it the prompt
    points to the open round record in work/rounds/; model is the cheapest model tier
    the slice needs – the loop and parallel sessions start the slice on it; ids is the
    range of finding ids reserved for new findings of the slice, e.g. "B84–B89")
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
**Model:** {model}
**Ids for new findings:** {ids}

## Scope
{scope}

## Patterns to mirror
{mirror}

## NOT building
{not_building}

## Prompt
```
Read CLAUDE.md, work/conventions.md, {round_ref} and this slice file.
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
**Modell:** {model}
**IDs für neue Befunde:** {ids}

## Umfang
{scope}

## Muster übernehmen
{mirror}

## NICHT bauen
{not_building}

## Prompt
```
Lies CLAUDE.md, work/conventions.md, {round_ref} und diese Slice-Datei.
Setze Slice {nr} "{name}" um (diese Datei).
1. Stelle zuerst einen Plan vor (Dateien, Klassen, Tests) mit einem Abschnitt
   „Annahmen (bei Freigabe bestätigen)“ für jeden offenen Punkt und einem kurzen „Review-Fokus“,
   speichere ihn unter work/plans/ und warte auf Freigabe.
2. Schreibe die Abnahmetests dieser Slice als fehlschlagende Tests (ROT).
3. Implementiere das Minimum bis grün. Halte jede Regel in CLAUDE.md und work/conventions.md ein.
4. Prüfe die Definition of Done. Halte Entscheidungen, Überraschungen und zurückgestellte
   Kleinigkeiten in der Rundenakte und in der Protokolldatei fest, die work/conventions.md nennt.
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

# Language-dependent pieces that are filled in code rather than in the template:
# the prefix of manual check items and the prompt's pointer to the round record
# (a glob for a given round, otherwise a description of how to find the open one).
PHRASES = {
    "en": {
        "manual": "Manual",
        "round_ref": "the round record work/rounds/{round}-*.md",
        "open_round_ref": 'the open round record in work/rounds/ (first line "Status: open")',
    },
    "de": {
        "manual": "Manuell",
        "round_ref": "die Rundenakte work/rounds/{round}-*.md",
        "open_round_ref": "die offene Rundenakte in work/rounds/ (erste Zeile „Status: open“)",
    },
}

REQUIRED = ("nr", "slug", "name", "goal", "deps", "scope", "non_goals")
OPTIONAL_TEXT = ("round", "source", "model", "ids")
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
    phrases = PHRASES[lang]
    round_id = entry.get("round")
    round_ref = (phrases["round_ref"].format(round=round_id) if round_id
                 else phrases["open_round_ref"])
    return {
        **entry,
        **{key: entry.get(key) or EMPTY for key in OPTIONAL_TEXT},
        "round_ref": round_ref,
        "scope": bullets(entry["scope"]),
        **{key: bullets(entry.get(key)) for key in OPTIONAL_LISTS},
        "checks": checkboxes(entry.get("acceptance"))
        + checkboxes(entry.get("manual"), f"{phrases['manual']}: "),
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
        # newline="\n" keeps LF on every platform (write_text would write CRLF on Windows).
        with open(out / f"{s['nr']}-{s['slug']}.md", "w", encoding="utf-8", newline="\n") as f:
            f.write(text)
    print(f"Wrote {len(slices)} slices to {out} ({lang})")
    return 0


if __name__ == "__main__":
    sys.exit(main())
