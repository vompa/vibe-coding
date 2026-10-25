"""Tests for the loop scripts of both plugins (assets/rebuild-loop and assets/slice-loop, .sh and .ps1)
with a fake claude CLI (no real Claude calls).

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
import os, re, sys
args = sys.argv[1:]
message = args[-1]
folder = os.environ["STUB_FOLDER"]  # per profile: rebuild or work
command = re.escape(os.environ["STUB_COMMAND"])  # per profile: /rebuild or /slice – any other command is unknown
open("stub-calls.log", "a", encoding="utf-8").write(" | ".join(args) + "\n")
plan = re.match(command + r" (\d{2,}) plan auto", message)
build = re.search(r"Build slice (\d{2,}) and close it", message)
close = re.match(command + r" close auto$", message)
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
    if os.environ.get("STUB_NO_TICK") == nr:
        print(f"SLICE-DONE: {nr}")
        sys.exit(0)
    # Parallel builds tick at the same time: lock the checklist like git would serialise the merges.
    import time
    while True:
        try:
            lock = os.open(f"{folder}/checklist.lock", os.O_CREAT | os.O_EXCL)
            break
        except FileExistsError:
            time.sleep(0.05)
    try:
        path = f"{folder}/checklist.md"
        lines = open(path, encoding="utf-8").read().split("\n")
        lines = [l.replace("\u2610", "\u2611") if re.match(rf"^\|\s*{nr}\b", l) else l for l in lines]
        open(path, "w", encoding="utf-8", newline="\n").write("\n".join(lines))
    finally:
        os.close(lock)
        os.remove(f"{folder}/checklist.lock")
    print(f"SLICE-DONE: {nr}")
else:
    sys.exit(2)
'''

# One profile per plugin. Case: name, slices done before, options, env, rounds (None = default),
# expected (exit code, ticked slices, build turns, close turns). "dry_run_ready" is what --dry-run
# prints when the first three slices are done.
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
            ("auto approve runs all slices then closes the round", 1, ["--yes"], {}, None, (0, 5, 4, 1)),
            ("three-digit slice is ticked and built", 3, ["--yes", "--max-slices", "1"], {}, None, (0, 4, 1, 0)),
            ("parallel builds both ready slices", 3, ["--yes", "--parallel"], {}, None, (0, 5, 2, 1)),
            ("red slice stops the loop", 3, ["--yes"], {"STUB_FAIL": "100"}, None, (1, 3, 1, 0)),
            ("done but not ticked stops instead of rebuilding", 3, ["--yes"], {"STUB_NO_TICK": "100"}, None, (1, 3, 1, 0)),
            ("decision without terminal does not build", 3, ["--yes"], {"STUB_DECISION": "100"}, None, (1, 3, 0, 0)),
            ("approval without terminal does not build", 3, [], {}, None, (1, 3, 0, 0)),
            ("max slices stops after one with slices left", 1, ["--yes", "--max-slices", "1"], {}, None, (0, 2, 1, 0)),
            ("close fails keeps the round open", 4, ["--yes"], {"STUB_CLOSE_FAIL": "1"}, None, (1, 5, 1, 1)),
            ("second round open runs on it", 3, ["--yes", "--max-slices", "1"], {},
             [("R01", "closed"), ("R02", "open")], (0, 4, 1, 0)),
            ("no open round exits without building", 3, ["--yes"], {}, [("R01", "closed")], (0, 3, 0, 0)),
            ("all done and closed exits cleanly", 5, [], {}, [("R01", "closed")], (0, 5, 0, 0)),
        ],
    },
]
# Options that start with "--" become PowerShell switches; a value after one (--max-slices 1) stays as it is.
PWSH_FLAGS = {"--yes": "-Yes", "--parallel": "-Parallel", "--dry-run": "-DryRun", "--max-slices": "-MaxSlices"}


def posix(path: pathlib.Path) -> str:
    """Path as bash sees it; C:/x would split PATH at the colon on Windows."""
    text = path.as_posix()
    return f"/{text[0].lower()}{text[2:]}" if os.name == "nt" and text[1:2] == ":" else text


def make_stub(bin_dir: pathlib.Path) -> None:
    stub = bin_dir / "claude_stub.py"
    stub.write_text(STUB, encoding="utf-8")
    wrapper = bin_dir / "claude"
    # The script argument stays C:/… – the .sh loop scripts turn off Git Bash path conversion.
    wrapper.write_text(f'#!/usr/bin/env bash\nexec "{posix(pathlib.Path(sys.executable))}" -X utf8 "{stub.as_posix()}" "$@"\n',
                       encoding="utf-8", newline="\n")
    wrapper.chmod(0o755)
    # The .ps1 loop scripts resolve claude as an application, so Windows needs a .cmd, not a .ps1.
    (bin_dir / "claude.cmd").write_text(f'@"{sys.executable}" -X utf8 "{stub}" %*\r\n', encoding="utf-8")


def make_repo(base: pathlib.Path, profile: dict, done: int, rounds: list[tuple[str, str]] | None = None) -> pathlib.Path:
    """Plan repo with the first `done` slices ticked; the slice loop also gets one record per round."""
    repo = pathlib.Path(tempfile.mkdtemp(dir=base))
    folder = repo / profile["folder"]
    folder.mkdir()
    (repo / ".git/info").mkdir(parents=True)
    slices = profile["slices"]
    (folder / "_slices.json").write_text(json.dumps(slices, ensure_ascii=False), encoding="utf-8")
    rows = ["| Slice | Plan | Commit |", "|---|---|---|"]
    rows += [f"| {s['nr']} Name | " + ("\u2611 | \u2611 |" if i < done else "\u2610 | \u2610 |") for i, s in enumerate(slices)]
    (folder / "checklist.md").write_text("\n".join(rows) + "\n", encoding="utf-8")
    if profile["folder"] == "work":  # only the slice loop has rounds
        (folder / "rounds").mkdir()
        for round_id, status in rounds or [("R01", "open")]:
            (folder / f"rounds/{round_id}-test.md").write_text(f"Status: {status}\n", encoding="utf-8")
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
    shells = [s for s in ("bash", "pwsh") if shutil.which(s)]
    if not shells:
        print("no bash or pwsh found")
        return 1
    failures = 0
    with tempfile.TemporaryDirectory() as tmp:
        base = pathlib.Path(tmp)
        bin_dir = base / "bin"
        bin_dir.mkdir()
        make_stub(bin_dir)
        for shell in shells:
            assert_stub_first(shell, bin_dir)
            for profile in PROFILES:
                for name, done, options, env, rounds, expected in profile["cases"]:
                    repo = make_repo(base, profile, done, rounds)
                    result = run_case(shell, repo, bin_dir, profile, options, env)
                    got = outcome(repo, profile, result)
                    models = wrong_models(repo, profile)
                    ok = got == expected and not models and (options != ["--dry-run"] or result.stdout.split() == profile["dry_run_ready"])
                    failures += not ok
                    print(f"{'ok  ' if ok else 'FAIL'} {shell:4} {profile['plugin']:12} {name}: exit/ticked/builds/closes {got}")
                    if not ok:
                        print(result.stdout[-1500:], result.stderr[-1500:], *models[:3], sep="\n")
    return 1 if failures else 0


if __name__ == "__main__":
    sys.exit(main())
