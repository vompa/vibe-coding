---
name: vibe-rebuild
description: Erstellt aus einer bestehenden App (Repo, Codebasis, Legacy-System) einen Bauplan für den Neubau per Vibe Coding mit KI-Agenten – analysis.md, PRD, Glossar, CLAUDE.md, vertikale Slices mit fertigen Prompts und Paritätstests gegen das Original. Verwenden, wenn jemand eine vorhandene Anwendung mit Claude Code oder anderen Agenten neu bauen, migrieren, modernisieren oder auf einen anderen Stack portieren will, einen Rebuild- oder Migrationsplan, eine Spec aus bestehendem Code oder Brownfield-Vibe-Coding braucht – auch wenn „Vibe Coding“ nicht wörtlich fällt. Nicht für neue Apps ohne Altcode, einzelne Features oder reine Code-Reviews.
license: MIT
compatibility: Für Claude Code und Claude mit Dateizugriff und Subagenten; Skripte brauchen Python 3.10+.
metadata:
  author: vompa
  version: "1.0.0"
  language: de
---

# Vibe Rebuild – bestehende App per Vibe Coding neu bauen

Ziel: Aus einer bestehenden Codebasis einen Bauplan erzeugen, mit dem ein Coding-Agent die App Slice für Slice neu baut und dabei **nachweisbar gleichwertig** zum Original bleibt.
Der Skill extrahiert die *Absicht* der App (Verhalten, Verträge, Fachzahlen), nicht ihre Implementierung, und übernimmt keinen Code. Warum: Wer Code kopiert, kopiert die Altlasten mit; wer nur Verhalten und Verträge mitnimmt, kann sauber neu schneiden und trotzdem Parität beweisen.

## 0. Werkzeuge wählen

Kurz prüfen, was verfügbar ist, und dem Nutzer in einer Zeile sagen, was verwendet wird.

| Aufgabe | Bevorzugt | Fallback |
|---|---|---|
| Analyse | `feature-dev:code-explorer`-Agenten parallel; ein PRD-aus-Code-Skill falls vorhanden | `Explore`-Subagenten |
| Spec schärfen | `superpowers:brainstorming` | Rückfragen (max. 5) |
| Ausführung später | `superpowers:writing-plans` + `subagent-driven-development`, alternativ GitHub Spec Kit | Prompts in den Slice-Dateien |
| Skill verbessern | `skill-creator` | – |

Dieser Skill liefert den Plan; ausgeführt wird er in einer späteren Session im Zielrepo.

## 1. Eingaben (eine Runde, dann loslegen)

Repo/Pfad (nur lesen), Zielstack (Default: gleicher Stack, aktuelle Versionen), Scope, ob das Original lokal lauffähig ist.
Ist der Nutzer nicht da oder bittet um einen Testlauf: sinnvolle Annahmen treffen, als `[Annahme]` markieren, weitermachen.

## 2. Inventur (schnell, vor den Agenten)

```
python3 scripts/inventory.py <repo> > vibe-plan/_inventory.md
```
Liefert Projekte, Dateizahlen und Zeilen je Ordner, Dateien über 300 Zeilen, Testdateien und vorhandene Doku.
Daraus zwei Entscheidungen ableiten:

- **Vorhandene Spezifikation?** (`docs/`, `spec*`, `PRD*`, ADRs, Mockups, Kalibrier-/Fachdokumente). Wenn ja, ist sie die primäre Quelle der Absicht; Code und Tests belegen den Ist-Stand. Lege eine **Quellen-Rangfolge** fest (z. B. Fachdokument > Tests > Spec > Mockup > Kommentare) und schreibe sie ins PRD. Widersprüche zwischen Quellen sind normal und wertvoll – sammeln, nicht glätten.
- **Analyse-Schnitt**: 3–5 Bereiche entlang der Schichten bzw. Projekte (z. B. Domäne+Simulation, Daten/Persistenz, API/Integrationen, Frontend+Infra+Tests). Faustregel ein Agent je ~8–12k Zeilen.

## 3. Analyse → `vibe-plan/analysis.md`

Explorer-Agenten parallel starten, je Bereich einen, mit der Vorlage aus `references/explorer-prompt.md`. Sie liefern alle dasselbe Schema, das du zusammenführst:

```
# Analysis
## Stack & Laufzeit   ## Domäne   ## Features   ## Schnittstellen
## Nichtfunktionales  ## Bestehende Tests   ## Legacy-Befunde   ## Offene Fragen
```

Dieses Schema ist die Schnittstelle zu allen späteren Phasen – auch wenn ein externer Reverse-Engineering-Skill die Analyse liefert, wird sein Ergebnis zuerst in dieses Schema gebracht.

**Stichprobe vor dem Weiterbauen**: 3–5 harte Zahlen aus den Agentenberichten (Anzahl Tools/Endpunkte/Tests, Default-Grenzwerte) per `grep` gegen den Code prüfen. Subagenten schätzen Zählungen gern; ein falscher Wert im PRD wird später zum falschen Akzeptanzkriterium.

**Offene Fragen** in eine eigene `open-questions.md`, getrennt nach *architekturrelevant* (ändern Zielarchitektur oder Scope), *fachlich* und *entfällt im Neubau*, jeweils mit der getroffenen `[Annahme]`. Architekturrelevante Fragen vor dem Slicing dem Nutzer vorlegen, wenn er erreichbar ist; sonst mit Annahmen weiter und das im README deutlich sagen.

