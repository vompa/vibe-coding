"""Tests for the loop scripts of both plugins (assets/rebuild-loop and assets/slice-loop, .sh and .ps1)
with a fake claude CLI (no real Claude calls).

The vibe-coding profile runs in a real git repository: the fake claude builds each slice on its own branch and
worktree and ends with SLICE-READY, and the loop's merge queue squashes the branch in the main checkout.

Usage: python tests/loop_test.py [text]   (bash and/or pwsh must be on PATH; missing shells are skipped)
  text: run only the cases whose name contains it; LOOP_TEST_SHELLS="pwsh" runs only that shell.
"""
import json
import mmap
import os
import pathlib
import re
import shutil
import subprocess
import sys
import tempfile
import threading
import time

ROOT = pathlib.Path(__file__).resolve().parent.parent
STUB = r'''
import os, re, subprocess, sys, time
args = sys.argv[1:]
message = args[-1]
folder = os.environ["STUB_FOLDER"]  # per profile: rebuild or work
command = re.escape(os.environ["STUB_COMMAND"])  # per profile: /rebuild or /slice – any other command is unknown
if os.environ.get("STUB_PREPARE") != "1":  # the test prepares branches with this stub, too: those are no claude calls
    open("stub-calls.log", "a", encoding="utf-8").write(" | ".join(args) + "\n")
plan = re.match(command + r" (\d{2,}) plan auto", message)
build = re.search(r"Build slice (\d{2,}) and close it", message)
check_back = re.search(r"finish slice (\d{2,}) and close it", message)  # the loop checks back on a slice that printed SLICE-WAIT
close = re.match(command + r" close auto$", message)
UNTICKED, TICKED = "\u2610", "\u2611"


def git(*arguments, cwd="."):
    subprocess.run(["git", *arguments], cwd=cwd, check=True, capture_output=True)


def git_out(*arguments, cwd="."):
    return subprocess.run(["git", *arguments], cwd=cwd, check=True, capture_output=True, text=True).stdout.strip()


def option(name, nr):
    """Env option for slice nr: "100" (that slice) or "100:value,101:value" (a value per slice); None when not set for nr."""
    for part in filter(None, os.environ.get(name, "").split(",")):
        key, _, value = part.partition(":")
        if key == nr:
            return value or True
    return None


def edit(path, change):
    """Rewrites the lines of a text file with change(lines) -> lines, LF line ends."""
    lines = open(path, encoding="utf-8").read().split("\n")
    open(path, "w", encoding="utf-8", newline="\n").write("\n".join(change(lines)))


def tick(path, nr, keep_commit):
    """Ticks the row of slice nr: every box, or every box but the last one (the Commit column)."""
    lines = open(path, encoding="utf-8").read().split("\n")
    for i, line in enumerate(lines):
        if re.match(rf"^\|\s*{nr}\b", line):
            head, box, tail = line.rpartition(UNTICKED) if keep_commit else (line, "", "")
            lines[i] = head.replace(UNTICKED, TICKED) + box + tail
    open(path, "w", encoding="utf-8", newline="\n").write("\n".join(lines))


def commit(cwd, text, name):
    """Commits everything in cwd with a message from a file, the way /slice does."""
    os.makedirs(".slice-loop", exist_ok=True)
    path = os.path.abspath(f".slice-loop/{name}")
    open(path, "w", encoding="utf-8", newline="\n").write(text + "\n")
    git("add", "-A", cwd=cwd)
    git("commit", "-q", "-F", path, cwd=cwd)


def build_in_place(nr):
    """The rebuild loop's contract and a /slice run that squashed itself: tick the row in this checkout, print SLICE-DONE."""
    tick(f"{folder}/checklist.md", nr, keep_commit=False)
    if folder == "work":
        commit(".", f"Slice {nr} squashed by the session", f"task-{nr}.msg")
    print(f"SLICE-DONE: {nr}")


def manual_block(nr, bad=False):
    """A manual test block in the format of /slice; bad: a second Result line."""
    block = ["", f"### Slice {nr} – stub check", "Start: run", "1. Click", "Expected: shown", f"Closes: F-{nr}", f"Result: {UNTICKED}"]
    return block + [f"Result: {UNTICKED}"] if bad else block


DECISION_LINES = {
    "ruling": lambda nr: ["Ruling: keep the old label – User, 2026-10-30"],
    "build": lambda nr: [f"Build decision (slice {nr}): a column without tests ticked – Claude, 2026-10-30"],
    "free": lambda nr: [f"Entscheidung beim Bauen (Slice {nr}): Spalte abgehakt – Claude, 30.10.2026"],
}


def append_to_record(worktree, nr):
    """Every /slice run adds to the open round record: a surprise at the end of Surprises and a manual-test block at the
    end (STUB_RECORD_LINE adds one line more, STUB_BAD_BLOCK makes the block malformed)."""
    rounds = f"{worktree}/{folder}/rounds"
    for name in sorted(os.listdir(rounds)) if os.path.isdir(rounds) else []:
        path = f"{rounds}/{name}"
        if open(path, encoding="utf-8").readline().strip() == "Status: open":
            extra = [os.environ["STUB_RECORD_LINE"]] if os.environ.get("STUB_RECORD_LINE") else []
            def change(lines):
                if option("STUB_GLUE", nr):  # a hand-made resolution that glued two bullets into one line
                    at = lines.index("- First open question?")
                    lines = lines[:at] + [lines[at] + lines[at + 1]] + lines[at + 2:]
                if option("STUB_EXTEND", nr):  # a slice that legitimately adds to the end of a line
                    at = lines.index("- First open question?")
                    lines[at] += f" Answered in slice {nr}."
                at = lines.index("## Manual test list")
                lines = lines[:at] + [f"- Slice {nr} stub surprise"] + lines[at:]
                if option("STUB_DECISION_LINE", nr):  # ruling, build (both formats) or free (a line in neither format)
                    at = lines.index("## Surprises")
                    lines = lines[:at] + DECISION_LINES[option("STUB_DECISION_LINE", nr)](nr) + lines[at:]
                return lines[:-1] + manual_block(nr, bad=bool(option("STUB_BAD_BLOCK", nr))) + extra + [""]
            edit(path, change)
            return


def write_checks(worktree, nr):
    """The checks proof /slice writes before SLICE-READY: "<exit code> <sha> <command>" per check of the baseline.
    STUB_CHECKS=NN:missing|red|stale|incomplete spoils it; orphan adds a red line of an old commit (a stale run of another
    session), rerun a red line followed by a green one of the same command, regress a green line followed by a red one."""
    mode = option("STUB_CHECKS", nr)
    if mode == "missing":
        return
    sha = git_out("rev-parse", "HEAD~1" if mode == "stale" else "HEAD", cwd=worktree)
    commands = ["baseline-check"] if mode == "incomplete" else ["baseline-check", "unit-tests"]
    lines = [f"{1 if mode == 'red' and c == 'unit-tests' else 0} {sha} {c}" for c in commands]
    if mode == "orphan":
        lines.append(f"1 {git_out('rev-parse', 'HEAD~1', cwd=worktree)} unit-tests")
    if mode == "rerun":
        lines.insert(1, f"1 {sha} unit-tests")
    if mode == "regress":
        lines.append(f"1 {sha} unit-tests")
    open(f".slice-loop/slice-{nr}.checks", "w", encoding="utf-8", newline="\n").write("\n".join(lines) + "\n")


def touch_shared_files(worktree, nr):
    """Options for files several slices change: STUB_APPEND appends a line to a file, STUB_STATUS sets the round's cell in
    the status table, STUB_FINDING appends a finding row with that id to docs/findings.md."""
    if option("STUB_APPEND", nr):
        edit(f"{worktree}/{option('STUB_APPEND', nr)}", lambda lines: lines[:-1] + [f"- Slice {nr} entry", ""])
    if option("STUB_STATUS", nr):
        edit(f"{worktree}/{option('STUB_STATUS', nr)}",
             lambda lines: [f"| R01 | open | Slice {nr} done |" if line.startswith("| R01 |") else line for line in lines])
    if option("STUB_FINDING", nr):
        edit(f"{worktree}/docs/findings.md", lambda lines: lines[:-1] + [f"| {option('STUB_FINDING', nr)} | found in slice {nr} |", ""])


def link_packages(worktree, inner):
    """Like a slice session that links node_modules of its worktree to the main checkout's (a junction on Windows):
    removing the worktree must not empty the link's target. inner (STUB_LINK=inner or NN:inner) links to a folder inside
    the worktree instead, which the removal takes away with the worktree: the loop must report the lost entries."""
    os.makedirs("node_modules", exist_ok=True)
    open("node_modules/keep.txt", "w", encoding="utf-8", newline="\n").write("package\n")
    target = os.path.abspath("node_modules")
    if inner:
        target = os.path.abspath(f"{worktree}/cache/node_modules")
        os.makedirs(target, exist_ok=True)
        open(f"{target}/keep.txt", "w", encoding="utf-8", newline="\n").write("package\n")
    link = f"{worktree}/node_modules"
    if not os.path.lexists(link):
        if os.name == "nt":
            import _winapi
            _winapi.CreateJunction(target, os.path.abspath(link))
        else:
            os.symlink(target, os.path.abspath(link), target_is_directory=True)


def build_on_branch(nr):
    """A /slice run in auto mode: its own worktree on slice-NN, the row ticked through Checks, the round record
    appended to, a task commit, the squash message in .slice-loop/ of the main checkout, then SLICE-READY."""
    worktree = f".claude/worktrees/slice-{nr}"
    if not os.path.isdir(worktree):
        git("worktree", "add", "-q", "-b", f"slice-{nr}", worktree, "HEAD")
    link = option("STUB_LINK", nr) or os.environ.get("STUB_LINK")
    if link:
        link_packages(worktree, inner=link == "inner")
    if os.environ.get("STUB_NO_TICK") != nr:
        tick(f"{worktree}/{folder}/checklist.md", nr, keep_commit=True)
    append_to_record(worktree, nr)
    touch_shared_files(worktree, nr)
    file = os.environ.get("STUB_FILE", f"slice-{nr}.txt")
    open(f"{worktree}/{file}", "w", encoding="utf-8", newline="\n").write(os.environ.get("STUB_CONTENT", f"slice {nr}") + "\n")
    commit(worktree, f"Slice {nr} task commit", f"task-{nr}.msg")
    write_checks(worktree, nr)
    if os.environ.get("STUB_NO_MESSAGE") != nr:
        open(f".slice-loop/slice-{nr}.msg", "w", encoding="utf-8", newline="\n").write(f"Slice {nr} stub squash\n\nBody line.\n")
    ready = option("STUB_READY_FILE", nr)  # missing: no ready file yet (checks still running); moved: an older tip
    if ready != "missing":
        sha = git_out("rev-parse", "HEAD~1" if ready == "moved" else "HEAD", cwd=worktree)
        open(f".slice-loop/slice-{nr}.ready", "w", encoding="utf-8", newline="\n").write(sha + "\n")
    if option("STUB_LOCK", nr):  # a worktree git will not remove, as when a shell still runs inside it
        git("worktree", "lock", worktree)
    print(f"SLICE-READY: {nr}")


def serialised(action, nr):
    """Parallel builds touch git or the checklist at the same time: one at a time, as git's own locks would."""
    while True:
        try:
            lock = os.open("stub.lock", os.O_CREAT | os.O_EXCL)
            break
        except FileExistsError:
            time.sleep(0.05)
    try:
        action(nr)
    finally:
        os.close(lock)
        os.remove("stub.lock")


if plan:
    print(f"PLAN: {folder}/plans/slice-{plan.group(1)}.md")
    if os.environ.get("STUB_DECISION") == plan.group(1):
        print("NEEDS-DECISION: Which licence?")
elif close:
    print("ROUND-OPEN: R01 checks red" if os.environ.get("STUB_CLOSE_FAIL") == "1" else "ROUND-DONE: R01")
elif (build or check_back) and option("STUB_WAIT_ALWAYS", (build or check_back).group(1)) \
        or build and option("STUB_WAIT", build.group(1)):
    # The session ends its turn while its full suite runs in the background.
    print(f"SLICE-WAIT: {(build or check_back).group(1)} full suite in the background")
elif build or check_back:
    nr = (build or check_back).group(1)
    if os.environ.get("STUB_FAIL") == nr:
        print(f"SLICE-OPEN: {nr} tests red")
        sys.exit(0)
    if os.environ.get("STUB_NO_TICK") == nr and folder == "rebuild":
        print(f"SLICE-DONE: {nr}")
        sys.exit(0)
    in_place = folder == "rebuild" or os.environ.get("STUB_MARKER") == "done"
    serialised(build_in_place if in_place else build_on_branch, nr)
else:
    sys.exit(2)
'''

