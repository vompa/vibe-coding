"""Tests for assets/rebuild-loop.sh and .ps1 with a fake claude CLI (no real Claude calls).

Usage: python tests/rebuild_loop_test.py   (bash and/or pwsh must be on PATH; missing shells are skipped)
"""
import json
import os
import pathlib
import shutil
import subprocess
import sys
import tempfile

ROOT = pathlib.Path(__file__).resolve().parent.parent
ASSETS = ROOT / "plugins/vibe-rebuild/skills/vibe-rebuild/assets"
SLICES = [
    {"nr": "00", "deps": "–"}, {"nr": "01", "deps": "00"}, {"nr": "02", "deps": "01"},
    {"nr": "03", "deps": "02"}, {"nr": "04", "deps": "02"},
]
STUB = r'''
import os, re, sys
args = sys.argv[1:]
message = args[-1]
open("stub-calls.log", "a", encoding="utf-8").write(" | ".join(args) + "\n")
plan = re.match(r"/rebuild (\d{2}) plan auto", message)
build = re.search(r"Build slice (\d{2}) and close it", message)
if plan:
    print(f"PLAN: rebuild/plans/slice-{plan.group(1)}.md")
    if os.environ.get("STUB_DECISION") == plan.group(1):
        print("NEEDS-DECISION: Which licence?")
elif build:
    nr = build.group(1)
    if os.environ.get("STUB_FAIL") == nr:
        print(f"SLICE-OPEN: {nr} tests red")
        sys.exit(0)
    path = "rebuild/checklist.md"
    lines = open(path, encoding="utf-8").read().split("\n")
    lines = [l.replace("\u2610", "\u2611") if re.match(rf"^\|\s*{nr}\b", l) else l for l in lines]
    open(path, "w", encoding="utf-8", newline="\n").write("\n".join(lines))
    print(f"SLICE-DONE: {nr}")
else:
    sys.exit(2)
'''

CASES = [
    # name, slices done before, options, env, expected (exit code, ticked slices, build turns)
    ("dry run lists ready slices", 3, ["--dry-run"], {}, (0, 3, 0)),
    ("auto approve runs all slices", 1, ["--yes"], {}, (0, 5, 4)),
    ("parallel builds both ready slices", 3, ["--yes", "--parallel"], {}, (0, 5, 2)),
    ("red slice stops the loop", 3, ["--yes"], {"STUB_FAIL": "03"}, (1, 3, 1)),
    ("decision without terminal does not build", 3, ["--yes"], {"STUB_DECISION": "03"}, (1, 3, 0)),
    ("approval without terminal does not build", 3, [], {}, (1, 3, 0)),
    ("all done exits cleanly", 5, [], {}, (0, 5, 0)),
]
PWSH_FLAGS = {"--yes": "-Yes", "--parallel": "-Parallel", "--dry-run": "-DryRun"}


def posix(path: pathlib.Path) -> str:
    """Path as bash sees it; C:/x would split PATH at the colon on Windows."""
    text = path.as_posix()
    return f"/{text[0].lower()}{text[2:]}" if os.name == "nt" and text[1:2] == ":" else text


def make_stub(bin_dir: pathlib.Path) -> None:
    stub = bin_dir / "claude_stub.py"
    stub.write_text(STUB, encoding="utf-8")
    wrapper = bin_dir / "claude"
    # The script argument stays C:/… – rebuild-loop.sh turns off Git Bash path conversion.
    wrapper.write_text(f'#!/usr/bin/env bash\nexec "{posix(pathlib.Path(sys.executable))}" -X utf8 "{stub.as_posix()}" "$@"\n',
                       encoding="utf-8", newline="\n")
    wrapper.chmod(0o755)
    (bin_dir / "claude.ps1").write_text(f"& '{sys.executable}' -X utf8 '{stub}' @args; exit $LASTEXITCODE\n", encoding="utf-8")


def make_repo(base: pathlib.Path, done: int) -> pathlib.Path:
    repo = pathlib.Path(tempfile.mkdtemp(dir=base))
    (repo / "rebuild").mkdir()
    (repo / ".git/info").mkdir(parents=True)
    (repo / "rebuild/_slices.json").write_text(json.dumps(SLICES, ensure_ascii=False), encoding="utf-8")
    rows = ["| Slice | Plan | Commit |", "|---|---|---|"]
    rows += [f"| {s['nr']} Name | " + ("\u2611 | \u2611 |" if i < done else "\u2610 | \u2610 |") for i, s in enumerate(SLICES)]
    (repo / "rebuild/checklist.md").write_text("\n".join(rows) + "\n", encoding="utf-8")
    return repo


def command(shell: str, bin_dir: pathlib.Path, body: str) -> list[str]:
    # Full path: on Windows a bare "bash" would start WSL from System32 instead of the bash on PATH.
    executable = shutil.which(shell)
    if shell == "bash":
        return [executable, "-c", f'export PATH="{posix(bin_dir)}:$PATH"; {body}']
    return [executable, "-NoProfile", "-Command", f"$env:PATH = '{bin_dir}' + [IO.Path]::PathSeparator + $env:PATH; {body}"]


def assert_stub_first(shell: str, bin_dir: pathlib.Path) -> None:
    """Never let a test reach the real claude CLI."""
    probe = "command -v claude" if shell == "bash" else "(Get-Command claude).Source"
    found = subprocess.run(command(shell, bin_dir, probe), capture_output=True, text=True).stdout.strip()
    if "claude_stub" not in found and not found.startswith((posix(bin_dir), str(bin_dir))):
        sys.exit(f"{shell}: claude resolves to {found!r}, not the stub – aborting")


def run_case(shell: str, repo: pathlib.Path, bin_dir: pathlib.Path, options: list[str], env: dict) -> subprocess.CompletedProcess:
    if shell == "bash":
        body = f'bash "{posix(ASSETS / "rebuild-loop.sh")}" ' + " ".join(options)
    else:
        body = f"& '{ASSETS / 'rebuild-loop.ps1'}' " + " ".join(PWSH_FLAGS[o] for o in options) + "; exit $LASTEXITCODE"
    return subprocess.run(command(shell, bin_dir, body), cwd=repo, env=dict(os.environ, **env), input="",
                          capture_output=True, text=True, encoding="utf-8", timeout=120)


def outcome(repo: pathlib.Path, result: subprocess.CompletedProcess) -> tuple[int, int, int]:
    ticked = (repo / "rebuild/checklist.md").read_text(encoding="utf-8").count("\u2611") // 2
    log = repo / "stub-calls.log"
    builds = log.read_text(encoding="utf-8").count("Build slice") if log.exists() else 0
    return result.returncode, ticked, builds


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
            for name, done, options, env, expected in CASES:
                repo = make_repo(base, done)
                result = run_case(shell, repo, bin_dir, options, env)
                got = outcome(repo, result)
                ok = got == expected and (not options == ["--dry-run"] or result.stdout.split() == ["03", "04"])
                failures += not ok
                print(f"{'ok  ' if ok else 'FAIL'} {shell:4} {name}: exit/ticked/builds {got}")
                if not ok:
                    print(result.stdout[-1500:], result.stderr[-1500:], sep="\n")
    return 1 if failures else 0


if __name__ == "__main__":
    sys.exit(main())
