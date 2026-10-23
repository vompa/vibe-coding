# vibe-rebuild

**Bestehende App → Bauplan für den Neubau per Vibe Coding, mit Paritätstests gegen das Original.**

Ein [Agent Skill](https://agentskills.io) und Claude-Code-Plugin. Er liest eine bestehende Codebasis und erzeugt die Unterlagen, mit denen ein Coding-Agent (Claude Code o. Ä.) die App Slice für Slice neu baut – und nachweist, dass der Neubau sich verhält wie das Original.

> *English:* Turns an existing codebase into a rebuild plan for AI coding agents — analysis, PRD, glossary, CLAUDE.md guardrails, vertical slices with ready-to-run prompts, and parity tests against the original. The skill writes its output in German (it follows the user's language for questions).

## Was herauskommt

```
vibe-plan/
  README.md          Einschätzung Neubau vs. Umbau, Slice-Graph, Startschritte
  analysis.md        Stack, Domäne, Features, Schnittstellen, Tests, Legacy-Befunde
  open-questions.md  offene Fragen mit markierten Annahmen
  PRD.md             Verhalten aus Nutzersicht mit Given/When/Then
  GLOSSARY.md        verbindliche Begriffe
  CLAUDE.md          Leitplanken fürs Zielrepo (Architektur, harte Regeln, Befehle)
  slices/NN-*.md     je Slice: Ziel, Umfang, fertiger Prompt, Definition of Done
  parity/            Fachvertrag, Schnittstellenvertrag, Aufzeichnungsplan
  checklist.md
```

## Wie es arbeitet

1. **Inventur** per Skript: Projekte, Zeilen je Ordner, Dateien > 300 Zeilen, vorhandene Spec/Doku.
2. **Analyse** mit 3–5 parallelen Explorer-Agenten (bevorzugt `feature-dev:code-explorer`), festes Schema, Stichprobe der Zahlen gegen den Code.
3. **PRD, Glossar, CLAUDE.md** – vorhandene Spezifikationen werden als primäre Quelle genutzt, mit Quellen-Rangfolge bei Widersprüchen.
4. **Slicing** in vertikale, abhängigkeitsgeordnete Slices (je eine Agent-Session).
5. **Parität** in drei Arten: Fachvertrag und Schnittstellenvertrag werden hart geprüft; implementierungsgebundene Prüfsummen nicht übernommen. LLM-Teile nur mit Fake-Modell.

Für die Ausführung danach eignet sich [superpowers](https://github.com/obra/superpowers) (`writing-plans` → `subagent-driven-development`) oder GitHub Spec Kit.

## Installation

**Claude Code**
```bash
claude plugin marketplace add vompa/vibe-rebuild
claude plugin install vibe-rebuild@vompa
```
oder in einer Session: `/plugin install vibe-rebuild --marketplace vompa/vibe-rebuild`

**Claude.ai / andere Agenten:** den Ordner `skills/vibe-rebuild/` als Skill hochladen bzw. in das Skills-Verzeichnis des Agenten kopieren.

## Benutzung

Einfach beschreiben, was du vorhast – der Skill löst von selbst aus, z. B.:

- „Analysiere `github.com/acme/billing` und plane den Neubau in Go mit Claude Code.“
- „Unsere WebForms-Lagerverwaltung soll auf .NET 10 + Blazor – mach einen Plan, den der Agent abarbeiten kann, und sichere die Parität ab.“
- „Pflichtenheft und Umbaureihenfolge aus unserem Spring-Monolithen für die KI.“

Explizit: `/vibe-rebuild:vibe-rebuild <repo oder pfad>`

## Qualität

- Getestet an einem realen Projekt ([OPCAgentSample](https://github.com/vompa/OPCAgentSample), ~37k Zeilen .NET/Vue): 22 Slices, Paritätsfälle aus 700+ bestehenden Tests.
- Auslöse-Test (`tests/trigger-eval.json`, 10 positive und 10 knapp negative Anfragen, je 3 Läufe): **20/20**, 0 Fehlauslösungen.
  ```bash
  python3 tests/trigger_check.py tests/trigger-eval.json --runs 3
  ```

## Entwicklung

```bash
claude plugin validate --strict .
claude --plugin-dir .     # Plugin für eine Session laden
```
Neue Version: `version` in `.claude-plugin/plugin.json` und `metadata.version` im SKILL.md erhöhen, `CHANGELOG.md` ergänzen.

## Lizenz

MIT – siehe [LICENSE](LICENSE).