# work/conventions.md: the baseline check the checks proof must list, and the full check chain -Verify runs (both shells
# run these commands: git is the one program they share). The red variant adds a chain command that fails.
BASELINE_LINE = "- Baseline check (before every slice): `baseline-check`, `unit-tests` ← test; not `| tail`\n"
CHAIN_LINE = "- Full check chain (before the round closes): `git rev-parse --git-dir`, `git rev-parse --is-inside-work-tree` ← all green\n"
CONVENTIONS = f"# Conventions\n{BASELINE_LINE}{CHAIN_LINE}"
CONVENTIONS_RED = (f"# Conventions\n{BASELINE_LINE}- Full check chain (before the round closes): `git rev-parse --git-dir`, "
                   "`git rev-parse --verify no-such-ref` ← the second one fails\n")
CONVENTIONS_WITHOUT_CHAIN = f"# Conventions\n{BASELINE_LINE}"
# The keys translated by an intake in another language: the scripts read only the English keys.
CONVENTIONS_TRANSLATED = "# Konventionen\n- Basisprüfung (vor jeder Slice): `baseline-check`, `unit-tests`\n" + CHAIN_LINE
# One profile per plugin. Case: name, slices done before, options, env, rounds (None = default),
# expected (exit code, ticked slices, build turns, close turns), and for the vibe-coding profile an optional dict of
# git expectations: "prepared" (branches made before the run: nr, optional file, content, ready, message, record_line
# and the BRANCH_OPTIONS), "main_row" (a checklist row committed on main after the branches were made), "main_change"
# (files or a manual test block committed on main after that), "rerun" (options of a second run after unlocking the
# worktrees), "subjects" (commit subjects after the initial commit, oldest first), "branches" (slice-* branches left;
# default none), "says" / "says_not" (a phrase that is / is not in the loop's output), "no_calls" (no claude call),
# "record_has" (lines of work/rounds/R01-test.md), "results" (its number of "Result:" lines), "order" (lines it holds in
# this order), "checklist_has" (lines of work/checklist.md), "file_has" (lines per file), "file_count" (path, line
# prefix, number of such lines), "says_order" (phrases in the output, in this order), "slices" (this case's own slice
# list), "squashed" (squash markers left by an earlier run: slice -> commit), "lock" (a full-suite lock left by an earlier
# run: owner, age_minutes) and "lock_gone" (the lock must be gone at the end; without it a "lock" must still be there),
# "holds" (files held by another process, or {"unlock": text} to unlock the worktrees at that output line).
# "dry_run_ready" is what --dry-run prints when the first three slices are done.
PROFILES = [
    {
        "plugin": "vibe-rebuild", "script": "rebuild-loop", "folder": "rebuild", "command": "/rebuild",
        "slices": [
            {"nr": "00", "deps": "–"}, {"nr": "01", "deps": "00"}, {"nr": "02", "deps": "01"},
            {"nr": "03", "deps": "02"}, {"nr": "04", "deps": "02"},
        ],
        "dry_run_ready": ["03", "04"],
        "cases": [
            ("dry run lists ready slices", 3, ["--dry-run"], {}, None, (0, 3, 0, 0)),
            ("auto approve runs all slices", 1, ["--yes"], {}, None, (0, 5, 4, 0)),
            ("parallel builds both ready slices", 3, ["--yes", "--parallel"], {}, None, (0, 5, 2, 0)),
            ("red slice stops the loop", 3, ["--yes"], {"STUB_FAIL": "03"}, None, (1, 3, 1, 0)),
            ("done but not ticked stops instead of rebuilding", 3, ["--yes"], {"STUB_NO_TICK": "03"}, None, (1, 3, 1, 0)),
            ("decision without terminal does not build", 3, ["--yes"], {"STUB_DECISION": "03"}, None, (1, 3, 0, 0)),
            ("approval without terminal does not build", 3, [], {}, None, (1, 3, 0, 0)),
            ("all done exits cleanly", 5, [], {}, None, (0, 5, 0, 0)),
        ],
    },
    {
        "plugin": "vibe-coding", "script": "slice-loop", "folder": "work", "command": "/slice",
        "slices": [
            {"nr": "05", "deps": "–", "round": "R01", "model": "sonnet"}, {"nr": "06", "deps": "05", "round": "R01"},
            {"nr": "07", "deps": "06", "round": "R01", "model": "opus"}, {"nr": "100", "deps": "07", "round": "R01", "model": "haiku"},
            {"nr": "101", "deps": "07", "round": "R01"},
        ],
        "dry_run_ready": ["100", "101"],
        # Every turn of a slice (plan and build) runs on the slice's "model"; a slice without one gets no --model.
        "models": {"05": "sonnet", "07": "opus", "100": "haiku"},
        "cases": [
            ("dry run lists ready slices", 3, ["--dry-run"], {}, None, (0, 3, 0, 0)),
            ("auto approve runs all slices through the merge queue then closes the round", 1, ["--yes"], {}, None, (0, 5, 4, 1),
             {"subjects": ["Slice 06 stub squash", "Slice 07 stub squash", "Slice 100 stub squash", "Slice 101 stub squash"],
              "results": 4}),
            ("three-digit slice is squashed through the queue", 3, ["--yes", "--max-slices", "1"], {}, None, (0, 4, 1, 0),
             {"subjects": ["Slice 100 stub squash"]}),
            # Two parallel slices tick adjacent checklist rows and both append to the record: the queue resolves both files.
            ("parallel builds both ready slices through the queue then close the round", 3, ["--yes", "--parallel"], {}, None,
             (0, 5, 2, 1),
             {"subjects": ["Slice 100 stub squash", "Slice 101 stub squash"], "results": 2,
              "record_has": ["- Slice 100 stub surprise", "### Slice 100 – stub check", "- Slice 101 stub surprise", "### Slice 101 – stub check"],
              "checklist_has": ["| 100 Name | ☑ | ☑ |", "| 101 Name | ☑ | ☑ |"]}),
            ("red slice stops the loop", 3, ["--yes"], {"STUB_FAIL": "100"}, None, (1, 3, 1, 0)),
            ("ready but not ticked stops instead of merging", 3, ["--yes"], {"STUB_NO_TICK": "100"}, None, (1, 3, 1, 0),
             {"subjects": [], "branches": ["slice-100"]}),
            ("SLICE-DONE is still accepted", 3, ["--yes", "--max-slices", "1"], {"STUB_MARKER": "done"}, None, (0, 4, 1, 0)),
            ("missing message file falls back to name and source", 3, ["--yes", "--max-slices", "1"], {"STUB_NO_MESSAGE": "100"},
             None, (0, 4, 1, 0), {"subjects": ["Slice 100: Name 100 (R01 – F-100)"]}),
            ("decision without terminal does not build", 3, ["--yes"], {"STUB_DECISION": "100"}, None, (1, 3, 0, 0)),
            ("approval without terminal does not build", 3, [], {}, None, (1, 3, 0, 0)),
            ("max slices stops after one with slices left", 1, ["--yes", "--max-slices", "1"], {}, None, (0, 2, 1, 0)),
            ("close fails keeps the round open", 4, ["--yes"], {"STUB_CLOSE_FAIL": "1"}, None, (1, 5, 1, 1)),
            ("second round open runs on it", 3, ["--yes", "--max-slices", "1"], {},
             [("R01", "closed"), ("R02", "open")], (0, 4, 1, 0)),
            ("no open round exits without building", 3, ["--yes"], {}, [("R01", "closed")], (0, 3, 0, 0)),
            ("all done and closed exits cleanly", 5, [], {}, [("R01", "closed")], (0, 5, 0, 0)),
            ("merge squashes one ready branch without a claude call", 3, ["--merge"], {}, [("R01", "closed")], (0, 4, 0, 0),
             {"prepared": [{"nr": "100"}], "subjects": ["Slice 100 stub squash"], "no_calls": True}),
            # The integration branch changed a file the slice changes too: left behind before the squash; the queue
            # squashes the next one.
            ("merge leaves a slice whose file the integration branch changed and squashes the next", 3, ["--merge"], {}, None,
             (1, 4, 0, 0),
             {"prepared": [{"nr": "100", "file": "shared.txt", "content": "from 100"}, {"nr": "101"}],
              "main_change": {"shared.txt": "from main\n"},
              "subjects": ["Change on main", "Slice 101 stub squash"], "branches": ["slice-100"],
              "says": "integration branch moved and touches shared.txt – merge it on the slice branch",
              "says_not": "work/checklist.md", "no_calls": True}),
            # Even without a textual conflict: the slice's checks never ran together with the integration branch's change.
            ("merge leaves a slice that overlaps the moved integration branch without a conflict", 3, ["--merge"], {}, None,
             (1, 3, 0, 0),
             {"prepared": [{"nr": "100", "file": "shared.txt", "content": "top\nbase"}],
              "main_change": {"shared.txt": "base\nmain\n"}, "subjects": ["Change on main"], "branches": ["slice-100"],
              "says": "integration branch moved and touches shared.txt", "no_calls": True}),
            # No re-merge after every squash: a slice cut from an older integration branch is squashed as it is.
            ("merge squashes a slice cut from an older integration branch that touches other files", 3, ["--merge"], {}, None,
             (0, 4, 0, 0),
             {"prepared": [{"nr": "100"}], "main_change": {"shared.txt": "from main\n"},
              "subjects": ["Change on main", "Slice 100 stub squash"], "file_has": {"shared.txt": ["from main"]},
              "says_not": "left behind", "no_calls": True}),
            # A real conflict in a document (left out of the overlap) leaves the slice behind with the same advice.
            ("merge leaves a real conflict in a document behind", 3, ["--merge"], {}, None, (1, 3, 0, 0),
             {"prepared": [{"nr": "100", "file": "docs/protocol.md", "content": "from 100"}],
              "main_change": {"docs/protocol.md": "from main\n"}, "subjects": ["Change on main"], "branches": ["slice-100"],
              "says": "merge conflict in docs/protocol.md – merge the integration branch on the slice branch", "no_calls": True}),
            # One decision format: rulings and build decisions pass, a line in neither format leaves the slice behind.
            ("merge takes rulings and build decisions in the round record", 3, ["--merge"], {}, None, (0, 5, 0, 0),
             {"prepared": [{"nr": "100", "decision": "ruling"}, {"nr": "101", "decision": "build"}],
              "subjects": ["Slice 100 stub squash", "Slice 101 stub squash"],
              "record_has": ["Ruling: keep the old label – User, 2026-10-30",
                             "Build decision (slice 101): a column without tests ticked – Claude, 2026-10-30"], "no_calls": True}),
            ("merge leaves a slice whose decision line is in neither format", 3, ["--merge"], {}, None, (1, 3, 0, 0),
             {"prepared": [{"nr": "100", "decision": "free"}], "subjects": [], "branches": ["slice-100"],
              "says": "decision line in neither format", "no_calls": True}),
            ("merge keeps both sides of lines appended at the same place in any file", 3, ["--merge"], {}, None, (0, 5, 0, 0),
             {"prepared": [{"nr": "100", "append": "docs/protocol.md"}, {"nr": "101", "append": "docs/protocol.md"}],
              "subjects": ["Slice 100 stub squash", "Slice 101 stub squash"],
              "file_has": {"docs/protocol.md": ["# Protocol", "- Slice 100 entry", "- Slice 101 entry"]}, "no_calls": True}),
            ("merge merges the status row of the round by rule", 3, ["--merge"], {}, None, (0, 5, 0, 0),
             {"prepared": [{"nr": "100", "status": "docs/status.md"}, {"nr": "101", "status": "docs/status.md"}],
              "file_has": {"docs/status.md": ["| R01 | open | Slice 100 done; Slice 101 done |"]},
              "file_count": [("docs/status.md", "| R01 |", 1)], "no_calls": True}),
            ("merge leaves a slice without checks proof and squashes the next", 3, ["--merge"], {}, None, (1, 4, 0, 0),
             {"prepared": [{"nr": "100", "checks": "missing"}, {"nr": "101"}], "subjects": ["Slice 101 stub squash"],
              "branches": ["slice-100"], "says": "no checks proof", "no_calls": True}),
            # A session still running its last checks has written no ready file yet, or one of an older tip.
            # Not ready yet is no failure of -Merge: the session is still checking, and exit 0 lets an orchestrator go on.
            ("merge lists a slice that has not reported ready as not ready yet and squashes the next", 3, ["--merge"], {}, None,
             (0, 4, 0, 0),
             {"prepared": [{"nr": "100", "ready_file": "missing"}, {"nr": "101"}], "subjects": ["Slice 101 stub squash"],
              "branches": ["slice-100"], "says": ["not ready yet: not reported ready: no .slice-loop/slice-100.ready",
                                                  "1 slice(s) not ready yet"], "says_not": "left behind", "no_calls": True}),
            ("merge lists a slice whose branch moved after it reported ready as not ready yet", 3, ["--merge"], {}, None,
             (0, 3, 0, 0),
             {"prepared": [{"nr": "100", "ready_file": "moved"}], "subjects": [], "branches": ["slice-100"],
              "says": "not ready yet: slice-100 moved after SLICE-READY", "no_calls": True}),
            # A real problem next to a slice not ready yet still fails the run.
            ("merge fails for a red check next to a slice not ready yet", 3, ["--merge"], {}, None, (1, 3, 0, 0),
             {"prepared": [{"nr": "100", "ready_file": "missing"}, {"nr": "101", "checks": "red"}], "subjects": [],
              "branches": ["slice-100", "slice-101"], "says": ["not ready yet", "1 slice(s) left behind"], "no_calls": True}),
            ("merge leaves a slice with a red check", 3, ["--merge"], {}, None, (1, 3, 0, 0),
             {"prepared": [{"nr": "100", "checks": "red"}], "subjects": [], "branches": ["slice-100"],
              "says": "check red (exit 1): unit-tests", "no_calls": True}),
            ("merge leaves a slice whose checks ran on an older commit", 3, ["--merge"], {}, None, (1, 3, 0, 0),
             {"prepared": [{"nr": "100", "checks": "stale"}], "subjects": [], "branches": ["slice-100"],              "says": ["no check ran on the tip", " of slice-100 (2 stale line(s) ignored)"], "no_calls": True}),
            # A stale line (another commit) is ignored when the tip has its own lines; of each command the last line counts.
            ("merge ignores a stale red line of an old commit and squashes", 3, ["--merge"], {}, None, (0, 4, 0, 0),
             {"prepared": [{"nr": "100", "checks": "orphan"}], "subjects": ["Slice 100 stub squash"], "no_calls": True}),
            ("merge accepts a green rerun after a red run on the tip", 3, ["--merge"], {}, None, (0, 4, 0, 0),
             {"prepared": [{"nr": "100", "checks": "rerun"}], "subjects": ["Slice 100 stub squash"], "no_calls": True}),
            ("merge leaves a slice whose check went red after a green run", 3, ["--merge"], {}, None, (1, 3, 0, 0),
             {"prepared": [{"nr": "100", "checks": "regress"}], "subjects": [], "branches": ["slice-100"],
              "says": "check red (exit 1): unit-tests", "no_calls": True}),
            ("merge leaves a slice whose proof lacks a baseline check", 3, ["--merge"], {}, None, (1, 3, 0, 0),
             {"prepared": [{"nr": "100", "checks": "incomplete"}], "subjects": [], "branches": ["slice-100"],
              "says": "baseline check missing from .slice-loop/slice-100.checks: unit-tests", "no_calls": True}),
            ("merge refuses a finding id defined twice", 3, ["--merge"], {}, None, (1, 4, 0, 0),
             {"prepared": [{"nr": "100", "finding": "F-90"}, {"nr": "101", "finding": "F-90"}],
              "subjects": ["Slice 100 stub squash"], "branches": ["slice-101"],
              "says": "finding id defined twice: F-90 in docs/findings.md", "no_calls": True}),
            # Ids may start with a non-ASCII capital (the owner's own findings Ä77 – Ä103 in a target repository).
            ("merge refuses a finding id with a non-ASCII capital defined twice", 3, ["--merge"], {}, None, (1, 4, 0, 0),
             {"prepared": [{"nr": "100", "finding": "Ä77"}, {"nr": "101", "finding": "Ä77"}],
              "subjects": ["Slice 100 stub squash"], "branches": ["slice-101"],
              "says": "finding id defined twice: Ä77 in docs/findings.md", "no_calls": True}),
            # The integration branch got slice 102's block after the branches were cut: the blocks end in slice order.
            ("merge puts the manual test blocks in slice order", 3, ["--merge"], {}, None, (0, 5, 0, 0),
             {"prepared": [{"nr": "101"}, {"nr": "100"}], "main_change": {"block": "102"}, "results": 3,
              "order": ["### Slice 100 – stub check", "### Slice 101 – stub check", "### Slice 102 – stub check"],
              "no_calls": True}),
            ("merge refuses a malformed manual test block", 3, ["--merge"], {}, None, (1, 3, 0, 0),
             {"prepared": [{"nr": "100", "bad_block": True}], "subjects": [], "branches": ["slice-100"],
              "says": "manual test block of slice 100", "no_calls": True}),
            # The build loop goes on without a slice it left behind, then lists it and exits non-zero without closing.
            ("parallel run goes on past a slice it left behind", 3, ["--yes", "--parallel"], {"STUB_CHECKS": "100:red"}, None,
             (1, 4, 2, 0), {"subjects": ["Slice 101 stub squash"], "branches": ["slice-100"], "says": "1 slice(s) left behind"}),
            ("SLICE-WAIT is still running and checked back on", 3, ["--yes", "--max-slices", "1"],
             {"STUB_WAIT": "100", "SLICE_WAIT_SECONDS": "0"}, None, (0, 4, 1, 0),
             {"subjects": ["Slice 100 stub squash"], "says": "still running: full suite in the background"}),
            ("SLICE-WAIT without end stops after the last check-back", 3, ["--yes", "--max-slices", "1"],
             {"STUB_WAIT_ALWAYS": "100", "SLICE_WAIT_SECONDS": "0", "SLICE_WAIT_MAX": "2"}, None, (1, 3, 1, 0),
             {"subjects": [], "says": "still waiting after 2 check-backs"}),
            # A worktree git will not remove is reported with its likely cause; a later --merge removes it.
            ("a worktree left by the squash is removed by a later merge", 3, ["--yes", "--max-slices", "1"],
             {"STUB_LOCK": "100", "SLICE_WRITE_RETRIES": "2", "SLICE_WRITE_BACKOFF_SECONDS": "0"}, None, (0, 4, 1, 0),
             {"rerun": ["--merge"], "subjects": ["Slice 100 stub squash"], "branches": [],
              "says": ["a shell, editor or process still runs inside it", "retrying in 0 s (attempt 2 of 2)"]}),
            # The shell of the finished session lets go during the retries: the removal succeeds without a second run.
            ("removing a worktree is retried until the shell inside it lets go", 3, ["--yes", "--max-slices", "1"],
             {"STUB_LOCK": "100", "SLICE_WRITE_BACKOFF_SECONDS": "1"}, None, (0, 4, 1, 0),
             {"holds": [{"unlock": "retrying"}], "subjects": ["Slice 100 stub squash"], "branches": [],
              "says": "retrying in 1 s (attempt 1 of 5)", "says_not": "could not be removed"}),
            # What a removal leaves is said in the closing report, not only among the retries.
            ("the report names a worktree the squash could not remove", 3, ["--yes", "--max-slices", "1"],
             {"STUB_LOCK": "100", "SLICE_WRITE_RETRIES": "0"}, None, (0, 4, 1, 0),
             {"subjects": ["Slice 100 stub squash"], "branches": ["slice-100"],
              "says": ["1 squashed slice(s) left something to clean up", "slice-100 kept"]}),
            # --watch: an orchestrating chat may not be woken by a session's report (R05: two slices waited four hours).
            ("watch squashes a slice that has reported ready and exits", 3, ["--merge", "--watch"], {"SLICE_WATCH_SECONDS": "0"}, None,
             (0, 4, 0, 0), {"prepared": [{"nr": "100"}], "subjects": ["Slice 100 stub squash"], "no_calls": True,
                            "says": "watching for SLICE-READY"}),
            ("watch ends after its last check when no slice reports ready", 3, ["--merge", "--watch"],
             {"SLICE_WATCH_SECONDS": "0", "SLICE_WATCH_MAX": "2"}, None, (0, 3, 0, 0),
             {"prepared": [{"nr": "100", "ready_file": "missing"}], "subjects": [], "branches": ["slice-100"], "no_calls": True,
              "says": "no slice reported ready after 2 check(s)", "says_not": "not ready yet"}),
            ("watch squashes a slice that reports ready while it waits", 3, ["--merge", "--watch"],
             {"SLICE_WATCH_SECONDS": "1", "SLICE_WATCH_MAX": "30"}, None, (0, 4, 0, 0),
             {"prepared": [{"nr": "100", "ready_file": "missing"}], "holds": [{"report_ready": "100"}],
              "subjects": ["Slice 100 stub squash"], "no_calls": True}),
            # A slice left behind wakes the orchestrator once; only a new tip brings it back.
            ("watch does not wake again for a slice it already left behind", 3, ["--merge", "--watch"],
             {"SLICE_WATCH_SECONDS": "0", "SLICE_WATCH_MAX": "1"}, None, (0, 3, 0, 0),
             {"prepared": [{"nr": "100", "checks": "red"}], "rerun": ["--merge", "--watch"], "subjects": [], "branches": ["slice-100"],
              "no_calls": True, "says": ["check red (exit 1): unit-tests", "no slice reported ready after 1 check(s)"]}),
            ("a second watch does not squash next to a running one", 3, ["--merge", "--watch"], {"SLICE_WATCH_SECONDS": "0"}, None,
             (0, 3, 0, 0), {"prepared": [{"nr": "100"}], "watch_alive": 0, "subjects": [], "branches": ["slice-100"], "no_calls": True,
                            "says": "already watching"}),
            ("a watch whose predecessor died long ago goes on", 3, ["--merge", "--watch"], {"SLICE_WATCH_SECONDS": "0"}, None,
             (0, 4, 0, 0), {"prepared": [{"nr": "100"}], "watch_alive": 61, "subjects": ["Slice 100 stub squash"], "no_calls": True,
                            "says_not": "already watching"}),
            # A squash marker of a branch that has commits after the squash: nothing for the queue to do.
            ("merge leaves a squashed branch that moved since", 4, ["--merge"], {}, None, (0, 4, 0, 0),
             {"prepared": [{"nr": "100"}], "squashed": {"100": "0" * 40}, "subjects": [], "branches": ["slice-100"],
              "says": "[slice 100] already squashed; slice-100 has commits after the squash – nothing to do for the queue "
                      "(squash them by hand or delete the branch)", "no_calls": True}),
            # The integration branch got a row after the branches were cut: it stays, and 101's squash keeps 100's ticks.
            ("merge resolves the checklist and keeps a row only the integration branch has", 3, ["--merge"], {}, None, (0, 5, 0, 0),
             {"prepared": [{"nr": "100"}, {"nr": "101"}], "main_row": "102",
              "subjects": ["Add row 102", "Slice 100 stub squash", "Slice 101 stub squash"], "results": 2,
              "checklist_has": ["| 100 Name | ☑ | ☑ |", "| 101 Name | ☑ | ☑ |", "| 102 Name | ☐ | ☐ |"],
              "no_calls": True}),
            ("a resolution that fails its check resets and stops", 3, ["--merge"], {}, None, (1, 4, 0, 0),
             {"prepared": [{"nr": "100"}, {"nr": "101", "record_line": "======="}],
              "subjects": ["Slice 100 stub squash"], "branches": ["slice-101"], "says": "R01-test.md failed its check",
              "no_calls": True}),
            # A worktree with node_modules linked to the main checkout: removing the worktree keeps the main packages.
            ("removing a worktree keeps the target of its linked folder", 3, ["--yes", "--max-slices", "1"], {"STUB_LINK": "1"},
             None, (0, 4, 1, 0),
             {"subjects": ["Slice 100 stub squash"], "keeps": "node_modules/keep.txt", "says_not": "lost entries"}),
            # The link's target is inside the worktree and goes with it: the loss is reported, the run fails, the squash stays.
            ("removing a worktree reports a linked folder that lost entries", 3, ["--yes", "--max-slices", "1"], {"STUB_LINK": "inner"},
             None, (1, 4, 1, 0),
             {"subjects": ["Slice 100 stub squash"], "branches": [],
              "says": "link target", "says_order": ["lost entries during the removal of the worktree of slice-100 (before 1, now 0)"]}),
            ("merge fails when a linked folder lost entries", 3, ["--merge"], {}, None, (1, 4, 0, 0),
             {"prepared": [{"nr": "100", "link": "inner"}], "subjects": ["Slice 100 stub squash"], "branches": [],
              "says": "restore it (for example npm ci)", "no_calls": True}),
            # Another process holds a file the queue writes (a scanner with it mapped): the write is retried until it is free.
            ("merge retries a write until another process frees the file", 3, ["--merge"], {"SLICE_WRITE_BACKOFF_SECONDS": "1"},
             None, (0, 4, 0, 0),
             {"prepared": [{"nr": "100"}], "holds": [{"path": ".slice-loop/slice-100.squashed", "release": "could not write"}],
              "subjects": ["Slice 100 stub squash"],
              "says": "could not write .slice-loop/slice-100.squashed (locked by another process?) – retrying", "no_calls": True}),
            # The file stays held: the slice is left behind and the merge reset – retried, as the checklist is held, too –
            # and the queue squashes the next slice.
            ("merge leaves a slice whose file stays locked, resets and squashes the next", 3, ["--merge"],
             {"SLICE_WRITE_RETRIES": "2", "SLICE_WRITE_BACKOFF_SECONDS": "1"}, None, (1, 4, 0, 0),
             {"prepared": [{"nr": "100"}, {"nr": "101"}],
              "holds": [{"path": ".slice-loop/slice-100.squashed", "release": "left behind"},
                        {"path": "work/checklist.md", "start": "could not write", "release": "could not reset"}],
              "subjects": ["Slice 101 stub squash"], "branches": ["slice-100"],
              "says": ["slice 100: could not write .slice-loop/slice-100.squashed (locked by another process) – merge reset",
                       "could not reset the merge (a file is locked by another process?) – retrying"], "no_calls": True}),
            # (c) A stop in the middle of the squash (here: a pre-commit hook refuses the commit) still resets the merge.
            ("a stop during the squash leaves a clean checkout", 3, ["--merge"], {}, None, (1, 3, 0, 0),
             {"prepared": [{"nr": "100"}], "failing_commit": True, "subjects": [], "branches": ["slice-100"],
              "says": "the squash commit failed – merge reset", "no_calls": True}),
            # A hand-made resolution glued two bullets of the record into one line.
            ("merge leaves a slice whose record has two lines glued into one", 3, ["--merge"], {}, None, (1, 3, 0, 0),
             {"prepared": [{"nr": "100", "glue": True}], "subjects": [], "branches": ["slice-100"],
              "says": "line glued to the next one in work/rounds/R01-test.md: - First open question?", "no_calls": True}),
            ("merge squashes a slice that adds text to the end of a line of the record", 3, ["--merge"], {}, None, (0, 4, 0, 0),
             {"prepared": [{"nr": "100", "extend": True}], "subjects": ["Slice 100 stub squash"], "says_not": "glued", "no_calls": True}),
            # The full-suite lock: a stale one (its slice branch is gone, or it is old) is reported and kept; a live one is not reported.
            ("a lock of a slice whose branch is gone is reported and kept", 3, ["--merge"], {}, None, (0, 3, 0, 0),
             {"lock": {"owner": "slice 99 2026-10-27T08:00:00Z"},
              "says": "stale lock .slice-loop/full-suite.lock (owner: slice 99 2026-10-27T08:00:00Z) – its slice branch is gone",
              "no_calls": True}),
            ("a lock older than an hour is reported and kept", 3, ["--merge"], {}, None, (0, 3, 0, 0),
             {"lock": {"owner": "merge queue 2026-10-27T05:00:00Z", "age_minutes": 120},
              "says": "stale lock .slice-loop/full-suite.lock (owner: merge queue 2026-10-27T05:00:00Z) – it is older than 60 minutes",
              "no_calls": True}),
            ("a lock of an existing slice branch is not reported", 3, ["--merge"], {}, None, (0, 4, 0, 0),
             {"prepared": [{"nr": "100"}], "lock": {"owner": "slice 100 2026-10-27T08:00:00Z"}, "subjects": ["Slice 100 stub squash"],
              "says_not": "stale lock", "no_calls": True}),
            # -Verify: after a squash the full check chain runs on the integration branch under the lock.
            ("verify runs the full check chain after a squash and frees the lock", 3, ["--merge", "--verify"], {}, None, (0, 4, 0, 0),
             {"prepared": [{"nr": "100"}], "subjects": ["Slice 100 stub squash"], "lock_gone": True, "no_calls": True,
              "says": ["[verify] git rev-parse --git-dir – green", "[verify] git rev-parse --is-inside-work-tree – green"]}),
            ("verify with a red command exits non-zero and frees the lock", 3, ["--merge", "--verify"], {}, None, (1, 4, 0, 0),
             {"prepared": [{"nr": "100"}], "main_change": {"work/conventions.md": CONVENTIONS_RED}, "lock_gone": True, "no_calls": True,
              "subjects": ["Change on main", "Slice 100 stub squash"],
              "says": ["[verify] git rev-parse --git-dir – green", "[verify] git rev-parse --verify no-such-ref – red (exit 128)",
                       "full check chain red on main after the merge queue"]}),
            ("verify without a squash runs nothing", 3, ["--merge", "--verify"], {}, None, (0, 3, 0, 0),
             {"says_not": "[verify]", "lock_gone": True, "no_calls": True}),
            ("verify without a full check chain line verifies nothing", 3, ["--merge", "--verify"], {}, None, (0, 4, 0, 0),
             {"prepared": [{"nr": "100"}], "main_change": {"work/conventions.md": CONVENTIONS_WITHOUT_CHAIN},
              "subjects": ["Change on main", "Slice 100 stub squash"],
              "says": "no '- Full check chain' line in work/conventions.md – nothing verified (the key stays English in any language)",
              "says_not": "[verify]", "lock_gone": True, "no_calls": True}),
            # A translated key hid the baseline from the queue without a word; now the run says so (and still squashes).
            ("merge reports a conventions file without a baseline check line", 3, ["--merge"], {}, None, (0, 4, 0, 0),
             {"prepared": [{"nr": "100"}], "main_change": {"work/conventions.md": CONVENTIONS_TRANSLATED},
              "subjects": ["Change on main", "Slice 100 stub squash"], "no_calls": True,
              "says": ["no '- Baseline check' line in work/conventions.md", "the key stays English in any language"]}),
            ("verify skips and fails when the lock is held", 3, ["--merge", "--verify"], {}, None, (1, 4, 0, 0),
             {"prepared": [{"nr": "100"}], "lock": {"owner": "slice 100 2026-10-27T08:00:00Z"}, "subjects": ["Slice 100 stub squash"],
              "says": "full-suite.lock is held (owner: slice 100 2026-10-27T08:00:00Z)", "says_not": "[verify]", "no_calls": True}),
            ("verify needs the merge option", 3, ["--verify"], {}, None, (1, 3, 0, 0), {"says": "erify needs ", "no_calls": True}),
            # -Parallel: at most two slices per batch, and none that shares a file with one already in the batch.
            ("parallel takes at most two slices per batch", 0, ["--yes", "--parallel"], {}, None, (0, 4, 4, 1),
             {"slices": [{"nr": nr, "deps": "–"} for nr in ("200", "201", "202", "203")],
              "subjects": [f"Slice {nr} stub squash" for nr in ("200", "201", "202", "203")], "results": 4,
              "says_order": ["[slice 201] squashed", "[slice 202] planning"]}),
            ("parallel keeps a slice that shares a file for the next batch", 0, ["--yes", "--parallel"], {}, None, (0, 3, 3, 1),
             {"slices": [{"nr": "200", "deps": "–", "files": ["src/app.cs"]}, {"nr": "201", "deps": "–", "files": ["src/"]},
                         {"nr": "202", "deps": "–", "files": ["docs/a.md"]}],
              "subjects": [f"Slice {nr} stub squash" for nr in ("200", "202", "201")], "results": 3,
              "says": "[slice 201] waits: shares src/app.cs with slice 200",
              "says_order": ["[slice 202] squashed", "[slice 201] planning"]}),
            ("merge leaves a branch whose row is not ticked through Checks", 3, ["--merge"], {}, None, (0, 3, 0, 0),
             {"prepared": [{"nr": "100", "ready": False}], "subjects": [], "branches": ["slice-100"], "no_calls": True}),
        ],
    },
]
# Options that start with "--" become PowerShell switches; a value after one (--max-slices 1) stays as it is.
PWSH_FLAGS = {"--yes": "-Yes", "--parallel": "-Parallel", "--dry-run": "-DryRun", "--max-slices": "-MaxSlices", "--merge": "-Merge",
              "--verify": "-Verify", "--watch": "-Watch"}
