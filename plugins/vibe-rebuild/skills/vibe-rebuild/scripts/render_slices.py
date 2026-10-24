#!/usr/bin/env python3
"""Render slice files from a JSON list.

Usage: python3 render_slices.py <_slices.json> <output_dir> [--lang en|de]
Entry format: see references/templates.md (_slices.json).
--lang sets the language of headings, prompt and Definition of Done (default: en).
"""
import json
import pathlib
import sys

TEMPLATES = {
    "en": """# Slice {nr} – {name}

**Goal:** {goal}
**PRD reference:** {prd}
**Depends on:** {deps}

## Scope
{scope}

## Prompt
```
Read CLAUDE.md, rebuild/GLOSSARY.md, rebuild/research.md and the rebuild/PRD.md sections "{prd}".
Implement slice {nr} "{name}" (this file).
0. If this slice needs a library or pattern rebuild/research.md does not cover,
   look up its current documentation first and add the findings to rebuild/research.md.
1. First present a plan (files, classes, tests) with a section "Assumptions (confirm on approval)"
   for every open point and a short "Review focus", and wait for approval.
2. Write this slice's acceptance and parity tests as failing tests (RED).
3. Implement the minimum to get green, then refactor. Follow every rule in CLAUDE.md.
4. Check the Definition of Done and report any deviations: deviations from the plan at the top of
   the plan file, from the original in rebuild/parity/deviations.md, and what the docs did not say
   under "Findings per slice" in rebuild/research.md.
```

## Definition of Done
- [ ] Acceptance criteria green as tests
- [ ] Parity cases green: {parity}
- [ ] Build without warnings, architecture tests green
- [ ] No file > 300 lines, no new packages without approval
- [ ] No dead code, no TODOs without an issue
- [ ] Deviations and findings recorded (plan, deviations.md, research.md)

## Non-goals
{non_goals}
""",
    "de": """# Slice {nr} – {name}

**Ziel:** {goal}
**PRD-Bezug:** {prd}
**Hängt ab von:** {deps}

## Umfang
{scope}

## Prompt
```
Lies CLAUDE.md, rebuild/GLOSSARY.md, rebuild/research.md und die Abschnitte "{prd}" in rebuild/PRD.md.
Setze Slice {nr} "{name}" um (diese Datei).
0. Braucht diese Slice eine Bibliothek oder ein Muster, das rebuild/research.md nicht abdeckt,
   lies zuerst die aktuelle Dokumentation und ergänze die Erkenntnisse in rebuild/research.md.
1. Stelle zuerst einen Plan vor (Dateien, Klassen, Tests) mit einem Abschnitt
   „Annahmen (bei Freigabe bestätigen)“ für jeden offenen Punkt und einem kurzen „Review-Fokus“,
   und warte auf Freigabe.
2. Schreibe die Abnahme- und Parity-Tests dieser Slice als fehlschlagende Tests (ROT).
3. Implementiere das Minimum bis grün, dann aufräumen. Halte jede Regel in CLAUDE.md ein.
4. Prüfe die Definition of Done und melde Abweichungen: Abweichungen vom Plan oben in der
   Plan-Datei, vom Original in rebuild/parity/deviations.md, und was die Doku nicht sagte
   unter „Findings per slice“ in rebuild/research.md.
```

## Definition of Done
- [ ] Abnahmekriterien als Tests grün
- [ ] Parity-Fälle grün: {parity}
- [ ] Build ohne Warnungen, Architekturtests grün
- [ ] Keine Datei > 300 Zeilen, keine neuen Pakete ohne Freigabe
- [ ] Kein toter Code, keine TODOs ohne Issue
- [ ] Abweichungen und Befunde festgehalten (Plan, deviations.md, research.md)

## Nicht in dieser Slice
{non_goals}
""",
}

REQUIRED = ("nr", "slug", "name", "goal", "prd", "deps", "scope", "parity", "non_goals")


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
        scope = "\n".join(f"- {item}" for item in s["scope"])
        text = template.format(**{**s, "scope": scope})
        (out / f"{s['nr']}-{s['slug']}.md").write_text(text, encoding="utf-8")
    print(f"Wrote {len(slices)} slices to {out} ({lang})")
    return 0


if __name__ == "__main__":
    sys.exit(main())
