#!/usr/bin/env python3
"""Rendert Slice-Dateien aus einer JSON-Liste.

Aufruf: python3 render_slices.py <_slices.json> <ausgabeordner>
Format der Einträge: siehe references/templates.md (_slices.json).
"""
import json
import pathlib
import sys

TEMPLATE = """# Slice {nr} – {name}

**Ziel:** {goal}
**PRD-Bezug:** {prd}
**Abhängig von:** {deps}

## Umfang
{scope}

## Prompt
```
Lies CLAUDE.md, GLOSSARY.md und die PRD-Abschnitte „{prd}“.
Setze Slice {nr} „{name}“ um (diese Datei).
1. Lege zuerst einen Plan vor (Dateien, Klassen, Tests) und warte auf Freigabe.
2. Schreibe die Akzeptanz- und Paritätstests dieses Slice als failing Tests (RED).
3. Implementiere minimal bis grün, dann refaktorieren. Halte alle Regeln aus CLAUDE.md ein.
4. Prüfe die Definition of Done und berichte Abweichungen.
```

## Definition of Done
- [ ] Akzeptanzkriterien als Tests grün
- [ ] Paritätsfälle grün: {parity}
- [ ] Build ohne Warnungen, Architekturtests grün
- [ ] Keine Datei > 300 Zeilen, keine neuen Pakete ohne Freigabe
- [ ] Kein toter Code, keine TODOs ohne Issue

## Nicht-Ziele
{non_goals}
"""

REQUIRED = ("nr", "slug", "name", "goal", "prd", "deps", "scope", "parity", "non_goals")


def main() -> int:
    if len(sys.argv) != 3:
        print(__doc__)
        return 2
    slices = json.loads(pathlib.Path(sys.argv[1]).read_text(encoding="utf-8"))
    out = pathlib.Path(sys.argv[2])
    out.mkdir(parents=True, exist_ok=True)
    for s in slices:
        missing = [k for k in REQUIRED if k not in s]
        if missing:
            print(f"Slice {s.get('nr', '?')}: fehlende Felder {missing}", file=sys.stderr)
            return 1
        scope = "\n".join(f"- {item}" for item in s["scope"])
        text = TEMPLATE.format(**{**s, "scope": scope})
        (out / f"{s['nr']}-{s['slug']}.md").write_text(text, encoding="utf-8")
    print(f"{len(slices)} Slices nach {out} geschrieben")
    return 0


if __name__ == "__main__":
    sys.exit(main())