TEST_IDENTITY = (("user.name", "loop-test"), ("user.email", "loop-test@example.invalid"))


def posix(path: pathlib.Path) -> str:
    """Path as bash sees it; C:/x would split PATH at the colon on Windows."""
    text = path.as_posix()
    return f"/{text[0].lower()}{text[2:]}" if os.name == "nt" and text[1:2] == ":" else text


def make_stub(bin_dir: pathlib.Path) -> pathlib.Path:
    stub = bin_dir / "claude_stub.py"
    stub.write_text(STUB, encoding="utf-8")
    wrapper = bin_dir / "claude"
    # The script argument stays C:/… – the .sh loop scripts turn off Git Bash path conversion.
    wrapper.write_text(f'#!/usr/bin/env bash\nexec "{posix(pathlib.Path(sys.executable))}" -X utf8 "{stub.as_posix()}" "$@"\n',
                       encoding="utf-8", newline="\n")
    wrapper.chmod(0o755)
    # The .ps1 loop scripts resolve claude as an application, so Windows needs a .cmd, not a .ps1.
    (bin_dir / "claude.cmd").write_text(f'@"{sys.executable}" -X utf8 "{stub}" %*\r\n', encoding="utf-8")
    return stub


def git(repo: pathlib.Path, *arguments: str) -> str:
    return subprocess.run(["git", *arguments], cwd=repo, check=True, capture_output=True, text=True, encoding="utf-8").stdout


