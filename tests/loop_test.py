"""Tests for the loop scripts of both plugins (assets/rebuild-loop and assets/slice-loop, .sh and .ps1)
with a fake claude CLI (no real Claude calls).

The vibe-coding profile runs in a real git repository: the fake claude builds each slice on its own branch and
worktree and ends with SLICE-READY, and the loop's merge queue squashes the branch in the main checkout.

Usage: python tests/loop_test.py   (bash and/or pwsh must be on PATH; missing shells are skipped)
"""
import json
import os
import pathlib
import re
import shutil
import subprocess
import sys
import tempfile

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
close = re.match(command + r" close auto$", message)
UNTICKED, TICKED = "\u2610", "\u2611"


def git(*arguments, cwd="."):
    subprocess.run(["git", *arguments], cwd=cwd, check=True, capture_output=True)


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


def append_to_record(worktree, nr):
    """Every /slice run adds to the open round record: a surprise and a manual-test block (STUB_RECORD_LINE adds one line more)."""
    rounds = f"{worktree}/{folder}/rounds"
    for name in sorted(os.listdir(rounds)) if os.path.isdir(rounds) else []:
        path = f"{rounds}/{name}"
        if open(path, encoding="utf-8").readline().strip() == "Status: open":
            lines = [f"- Slice {nr} stub surprise", f"### Slice {nr} stub check", f"Result: {UNTICKED}"]
            lines += [os.environ["STUB_RECORD_LINE"]] if os.environ.get("STUB_RECORD_LINE") else []
            open(path, "a", encoding="utf-8", newline="\n").write("\n".join(lines) + "\n")
            return


def build_on_branch(nr):
    """A /slice run in auto mode: its own worktree on slice-NN, the row ticked through Checks, the round record
    appended to, a task commit, the squash message in .slice-loop/ of the main checkout, then SLICE-READY."""
    worktree = f".claude/worktrees/slice-{nr}"
    if not os.path.isdir(worktree):
        git("worktree", "add", "-q", "-b", f"slice-{nr}", worktree, "HEAD")
    if os.environ.get("STUB_NO_TICK") != nr:
        tick(f"{worktree}/{folder}/checklist.md", nr, keep_commit=True)
    append_to_record(worktree, nr)
    file = os.environ.get("STUB_FILE", f"slice-{nr}.txt")
    open(f"{worktree}/{file}", "w", encoding="utf-8", newline="\n").write(os.environ.get("STUB_CONTENT", f"slice {nr}") + "\n")
    commit(worktree, f"Slice {nr} task commit", f"task-{nr}.msg")
    if os.environ.get("STUB_NO_MESSAGE") != nr:
        open(f".slice-loop/slice-{nr}.msg", "w", encoding="utf-8", newline="\n").write(f"Slice {nr} stub squash\n\nBody line.\n")
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
elif build:
    nr = build.group(1)
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

# One profile per plugin. Case: name, slices done before, options, env, rounds (None = default),
# expected (exit code, ticked slices, build turns, close turns), and for the vibe-coding profile an optional dict of
# git expectations: "prepared" (branches made before the run: nr, optional file, content, ready, message, record_line),
# "main_row" (a checklist row committed on main after the branches were made), "subjects" (commit subjects after the
# initial commit, oldest first), "branches" (slice-* branches left; default none), "says" / "says_not" (a phrase that
# is / is not in the loop's output), "no_calls" (no claude call), "record_has" (lines of work/rounds/R01-test.md),
# "results" (its number of "Result:" lines), "checklist_has" (lines of work/checklist.md). "dry_run_ready" is what
# --dry-run prints when the first three slices are done.
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
              "record_has": ["- Slice 100 stub surprise", "### Slice 100 stub check", "- Slice 101 stub surprise", "### Slice 101 stub check"],
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
            ("merge stops on a conflict in a foreign file", 3, ["--merge"], {}, None, (1, 4, 0, 0),
             {"prepared": [{"nr": "100", "file": "shared.txt", "content": "from 100"},
                           {"nr": "101", "file": "shared.txt", "content": "from 101"}],
              "subjects": ["Slice 100 stub squash"], "branches": ["slice-101"], "says": "merge conflict in shared.txt ",
              "says_not": "work/checklist.md", "no_calls": True}),
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
            ("merge leaves a branch whose row is not ticked through Checks", 3, ["--merge"], {}, None, (0, 3, 0, 0),
             {"prepared": [{"nr": "100", "ready": False}], "subjects": [], "branches": ["slice-100"], "no_calls": True}),
        ],
    },
]
# Options that start with "--" become PowerShell switches; a value after one (--max-slices 1) stays as it is.
PWSH_FLAGS = {"--yes": "-Yes", "--parallel": "-Parallel", "--dry-run": "-DryRun", "--max-slices": "-MaxSlices", "--merge": "-Merge"}
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
    (repo / ".git/info/exclude").write_text("stub-calls.log\nstub.lock\n.claude/worktrees/\n", encoding="utf-8", newline="\n")
    git(repo, "add", "-A")
    git(repo, "commit", "-q", "-m", "Initial state")


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
    subprocess.run([sys.executable, "-X", "utf8", str(stub), f"Build slice {branch['nr']} and close it"],
                   cwd=repo, env=env, check=True, capture_output=True)


