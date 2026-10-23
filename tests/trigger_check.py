#!/usr/bin/env python3
"""Misst, wie zuverlässig der installierte Skill auslöst.

Treffer = Claudes erster Tool-Aufruf ist `Skill` mit einem Namen, der den Skill-Namen enthält.
Voraussetzung: Claude Code (`claude`) installiert, angemeldet, Plugin installiert.

Aufruf:
  python3 tests/trigger_check.py tests/trigger-eval.json \
      [--runs 3] [--workers 6] [--model <modell-id>] [--skill vibe-rebuild] [--out result.json]

Hinweis: Der Optimierer des skill-creator zählt nur seine eigene Testkopie als Treffer.
Ist das Plugin bereits installiert, gewinnt der installierte Skill und der Optimierer meldet
fälschlich 0 %. Dieses Skript misst deshalb direkt gegen den installierten Skill.
"""
import argparse
import concurrent.futures as cf
import json
import os
import subprocess
import sys


def first_action(query: str, model: str | None, cwd: str) -> str:
    cmd = ["claude", "-p", query, "--output-format", "stream-json", "--verbose", "--max-turns", "1"]
    if model:
        cmd += ["--model", model]
    env = {k: v for k, v in os.environ.items() if k != "CLAUDECODE"}
    try:
        p = subprocess.run(cmd, capture_output=True, text=True, cwd=cwd, env=env, timeout=240)
    except subprocess.TimeoutExpired:
        return "timeout"
    for line in p.stdout.splitlines():
        try:
            e = json.loads(line)
        except json.JSONDecodeError:
            continue
        if e.get("type") == "assistant":
            for c in e["message"].get("content", []):
                if c.get("type") == "tool_use":
                    if c["name"] == "Skill":
                        return "skill:" + c["input"].get("skill", "")
                    return "tool:" + c["name"]
    return "no-tool"


def main() -> int:
    ap = argparse.ArgumentParser()
    ap.add_argument("eval_set")
    ap.add_argument("--runs", type=int, default=3)
    ap.add_argument("--workers", type=int, default=6)
    ap.add_argument("--model")
    ap.add_argument("--skill", default="vibe-rebuild")
    ap.add_argument("--cwd", default=os.getcwd())
    ap.add_argument("--out")
    a = ap.parse_args()

    items = json.load(open(a.eval_set, encoding="utf-8"))
    res: dict[int, list[str]] = {i: [] for i in range(len(items))}
    with cf.ThreadPoolExecutor(a.workers) as ex:
        futs = {ex.submit(first_action, it["query"], a.model, a.cwd): i
                for i, it in enumerate(items) for _ in range(a.runs)}
        for f in cf.as_completed(futs):
            res[futs[f]].append(f.result())

    out, ok = [], 0
    for i, it in enumerate(items):
        hits = sum(a.skill in r for r in res[i])
        rate = hits / a.runs
        passed = rate >= 0.5 if it["should_trigger"] else rate < 0.5
        ok += passed
        out.append({"query": it["query"], "should_trigger": it["should_trigger"],
                    "hits": hits, "runs": a.runs, "pass": passed, "first_actions": res[i]})
        print(f"{'PASS' if passed else 'FAIL'} {hits}/{a.runs} should={it['should_trigger']}: "
              f"{it['query'][:70]}")
    print(f"TOTAL {ok}/{len(items)}")
    if a.out:
        json.dump(out, open(a.out, "w", encoding="utf-8"), ensure_ascii=False, indent=1)
    return 0 if ok == len(items) else 1


if __name__ == "__main__":
    sys.exit(main())