def init_git(repo: pathlib.Path) -> None:
    """A real repository on main with a local test identity; files the fake claude leaves in the checkout are excluded."""
    git(repo, "init", "-q", "-b", "main")
    for key, value in TEST_IDENTITY + (("core.autocrlf", "false"), ("commit.gpgsign", "false")):
        git(repo, "config", key, value)
    (repo / ".git/info/exclude").write_text("stub-calls.log\nstub.lock\n.claude/worktrees/\nnode_modules\n", encoding="utf-8", newline="\n")
    git(repo, "add", "-A")
    git(repo, "commit", "-q", "-m", "Initial state")


# Per-branch options of "prepared" and the stub variable each one sets for that slice.
BRANCH_OPTIONS = {"append": "STUB_APPEND", "status": "STUB_STATUS", "finding": "STUB_FINDING", "checks": "STUB_CHECKS",
                  "bad_block": "STUB_BAD_BLOCK", "glue": "STUB_GLUE", "extend": "STUB_EXTEND", "link": "STUB_LINK",
                  "ready_file": "STUB_READY_FILE", "decision": "STUB_DECISION_LINE"}
# Files every vibe-coding test repository starts with: the baseline check the queue requires in the checks proof, the
# findings file the record names under ## Source, a status page with the round's row, a protocol appended to.
WORK_FILES = {
    "work/conventions.md": CONVENTIONS,
    "docs/findings.md": "# Findings\n| id | finding |\n|---|---|\n| F-01 | old |\n",
    "docs/status.md": "| Round | State | Slices |\n|---|---|---|\n| R01 | open | – |\n",
    "docs/protocol.md": "# Protocol\n",
    "shared.txt": "base\n",
}


