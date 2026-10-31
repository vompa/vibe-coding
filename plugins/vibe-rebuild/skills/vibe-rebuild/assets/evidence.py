#!/usr/bin/env python3
"""Evidence for a slice: done is what is evidenced, not what is claimed.

Copied unchanged to .claude/scripts/evidence.py in the target repo. Run from the repo folder.

  python3 .claude/scripts/evidence.py start NN              stamp the slice start (keeps an existing stamp)
  python3 .claude/scripts/evidence.py run NN red -- <test command>       failing run before the change
  python3 .claude/scripts/evidence.py run NN suite -- <test command>     full suite, must exit 0
  python3 .claude/scripts/evidence.py run NN ac:AC-03 -- <command>       proof for one goal criterion
  python3 .claude/scripts/evidence.py add NN <node> --file <log> | --sha <commit> | --waived "<reason>"
  python3 .claude/scripts/evidence.py check NN              exit 0 only when every node is evidenced
  python3 .claude/scripts/evidence.py show NN               the same table, never fails

Nodes of a slice: red, suite, review, plus ac:<id> for every goal criterion the slice names in the
field "acs" of rebuild/_slices.json. Each node is open, claimed, evidenced or waived. Only these count:
- a log whose last non-empty line is "exit=0" ("exit=<not 0>" for red), written after the slice start
- a commit made after the slice start that is on a branch or tag
- "waived" with a reason (not allowed for suite and review)
- review: the cold reviewer's report rebuild/evidence/NN/review.md with one line "AC-xx: PASS" per goal
  criterion of the slice and "verdict=pass" as its last non-empty line
Anything else – a hand-written line in the record, a log from before the start – is "claimed" and does
not close the slice. Logs stay out of git (rebuild/evidence/**/*.log); the record NN.json is committed.
"""
import datetime as dt
import hashlib
import json
import pathlib
import re
import subprocess
import sys

EVIDENCE = pathlib.Path("rebuild/evidence")
SLICES = pathlib.Path("rebuild/_slices.json")
NO_WAIVER = {"suite", "review"}
SLACK = 2.0  # seconds: file systems round mtimes


def record_path(nr: str) -> pathlib.Path:
    return EVIDENCE / f"{nr}.json"


def load(nr: str) -> dict:
    path = record_path(nr)
    if not path.is_file():
        sys.exit(f"No evidence record for slice {nr}. Run: python3 .claude/scripts/evidence.py start {nr}")
    return json.loads(path.read_text(encoding="utf-8"))


def save(nr: str, rec: dict) -> None:
    EVIDENCE.mkdir(parents=True, exist_ok=True)
    record_path(nr).write_text(json.dumps(rec, indent=2, ensure_ascii=False) + "\n", encoding="utf-8")


def slice_acs(nr: str) -> list[str]:
    if not SLICES.is_file():
        return []
    for entry in json.loads(SLICES.read_text(encoding="utf-8")):
        if str(entry.get("nr")) == nr:
            acs = entry.get("acs", [])
            items = acs if isinstance(acs, list) else re.split(r"[,\s]+", str(acs))
            return [a.strip() for a in items if re.fullmatch(r"AC-[\w.-]+", a.strip())]
    return []


def required(nr: str) -> list[str]:
    return ["red", "suite", "review"] + [f"ac:{a}" for a in slice_acs(nr)]


def last_line(path: pathlib.Path) -> str:
    lines = [ln.strip() for ln in path.read_text(encoding="utf-8", errors="replace").splitlines() if ln.strip()]
    return lines[-1] if lines else ""


def git(*args: str) -> str:
    proc = subprocess.run(["git", *args], capture_output=True, text=True)
    return proc.stdout.strip() if proc.returncode == 0 else ""


def judge(nr: str, node: str, item: dict | None, started: float) -> tuple[str, str]:
    """State and reason, always recomputed from the evidence itself."""
    if not item:
        return "open", "no evidence"
    kind = item.get("kind")
    if kind == "waived":
        if node in NO_WAIVER:
            return "claimed", f"{node} cannot be waived"
        return ("waived", item["reason"]) if item.get("reason", "").strip() else ("claimed", "waived without reason")
    if kind == "sha":
        sha = item.get("sha", "")
        stamp = git("log", "-1", "--format=%ct", sha)
        if not stamp:
            return "claimed", f"commit {sha} not found"
        if float(stamp) + SLACK < started:
            return "claimed", f"commit {sha} is older than the slice start"
        if not (git("branch", "-a", "--contains", sha) or git("tag", "--contains", sha)):
            return "claimed", f"commit {sha} is on no branch or tag"
        return "evidenced", f"commit {sha[:12]}"
    path = pathlib.Path(item.get("path", ""))
    if not path.is_file():
        return "claimed", f"{path} is missing"
    if path.stat().st_mtime + SLACK < started:
        return "claimed", f"{path.name} is older than the slice start"
    tail = last_line(path)
    if node == "review":
        text = path.read_text(encoding="utf-8", errors="replace")
        missing = [a for a in slice_acs(nr) if not re.search(rf"^\W*{re.escape(a)}\s*:\s*PASS\b", text, re.M)]
        if missing:
            return "claimed", f"review has no PASS for {', '.join(missing)}"
        return ("evidenced", path.name) if tail.lower() == "verdict=pass" else ("claimed", "review verdict is not pass")
    match = re.fullmatch(r"exit=(-?\d+)", tail)
    if not match:
        return "claimed", f"{path.name} does not end with exit=<code>"
    code = int(match.group(1))
    if node == "red":
        return ("evidenced", f"{path.name} (exit={code})") if code != 0 else ("claimed", "red run passed – no failing test")
    return ("evidenced", path.name) if code == 0 else ("claimed", f"{path.name} ended with exit={code}")