def add_main_row(repo: pathlib.Path, profile: dict, nr: str) -> None:
    """A checklist row committed on main after the slice branches were cut."""
    checklist = repo / profile["folder"] / "checklist.md"
    with checklist.open("a", encoding="utf-8", newline="\n") as file:
        file.write(f"| {nr} Name | ☐ | ☐ |\n")
    git(repo, "commit", "-q", "-am", f"Add row {nr}")


def make_repo(base: pathlib.Path, profile: dict, done: int, rounds: list[tuple[str, str]] | None,
              stub: pathlib.Path, prepared: list[dict], main_row: str | None) -> pathlib.Path:
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
        (folder / f"rounds/{round_id}-test.md").write_text(f"Status: {status}\n", encoding="utf-8", newline="\n")
    init_git(repo)
    for branch in prepared:
        prepare_branch(repo, stub, profile, branch)
    if main_row:
        add_main_row(repo, profile, main_row)
    return repo


def command(shell: str, bin_dir: pathlib.Path, body: str) -> list[str]:
    # Full path: on Windows a bare "bash" would start WSL from System32 instead of the bash on PATH.
    executable = shutil.which(shell)
    if shell == "bash":
        return [executable, "-c", f'export PATH="{posix(bin_dir)}:$PATH"; {body}']
    return [executable, "-NoProfile", "-Command", f"$env:PATH = '{bin_dir}' + [IO.Path]::PathSeparator + $env:PATH; {body}"]


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


def run_case(shell: str, repo: pathlib.Path, bin_dir: pathlib.Path, profile: dict, options: list[str], env: dict) -> subprocess.CompletedProcess:
    script = script_path(profile, shell)
    if not script.exists():
        # Not left to the shell: a missing .ps1 would not give a failing exit code under -Command.
        return subprocess.CompletedProcess([], 127, "", f"script missing: {script}")
    if shell == "bash":
        body = f'bash "{posix(script)}" ' + " ".join(options)
    else:
        body = f"& '{script}' " + pwsh_arguments(options) + "; exit $LASTEXITCODE"
    stub_env = dict(os.environ, STUB_FOLDER=profile["folder"], STUB_COMMAND=profile["command"], **env)
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
    if "says" in expected and expected["says"] not in output:
        problems.append(f"output does not name {expected['says']!r}")
    if "says_not" in expected and expected["says_not"] in output:
        problems.append(f"output names {expected['says_not']!r}")
    if expected.get("no_calls") and calls_log(repo):
        problems.append("claude was called")
    folder = repo / profile["folder"]
    record = (folder / "rounds/R01-test.md").read_text(encoding="utf-8").splitlines()
    checklist = (folder / "checklist.md").read_text(encoding="utf-8").splitlines()
    problems += [f"record lacks {line!r}" for line in expected.get("record_has", []) if line not in record]
    problems += [f"checklist lacks {line!r}" for line in expected.get("checklist_has", []) if line not in checklist]
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
    shells = [s for s in ("bash", "pwsh") if shutil.which(s)]
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
                    git_expected = extra[0] if extra else {}
                    repo = make_repo(base, profile, done, rounds, stub, git_expected.get("prepared", []), git_expected.get("main_row"))
                    result = run_case(shell, repo, bin_dir, profile, options, env)
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