## 4. PRD & Glossar

`PRD.md`: Verhalten aus Nutzersicht – Zweck, Grundsätze, Nutzer/Rollen, Features mit Story und Given/When/Then-Akzeptanzkriterien, Randfälle, Fehlerverhalten, API-Vertrag in Kurzform, „Bewusst behobene Legacy-Fehler“, Nicht-Ziele. Keine Klassen- oder Dateinamen. Liegt eine gute Spec vor, nicht abschreiben, sondern auf sie verweisen und nur Akzeptanzkriterien ergänzen.
`GLOSSARY.md`: Begriff | Code-Bezeichner | Bedeutung. Der Agent benutzt nur diese Begriffe.

Vorlagen: `references/templates.md`.

## 5. Leitplanken → `vibe-plan/CLAUDE.md` (für das Zielrepo)

Zielarchitektur mit erlaubten Abhängigkeitsrichtungen – und wie sie **erzwungen** wird (Architekturtests, z. B. NetArchTest/ArchUnit, Analyzer-Regeln). Regeln, die nur im Text stehen, hält ein Agent über viele Sessions nicht durch.
Dazu: harte Regeln (Dateigröße, eine Verantwortung, Konstanten einmal, keine Secrets, keine neuen Pakete ohne Rückfrage), „Verboten“ = Legacy-Befunde, exakte Befehle, Arbeitsweise (Plan → Tests → Code, ein Slice pro Session, Commit pro grünem Slice).

## 6. Slicing → `vibe-plan/slices/NN-name.md`

Vertikal und nach Abhängigkeit geordnet; Slice 00 = Gerüst inkl. CI, Architekturtests und Paritäts-Harness. Orientierung: ein Slice ≈ eine Agent-Session (1–2 h), grob ein Slice je 1,5–2k Zeilen Original.
Slices als Liste in `vibe-plan/_slices.json` festhalten und rendern:
```
python3 scripts/render_slices.py vibe-plan/_slices.json vibe-plan/slices
```
Jeder Slice hat Ziel, PRD-Bezug, Abhängigkeiten, Umfang, fertigen Prompt (Plan zuerst, dann failing Tests, dann Code), Definition of Done mit den konkreten Paritätsfällen, Nicht-Ziele.

## 7. Parität → `vibe-plan/parity/`

Der zentrale Hebel. Paritätsfälle in drei Arten einteilen, weil sie unterschiedlich belastbar sind:

| Art | Beispiel | Im Neubau |
|---|---|---|
| **Fachvertrag** | Kennzahlen, Summen, Startzustände aus Fachdoku und Tests | hart prüfen |
| **Schnittstellenvertrag** | Statuscodes, Fehlerformate, Feldnamen, Ereignisreihenfolge | hart prüfen |
| **Implementierungsgebunden** | Prüfsummen über Zufallsgeneratoren, Byte-Snapshots, Timing | nicht übernehmen; im Neubau neu festlegen |

Quellen, in dieser Reihenfolge:
1. **Bestehende Tests des Originals** – meist die reichste Quelle; Assertions als Fälle übernehmen (Eingabe → erwartete Ausgabe).
2. **Aufzeichnung gegen das laufende Original** (Request/Response je Endpunkt und Rolle), volatile Felder normalisiert; Vergleich z. B. mit Verify/Approval-Tests.
3. Fachdokumente.

Nicht-deterministische Abhängigkeiten (LLM-Aufrufe, externe APIs, Zeit) nie live in Paritätstests: Fake/Stub mit Skript, deterministische Fallbacks aufzeichnen, Uhr anhalten.
`parity/README.md` beschreibt Harness, Aufzeichnung, Normalisierung und ein Abweichungsprotokoll (Bug im Neubau vs. bewusst behoben + PRD-Verweis).

## 8. Übergabe

`README.md` mit:
- **Einschätzung Neubau vs. Umbau** – ist das Original schon gut strukturiert und getestet, ist ein gezielter Umbau der Legacy-Befunde oft günstiger; dann sagen, welche Slices dafür reichen würden.
- Dateiübersicht, Abhängigkeitsgraph der Slices (was parallel geht), Startschritte, vorgesehener Execution-Skill.
- `checklist.md` (Slice × Plan/Tests rot/Grün/Parität/Commit).

Ergebnis als Ordner `vibe-plan/` (und gezippt) übergeben; das Original bleibt unverändert.

## Regeln

- Original nie verändern; nur lesen und Paritätstests ausführen.
- Keinen Code übernehmen – Verhalten, Datenverträge, Schnittstellen, Fachzahlen schon.
- Secrets, Connection Strings, personenbezogene Testdaten nie in den Plan; Platzhalter.
- Lieber eine markierte Annahme als eine stille Erfindung.

## Ausgabe-Struktur

```
vibe-plan/
  README.md  analysis.md  open-questions.md  PRD.md  GLOSSARY.md  CLAUDE.md  checklist.md
  slices/00-scaffold.md … NN-*.md
  parity/README.md  <bereich>-cases.md …
  _inventory.md  _slices.json
```