def record_text(status: str) -> str:
    return (f"Status: {status}\n\n# Round – test\n\n## Source\n`docs/findings.md`, marked \"done in slice NN\"\n\n"
            "## Decisions\n\n## Surprises\n\n- First open question?\n- Second open question\n\n## Manual test list\n")


def prepare_branch(repo: pathlib.Path, stub: pathlib.Path, profile: dict, branch: dict) -> None:
    """A slice-NN branch as a finished /slice run leaves it, made by the fake claude without counting as a call."""
    env = dict(os.environ, STUB_FOLDER=profile["folder"], STUB_COMMAND=profile["command"], STUB_PREPARE="1")
    if branch.get("file"):
        env.update(STUB_FILE=branch["file"], STUB_CONTENT=branch["content"])
    if not branch.get("ready", True):
        env["STUB_NO_TICK"] = branch["nr"]
    if not branch.get("message", True):
        env["STUB_NO_MESSAGE"] = branch["nr"]
    if branch.get("record_line"):
        env["STUB_RECORD_LINE"] = branch["record_line"]
    for key, variable in BRANCH_OPTIONS.items():
        if branch.get(key):
            env[variable] = f"{branch['nr']}:{branch[key]}" if branch[key] is not True else branch["nr"]
    subprocess.run([sys.executable, "-X", "utf8", str(stub), f"Build slice {branch['nr']} and close it"],
                   cwd=repo, env=env, check=True, capture_output=True)