def fix_hint(nr: str, node: str) -> str:
    if node == "review":
        return f"cold review → rebuild/evidence/{nr}/review.md, then: evidence.py add {nr} review --file rebuild/evidence/{nr}/review.md"
    return f"evidence.py run {nr} {node} -- <command>"


def table(nr: str) -> list[tuple[str, str, str]]:
    rec = load(nr)
    return [(node, *judge(nr, node, rec["nodes"].get(node), rec["started"])) for node in required(nr)]


def cmd_start(nr: str, force: bool) -> int:
    if record_path(nr).is_file() and not force:
        print(f"Slice {nr} started earlier – keeping that stamp ({load(nr)['started_utc']}).")
        return 0
    now = dt.datetime.now(dt.timezone.utc)
    save(nr, {"slice": nr, "started": now.timestamp(), "started_utc": now.isoformat(timespec="seconds"), "nodes": {}})
    print(f"Slice {nr} started {now.isoformat(timespec='seconds')}; nodes: {', '.join(required(nr))}")
    return 0


def cmd_run(nr: str, node: str, command: list[str]) -> int:
    rec = load(nr)
    if not command:
        sys.exit("Give the command after --")
    log = EVIDENCE / nr / (node.replace(":", "-") + ".log")
    log.parent.mkdir(parents=True, exist_ok=True)
    shell = len(command) == 1
    with log.open("w", encoding="utf-8") as out:
        proc = subprocess.Popen(command[0] if shell else command, shell=shell, stdout=subprocess.PIPE,
                                stderr=subprocess.STDOUT, text=True, encoding="utf-8", errors="replace")
        for line in proc.stdout:
            sys.stdout.write(line)
            out.write(line)
        code = proc.wait()
        out.write(f"\nexit={code}\n")
    digest = hashlib.sha256(log.read_bytes()).hexdigest()
    rec["nodes"][node] = {"kind": "log", "path": log.as_posix(), "exit": code, "sha256": digest,
                          "at": dt.datetime.now(dt.timezone.utc).isoformat(timespec="seconds")}
    save(nr, rec)
    state, reason = judge(nr, node, rec["nodes"][node], rec["started"])
    print(f"{node}: {state} – {reason}")
    return 0 if state == "evidenced" else 1


def cmd_add(nr: str, node: str, opts: list[str]) -> int:
    rec = load(nr)
    if len(opts) != 2 or opts[0] not in ("--file", "--sha", "--waived"):
        sys.exit("Give exactly one of --file <log>, --sha <commit>, --waived \"<reason>\"")
    flag, value = opts
    item = {"--file": {"kind": "log", "path": pathlib.Path(value).as_posix()},
            "--sha": {"kind": "sha", "sha": value},
            "--waived": {"kind": "waived", "reason": value}}[flag]
    item["at"] = dt.datetime.now(dt.timezone.utc).isoformat(timespec="seconds")
    rec["nodes"][node] = item
    save(nr, rec)
    state, reason = judge(nr, node, item, rec["started"])
    print(f"{node}: {state} – {reason}")
    return 0 if state in ("evidenced", "waived") else 1


def cmd_check(nr: str, strict: bool) -> int:
    rows = table(nr)
    width = max(len(r[0]) for r in rows)
    for node, state, reason in rows:
        print(f"{node:<{width}}  {state:<9}  {reason}")
    gaps = [r for r in rows if r[1] not in ("evidenced", "waived")]
    if not gaps:
        print(f"EVIDENCE OK: {nr}")
        return 0
    print(f"NOT DONE: {len(gaps)} node(s) of slice {nr} without evidence")
    for node, _, _ in gaps:
        print(f"  {node}: {fix_hint(nr, node)}")
    return 1 if strict else 0


def main(argv: list[str]) -> int:
    if len(argv) < 2 or argv[0] not in ("start", "run", "add", "check", "show"):
        print(__doc__)
        return 2
    action, nr, rest = argv[0], argv[1], argv[2:]
    if action == "start":
        return cmd_start(nr, "--force" in rest)
    if action in ("check", "show"):
        return cmd_check(nr, strict=action == "check")
    if not rest:
        sys.exit(f"Name the node: {', '.join(required(nr))}")
    node, rest = rest[0], rest[1:]
    if node not in required(nr):
        sys.exit(f"Unknown node '{node}' for slice {nr}; nodes: {', '.join(required(nr))}")
    if action == "run":
        if node == "review":
            sys.exit("review is evidenced by the cold reviewer's report: use add --file")
        return cmd_run(nr, node, rest[1:] if rest[:1] == ["--"] else rest)
    return cmd_add(nr, node, rest)


if __name__ == "__main__":
    sys.exit(main(sys.argv[1:]))
