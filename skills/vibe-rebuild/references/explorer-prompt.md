# Vorlage: Prompt für einen Explorer-Agenten

Für jeden Analysebereich einen Agenten (`feature-dev:code-explorer`, sonst `Explore`) mit diesem Prompt starten – alle im selben Zug, damit sie parallel laufen. Platzhalter in `<…>` ersetzen.

```
Read-only analysis of the repo at <PFAD> (do NOT modify anything).
Scope: <Ordner/Projekte>, the related tests under <Testordner>, plus the sections of <vorhandene Spec/Doku> that concern this scope.

Goal: extract the INTENT (behaviour, contracts, business numbers), not the implementation,
so a coding agent could rebuild it from scratch. Answer in <Sprache des Nutzers>, Markdown,
exactly these headings, only what applies to your scope:

## Stack & Laufzeit      (packages + versions, run/build/test commands, ports, config defaults)
## Domäne                (entities, invariants, rules with exact formulas/thresholds; glossary candidates with 1-line definitions)
## Features              (each: purpose, entry point, modules, key behaviour)
## Schnittstellen        (APIs/routes, protocols, events, storage schema/keys, CLI, config keys – no secret values)
## Nichtfunktionales     (security, determinism, performance figures, limits, failure behaviour, telemetry)
## Bestehende Tests      (what each test file pins; which are usable as acceptance criteria / golden master;
                          flag tests that are tied to implementation details, e.g. checksums over RNG output)
## Legacy-Befunde        (what a rebuild should NOT copy: files >300 lines, mixed responsibilities, duplication,
                          dead/speculative code, spec-vs-code contradictions – each with file path and reason)
## Offene Fragen

Then add "Golden-Master-Kandidaten": concrete input → observable output pairs, with the exact numbers.
Say explicitly which files you did NOT read. Max ~1000 words.
```

## Hinweise
- Zahlen exakt übernehmen lassen (Grenzwerte, Defaults, Erwartungswerte aus Tests) – sie werden Akzeptanzkriterien.
- „Which files you did NOT read“ ist wichtig: Lücken landen in den offenen Fragen statt als stille Annahmen im PRD.
- Nach dem Zusammenführen Stichproben gegen den Code prüfen (siehe SKILL.md §3).