def add_main_row(repo: pathlib.Path, profile: dict, nr: str) -> None:
    """A checklist row committed on main after the slice branches were cut."""
    checklist = repo / profile["folder"] / "checklist.md"
    with checklist.open("a", encoding="utf-8", newline="\n") as file:
        file.write(f"| {nr} Name | ☐ | ☐ |\n")
    git(repo, "commit", "-q", "-am", f"Add row {nr}")


def change_main(repo: pathlib.Path, changes: dict) -> None:
    """Commits on main after the slice branches were cut: "path": text replaces a file, "block": NN appends a manual
    test block for slice NN to the open record."""
    for path, text in changes.items():
        if path == "block":
            record = repo / "work/rounds/R01-test.md"
            record.write_text(record.read_text(encoding="utf-8") + "\n".join(
                ["", f"### Slice {text} – stub check", "Start: run", "1. Click", "Expected: shown", f"Closes: F-{text}", "Result: ☐", ""]),
                encoding="utf-8", newline="\n")
        else:
            (repo / path).write_text(text, encoding="utf-8", newline="\n")
    git(repo, "commit", "-q", "-am", "Change on main")


def make_repo(base: pathlib.Path, profile: dict, done: int, rounds: list[tuple[str, str]] | None,
              stub: pathlib.Path, prepared: list[dict], main_row: str | None, main_change: dict | None = None) -> pathlib.Path:
    """Plan repo with the first `done` slices ticked; the slice loop also gets one record per round and a real git repository."""
    repo = pathlib.Path(tempfile.mkdtemp(dir=base))
    folder = repo / profile["folder"]
    folder.mkdir()
    slices = [dict(s, name=f"Name {s['nr']}", source=f"R01 – F-{s['nr']}") if profile["folder"] == "work" else s
              for s in profile["slices"]]
    (folder / "_slices.json").write_text(json.dumps(slices, ensure_ascii=False), encoding="utf-8")
    rows = ["| Slice | Plan | Commit |", "|---|---|---|"]
    rows += [f"| {s['nr']} Name | " + ("\u2611 | \u2611 |" if i < done else "\u2610 | \u2610 |") for i, s in enumerate(slices)]
    (folder / "checklist.md").write_text("\n".join(rows) + "\n", encoding="utf-8", newline="\n")
    if profile["folder"] != "work":  # the rebuild loop needs no git, only the folder it appends its exclude line to
        (repo / ".git/info").mkdir(parents=True)
        return repo
    (folder / "rounds").mkdir()
    for round_id, status in rounds or [("R01", "open")]:
        (folder / f"rounds/{round_id}-test.md").write_text(record_text(status), encoding="utf-8", newline="\n")
    for path, text in WORK_FILES.items():
        (repo / path).parent.mkdir(parents=True, exist_ok=True)
        (repo / path).write_text(text, encoding="utf-8", newline="\n")
    init_git(repo)
    for branch in prepared:
        prepare_branch(repo, stub, profile, branch)
    if main_row:
        add_main_row(repo, profile, main_row)
    if main_change:
        change_main(repo, main_change)
    return repo


