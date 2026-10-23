# Vorlagen

## PRD.md
```
# PRD – <Produktname> (Neubau)
> Beschreibt was, nicht wie. Begriffe: GLOSSARY.md. Weiter gültige Quelldokumente: <Liste>.
> Bei Widerspruch gilt: <Quellen-Rangfolge>.

## Zweck            (2–3 Sätze)
## Grundsätze       (G1…Gn – gelten für jedes Feature)
## Nutzer           (Rolle | sieht/darf | typische Aufgaben)
## Features
### F1 <Name>
**Story**: Als <Rolle> will ich <Ziel>, damit <Nutzen>.
- AK1 Given … When … Then … (exakte Zahlen, wenn bekannt)
- Randfälle: …
- Fehler: …
## API (Vertrag)    (Routen/Operationen kurz, Fehlerformat)
## Bewusst behobene Legacy-Fehler   (dürfen in der Parität abweichen)
## Nicht-Ziele
```

## GLOSSARY.md
```
| Begriff | Code | Bedeutung |
```

## CLAUDE.md (Zielrepo)
```
# CLAUDE.md – <Produkt> (Neubau)
<Zweck in 2–3 Sätzen>; Verweis auf PRD.md, GLOSSARY.md; Ziel = Parität laut parity/.

## Architektur       (Projekt-/Modulbaum mit Abhängigkeitspfeilen; wie erzwungen: Architekturtests, Analyzer)
## Harte Regeln      (≤300 Zeilen/Datei, eine Verantwortung, Konstanten einmal, keine Secrets,
                      keine neuen Pakete ohne Rückfrage, Fachlogik nur an einer Stelle, typisierte Fehler)
## Verboten (Legacy) (konkrete Befunde aus analysis.md)
## Befehle           (exakt ausführbar: build, test, parity, run, lint)
## Arbeitsweise      (Slice lesen → Plan → failing Tests → Code → DoD → Commit; Unklarheit = fragen)
```

## parity/README.md
```
# Paritäts-Harness
## Drei Arten (Fachvertrag | Schnittstellenvertrag | implementierungsgebunden – nicht übernehmen)
## Aufzeichnung vom Original (Startkonfiguration, deterministische Fallbacks, Uhr anhalten, fixtures/<bereich>/<fall>.json)
## Normalisierung     (Ids, Tokens, Dauer, Realzeit-Zeitstempel → Platzhalter)
## Nicht deterministische Teile (Fake-Modell, Stubs)
## Abweichungsprotokoll (deviations.md: Fall | Original | Neubau | Bewertung)
```

## _slices.json (Eingabe für scripts/render_slices.py)
```json
[
  {
    "nr": "00", "slug": "scaffold", "name": "Gerüst",
    "goal": "Lauffähige, leere Solution mit allen Gates und Paritäts-Harness.",
    "prd": "Grundsätze, CLAUDE.md", "deps": "–",
    "scope": ["Solution + Projekte", "Architekturtests", "CI", "Paritäts-Harness"],
    "parity": "Architekturtests grün auf leerer Solution",
    "non_goals": "Fachlogik"
  }
]
```
