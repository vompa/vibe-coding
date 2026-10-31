#!/usr/bin/env python3
"""Render slice files from a JSON list.

Usage: python3 render_slices.py <_slices.json> <output_dir> [--lang en|de]
Entry format: see references/templates.md (_slices.json).
--lang sets the language of headings, prompt and Definition of Done (default: en).
Optional field "acs" (list or comma-separated goal-contract criteria) defaults to "–".
"""
import json
import pathlib
import sys

TEMPLATES = {
    "en": """# Slice {nr} – {name}

**Goal:** {goal}
**PRD reference:** {prd}
**Depends on:** {deps}
**Goal criteria:** {acs}

## Scope
{scope}

## Prompt
```
Read CLAUDE.md, the approved goal contract in rebuild/goal/, rebuild/GLOSSARY.md, rebuild/research.md
and the rebuild/PRD.md sections "{prd}". Implement slice {nr} "{name}" (this file).
The goal contract is read-only: a criterion that cannot be met becomes a change request, never a weaker test.
0. If this slice needs a library or pattern rebuild/research.md does not cover,
   look up its current documentation first and add the findings to rebuild/research.md.
1. First present a plan (files, classes, tests) with a section "Assumptions (confirm on approval)"
   for every open point, how each goal criterion ({acs}) will be proven, and a short "Review focus",
   and wait for approval. Then: python3 .claude/scripts/evidence.py start {nr}
2. Write this slice's acceptance and parity tests as failing tests (RED) and log the red run:
   evidence.py run {nr} red -- <test command>
3. Implement the minimum to get green, then refactor. Follow every rule in CLAUDE.md.
   Log the full suite (evidence.py run {nr} suite -- <test command>) and each goal criterion
   (evidence.py run {nr} ac:<id> -- <check>).
4. Cold review by a fresh subagent that did not build this slice (see /rebuild), then
   evidence.py check {nr} must print EVIDENCE OK. "Done" is what is evidenced, not what is claimed.
5. Check the Definition of Done and report any deviations: deviations from the plan at the top of
   the plan file, from the original in rebuild/parity/deviations.md, and what the docs did not say
   under "Findings per slice" in rebuild/research.md.
```

## Definition of Done
- [ ] Acceptance criteria green as tests
- [ ] Parity cases green: {parity}
- [ ] Evidence complete: `evidence.py check {nr}` → EVIDENCE OK (red run, suite, cold review, goal criteria: {acs})
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
**Zielkriterien:** {acs}

## Umfang
{scope}

## Prompt
```
Lies CLAUDE.md, den freigegebenen Zielvertrag in rebuild/goal/, rebuild/GLOSSARY.md, rebuild/research.md
und die Abschnitte "{prd}" in rebuild/PRD.md. Setze Slice {nr} "{name}" um (diese Datei).
Der Zielvertrag ist schreibgeschützt: Ein unerreichbares Kriterium wird ein Change Request, nie ein schwächerer Test.
0. Braucht diese Slice eine Bibliothek oder ein Muster, das rebuild/research.md nicht abdeckt,
   lies zuerst die aktuelle Dokumentation und ergänze die Erkenntnisse in rebuild/research.md.
1. Stelle zuerst einen Plan vor (Dateien, Klassen, Tests) mit einem Abschnitt
   „Annahmen (bei Freigabe bestätigen)“ für jeden offenen Punkt, dem Nachweisweg je Zielkriterium
   ({acs}) und einem kurzen „Review-Fokus“, und warte auf Freigabe.
   Danach: python3 .claude/scripts/evidence.py start {nr}
2. Schreibe die Abnahme- und Parity-Tests dieser Slice als fehlschlagende Tests (ROT) und protokolliere
   den roten Lauf: evidence.py run {nr} red -- <Testbefehl>
3. Implementiere das Minimum bis grün, dann aufräumen. Halte jede Regel in CLAUDE.md ein.
   Protokolliere die ganze Suite (evidence.py run {nr} suite -- <Testbefehl>) und jedes Zielkriterium
   (evidence.py run {nr} ac:<id> -- <Prüfung>).
4. Kalt-Review durch einen frischen Subagenten, der diese Slice nicht gebaut hat (siehe /rebuild), dann
   muss evidence.py check {nr} EVIDENCE OK melden. Fertig ist, was belegt ist, nicht was behauptet wird.
5. Prüfe die Definition of Done und melde Abweichungen: Abweichungen vom Plan oben in der
   Plan-Datei, vom Original in rebuild/parity/deviations.md, und was die Doku nicht sagte
   unter „Findings per slice“ in rebuild/research.md.
```

## Definition of Done
- [ ] Abnahmekriterien als Tests grün
- [ ] Parity-Fälle grün: {parity}
- [ ] Belege vollständig: `evidence.py check {nr}` → EVIDENCE OK (roter Lauf, Suite, Kalt-Review, Zielkriterien: {acs})
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
        acs = s.get("acs") or "–"
        acs = ", ".join(acs) if isinstance(acs, list) else str(acs)
        text = template.format(**{**s, "scope": scope, "acs": acs or "–"})
        (out / f"{s['nr']}-{s['slug']}.md").write_text(text, encoding="utf-8")
    print(f"Wrote {len(slices)} slices to {out} ({lang})")
    return 0


if __name__ == "__main__":
    sys.exit(main())