def prepare_state(repo: pathlib.Path, expected: dict) -> None:
    """State an earlier run left in .slice-loop/: "squashed" (slice nr -> the commit its squash marker names) and "lock"
    (a full-suite lock: owner text, age_minutes)."""
    if "squashed" not in expected and "lock" not in expected and "watch_alive" not in expected:
        return
    log_dir = repo / ".slice-loop"
    log_dir.mkdir(exist_ok=True)
    if "watch_alive" in expected:  # the sign of life of another watch, this many minutes old
        alive = log_dir / "watch.alive"
        alive.write_text("", encoding="utf-8")
        then = time.time() - 60 * expected["watch_alive"]
        os.utime(alive, (then, then))
    for nr, sha in expected.get("squashed", {}).items():
        (log_dir / f"slice-{nr}.squashed").write_text(sha + "\n", encoding="utf-8", newline="\n")
    if "lock" in expected:
        lock = log_dir / "full-suite.lock"
        lock.mkdir()
        (lock / "owner").write_text(expected["lock"]["owner"] + "\n", encoding="utf-8", newline="\n")
        then = time.time() - 60 * expected["lock"].get("age_minutes", 0)
        for path in (lock / "owner", lock):
            os.utime(path, (then, then))


def command(shell: str, bin_dir: pathlib.Path, body: str) -> list[str]:
    # Full path: on Windows a bare "bash" would start WSL from System32 instead of the bash on PATH.
    executable = shutil.which(shell)
    if shell == "bash":
        return [executable, "-c", f'export PATH="{posix(bin_dir)}:$PATH"; {body}']
    # UTF-8 console output, so the test can read non-ASCII ids (Ä77) the script prints; a real console shows its own code page.
    return [executable, "-NoProfile", "-Command", "[Console]::OutputEncoding = [Text.UTF8Encoding]::new($false); "
            f"$env:PATH = '{bin_dir}' + [IO.Path]::PathSeparator + $env:PATH; {body}"]


def assert_stub_first(shell: str, bin_dir: pathlib.Path) -> None:
    """Never let a test reach the real claude CLI."""
    probe = "command -v claude" if shell == "bash" else "(Get-Command claude -CommandType Application | Select-Object -First 1).Source"
    found = subprocess.run(command(shell, bin_dir, probe), capture_output=True, text=True).stdout.strip()
    if "claude_stub" not in found and not found.startswith((posix(bin_dir), str(bin_dir))):
        sys.exit(f"{shell}: claude resolves to {found!r}, not the stub – aborting")


def script_path(profile: dict, shell: str) -> pathlib.Path:
    plugin = profile["plugin"]
    return ROOT / "plugins" / plugin / "skills" / plugin / "assets" / f"{profile['script']}.{'sh' if shell == 'bash' else 'ps1'}"


def pwsh_arguments(options: list[str]) -> str:
    """--yes -> -Yes; values such as the 1 in --max-slices 1 pass through unchanged."""
    return " ".join(PWSH_FLAGS[o] if o.startswith("--") else o for o in options)


class Hold:
    """Another process holding a file as a scanner or indexer does, so that neither the loop nor git can replace it: on
    Windows the file is mapped (the loop meets ERROR_USER_MAPPED_FILE); elsewhere, where a mapping blocks nothing, its
    folder is made read-only (needs a user other than root). It starts at the first output line containing "start"
    (at once without one) and ends at the first one containing "release" (with the run without one)."""

    def __init__(self, repo: pathlib.Path, spec: dict):
        self.path = repo / spec["path"]
        self.start, self.release = spec.get("start"), spec.get("release")
        self.held = self.done = False

    def take(self) -> None:
        if os.name == "nt":
            self.path.parent.mkdir(parents=True, exist_ok=True)
            if not self.path.exists() or not self.path.stat().st_size:
                self.path.write_text("held\n", encoding="utf-8", newline="\n")
            self.handle = self.path.open("rb")
            self.view = mmap.mmap(self.handle.fileno(), 0, access=mmap.ACCESS_READ)
        else:
            self.mode = self.path.parent.stat().st_mode
            self.path.parent.chmod(0o555)
        self.held = True

    def free(self) -> None:
        if self.held:
            if os.name == "nt":
                self.view.close()
                self.handle.close()
            else:
                self.path.parent.chmod(self.mode)
        self.held, self.done = False, True

    def see(self, line: str) -> None:
        if not self.held and not self.done and self.start and self.start in line:
            self.take()
        elif self.held and self.release and self.release in line:
            self.free()


def unlock_worktrees(repo: pathlib.Path) -> None:
    """Whatever kept the slice worktrees (here: their lock) is gone."""
    for line in git(repo, "worktree", "list", "--porcelain").splitlines():
        if line.startswith("worktree ") and ".claude/worktrees/" in line:
            subprocess.run(["git", "worktree", "unlock", line[9:]], cwd=repo, capture_output=True)


class Unlock(Hold):
    """A shell of the finished session that lets go of its worktree: the worktrees are unlocked at the first output line
    containing the text of the spec {"unlock": text}."""

    def __init__(self, repo: pathlib.Path, spec: dict):
        self.repo, self.start, self.release = repo, spec["unlock"], None
        self.held = self.done = False

    def take(self) -> None:
        unlock_worktrees(self.repo)
        self.held = True

    def free(self) -> None:
        self.held, self.done = False, True


class ReportReady(Hold):
    """A slice session that reports ready while the watch waits: at the watch's first line it writes the ready file of
    slice {"report_ready": nr} with the branch tip, as /slice does last before SLICE-READY."""

    def __init__(self, repo: pathlib.Path, spec: dict):
        self.repo, self.nr, self.start, self.release = repo, spec["report_ready"], "watching for SLICE-READY", None
        self.held = self.done = False

    def take(self) -> None:
        tip = git(self.repo, "rev-parse", f"slice-{self.nr}").strip()
        (self.repo / f".slice-loop/slice-{self.nr}.ready").write_text(tip + "\n", encoding="utf-8", newline="\n")
        self.held = True

    def free(self) -> None:
        self.held, self.done = False, True


