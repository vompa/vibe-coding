#!/usr/bin/env python3
"""Render slice files from a JSON list.

Usage: python3 render_slices.py <_slices.json> <output_dir>
Entry format: see references/templates.md (_slices.json).
"""
import json
import pathlib
import sys

TEMPLATE = """# Slice {nr} – {name}

**Goal:** {goal}
**PRD reference:** {prd}
**Depends on:** {deps}

## Scope
{scope}

## Prompt
```
Read CLAUDE.md, GLOSSARY.md, research.md and the PRD sections "{prd}".
Implement slice {nr} "{name}" (this file).
0. If this slice needs a library or pattern research.md does not cover,
   look up its current documentation first and add the findings to research.md.
1. First present a plan (files, classes, tests) and wait for approval.
2. Write this slice's acceptance and parity tests as failing tests (RED).
3. Implement the minimum to get green, then refactor. Follow every rule in CLAUDE.md.
4. Check the Definition of Done and report any deviations.
```

## Definition of Done
- [ ] Acceptance criteria green as tests
- [ ] Parity cases green: {parity}
- [ ] Build without warnings, architecture tests green
- [ ] No file > 300 lines, no new packages without approval
- [ ] No dead code, no TODOs without an issue

## Non-goals
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
            print(f"Slice {s.get('nr', '?')}: missing fields {missing}", file=sys.stderr)
            return 1
        scope = "\n".join(f"- {item}" for item in s["scope"])
        text = TEMPLATE.format(**{**s, "scope": scope})
        (out / f"{s['nr']}-{s['slug']}.md").write_text(text, encoding="utf-8")
    print(f"Wrote {len(slices)} slices to {out}")
    return 0


if __name__ == "__main__":
    sys.exit(main())