def run_held(arguments: list[str], repo: pathlib.Path, env: dict, specs: list[dict]) -> subprocess.CompletedProcess:
    """Runs the loop while other processes hold files (Hold), reading its output as it comes to start and end each hold."""
    kinds = {"unlock": Unlock, "report_ready": ReportReady}
    holds = [next((kind for key, kind in kinds.items() if key in spec), Hold)(repo, spec) for spec in specs]
    for hold in holds:
        if not hold.start:
            hold.take()
    process = subprocess.Popen(arguments, cwd=repo, env=env, stdin=subprocess.DEVNULL, stdout=subprocess.PIPE,
                               stderr=subprocess.STDOUT, text=True, encoding="utf-8")
    timer = threading.Timer(120, process.kill)
    timer.start()
    lines = []
    try:
        for line in process.stdout:
            lines.append(line)
            for hold in holds:
                hold.see(line)
        process.wait()
    finally:
        timer.cancel()
        for hold in holds:
            hold.free()
    return subprocess.CompletedProcess(arguments, process.returncode, "".join(lines), "")


def run_case(shell: str, repo: pathlib.Path, bin_dir: pathlib.Path, profile: dict, options: list[str], env: dict,
             holds: list[dict] | None = None) -> subprocess.CompletedProcess:
    script = script_path(profile, shell)
    if not script.exists():
        # Not left to the shell: a missing .ps1 would not give a failing exit code under -Command.
        return subprocess.CompletedProcess([], 127, "", f"script missing: {script}")
    if shell == "bash":
        body = f'bash "{posix(script)}" ' + " ".join(options)
    else:
        body = f"& '{script}' " + pwsh_arguments(options) + "; exit $LASTEXITCODE"
    stub_env = dict(os.environ, STUB_FOLDER=profile["folder"], STUB_COMMAND=profile["command"], **env)
    if holds:
        return run_held(command(shell, bin_dir, body), repo, stub_env, holds)
    return subprocess.run(command(shell, bin_dir, body), cwd=repo, env=stub_env,
                          input="", capture_output=True, text=True, encoding="utf-8", timeout=120)


def calls_log(repo: pathlib.Path) -> str:
    log = repo / "stub-calls.log"
    return log.read_text(encoding="utf-8") if log.exists() else ""


def outcome(repo: pathlib.Path, profile: dict, result: subprocess.CompletedProcess) -> tuple[int, int, int, int]:
    ticked = (repo / profile["folder"] / "checklist.md").read_text(encoding="utf-8").count("\u2611") // 2
    calls = calls_log(repo)
    return result.returncode, ticked, calls.count("Build slice"), calls.count("close auto")


def git_problems(repo: pathlib.Path, profile: dict, result: subprocess.CompletedProcess, expected: dict) -> list[str]:
    """What the merge queue left in the repository that the case does not expect; the rebuild profile has no git."""
    if profile["folder"] != "work":
        return []
    problems = []
    status = git(repo, "status", "--porcelain")
    if status:
        problems.append(f"working tree not clean: {status!r}")
    branches = sorted(git(repo, "for-each-ref", "--format=%(refname:short)", "refs/heads/slice-*").split())
    if branches != sorted(expected.get("branches", [])):
        problems.append(f"slice branches left: {branches}")
    worktrees = git(repo, "worktree", "list", "--porcelain").count("worktree ") - 1
    if worktrees != len(branches):
        problems.append(f"{worktrees} slice worktrees left for {len(branches)} branches")
    subjects = git(repo, "log", "--reverse", "--format=%s").splitlines()[1:]
    if "subjects" in expected and subjects != expected["subjects"]:
        problems.append(f"commit subjects after the initial one: {subjects}")
    output = result.stdout + result.stderr
    says = expected.get("says", [])
    for text in [says] if isinstance(says, str) else says:
        if text not in output:
            problems.append(f"output does not name {text!r}")
    if "says_not" in expected and expected["says_not"] in output:
        problems.append(f"output names {expected['says_not']!r}")
    at = -1
    for text in expected.get("says_order", []):
        at = output.find(text, at + 1)
        if at < 0:
            problems.append(f"output lacks {text!r} after the lines before it")
            break
    if "lock" in expected or "lock_gone" in expected:
        lock_there = (repo / ".slice-loop/full-suite.lock").exists()
        if lock_there == expected.get("lock_gone", False):
            problems.append(f"full-suite lock {'is still there' if lock_there else 'is gone'}")
    if expected.get("no_calls") and calls_log(repo):
        problems.append("claude was called")
    if "keeps" in expected and not (repo / expected["keeps"]).is_file():
        problems.append(f"{expected['keeps']} of the main checkout is gone")
    folder = repo / profile["folder"]
    record = (folder / "rounds/R01-test.md").read_text(encoding="utf-8").splitlines()
    checklist = (folder / "checklist.md").read_text(encoding="utf-8").splitlines()
    problems += [f"record lacks {line!r}" for line in expected.get("record_has", []) if line not in record]
    problems += [f"checklist lacks {line!r}" for line in expected.get("checklist_has", []) if line not in checklist]
    for path, lines in expected.get("file_has", {}).items():
        text = (repo / path).read_text(encoding="utf-8").splitlines()
        problems += [f"{path} lacks {line!r}" for line in lines if line not in text]
    for path, prefix, count in expected.get("file_count", []):
        found = sum(line.startswith(prefix) for line in (repo / path).read_text(encoding="utf-8").splitlines())
        if found != count:
            problems.append(f"{path} has {found} lines starting with {prefix!r}, not {count}")
    if "order" in expected and [line for line in record if line in expected["order"]] != expected["order"]:
        problems.append(f"record order: {[line for line in record if line.startswith('### ')]}")
    if "results" in expected and sum(line.startswith("Result:") for line in record) != expected["results"]:
        problems.append(f"record has {sum(line.startswith('Result:') for line in record)} Result lines")
    markers = [line for line in record + checklist if line.startswith(("<<<<<<<", "=======", ">>>>>>>", "|||||||"))]
    if markers:
        problems.append(f"conflict markers left: {markers}")
    return problems


def wrong_models(repo: pathlib.Path, profile: dict) -> list[str]:
    """Slice turns (plan and build) whose --model differs from the slice's "model" field; a profile without models expects none."""
    expected = profile.get("models", {})
    wrong = []
    for call in calls_log(repo).splitlines():
        slice_nr = re.search(r"(?:/\w+ |Build slice )(\d{2,})", call)
        if not slice_nr:
            continue
        passed = re.search(r"--model \| (\S+)", call)
        if (passed.group(1) if passed else None) != expected.get(slice_nr.group(1)):
            wrong.append(call)
    return wrong


def main() -> int:
    sys.stdout.reconfigure(encoding="utf-8", errors="replace")  # failure output carries ☑ and ☐; Windows consoles default to cp1252
    only = sys.argv[1] if len(sys.argv) > 1 else ""  # optional: run only cases whose name contains this text
    shells = [s for s in os.environ.get("LOOP_TEST_SHELLS", "bash pwsh").split() if shutil.which(s)]
    if not shells:
        print("no bash or pwsh found")
        return 1
    failures = 0
    with tempfile.TemporaryDirectory() as tmp:
        base = pathlib.Path(tmp)
        bin_dir = base / "bin"
        bin_dir.mkdir()
        stub = make_stub(bin_dir)
        for shell in shells:
            assert_stub_first(shell, bin_dir)
            for profile in PROFILES:
                for name, done, options, env, rounds, expected, *extra in profile["cases"]:
                    if only not in name:
                        continue
                    git_expected = extra[0] if extra else {}
                    repo = make_repo(base, dict(profile, slices=git_expected.get("slices", profile["slices"])), done, rounds, stub,
                                     git_expected.get("prepared", []), git_expected.get("main_row"), git_expected.get("main_change"))
                    prepare_state(repo, git_expected)
                    if git_expected.get("failing_commit"):
                        (repo / ".git/hooks/pre-commit").write_text("#!/bin/sh\nexit 1\n", encoding="utf-8", newline="\n")
                    result = run_case(shell, repo, bin_dir, profile, options, env, git_expected.get("holds"))
                    if "rerun" in git_expected:  # whatever kept the worktree is gone (here: its lock), then the queue runs again
                        unlock_worktrees(repo)
                        first = result
                        result = run_case(shell, repo, bin_dir, profile, git_expected["rerun"], env)
                        result.stdout, result.stderr = first.stdout + result.stdout, first.stderr + result.stderr
                    got = outcome(repo, profile, result)
                    problems = wrong_models(repo, profile) + git_problems(repo, profile, result, git_expected)
                    ok = got == expected and not problems and (options != ["--dry-run"] or result.stdout.split() == profile["dry_run_ready"])
                    failures += not ok
                    print(f"{'ok  ' if ok else 'FAIL'} {shell:4} {profile['plugin']:12} {name}: exit/ticked/builds/closes {got}")
                    if not ok:
                        print(result.stdout[-1500:], result.stderr[-1500:], *problems[:5], sep="\n")
    return 1 if failures else 0


if __name__ == "__main__":
    sys.exit(main())
