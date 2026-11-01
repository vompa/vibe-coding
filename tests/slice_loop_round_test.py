"""The hands-off loop of vibe-coding works only the slices of the open round: slices of a round planned ahead wait.

Usage: python tests/slice_loop_round_test.py
"""
import importlib.util
import json
import os
import pathlib
import subprocess
import sys
import tempfile

ROOT = pathlib.Path(__file__).resolve().parent.parent
SCRIPT = ROOT / "plugins/vibe-coding/skills/vibe-coding/assets/slice_loop.py"
SLICES = [
    {"nr": "01", "deps": "–", "round": "R01"},
    {"nr": "02", "deps": "–", "round": "R02"},
    {"nr": "03", "deps": "–"},  # written before slices named their round: it belongs to whatever round is open
]
OPEN, DONE = "| ☐ | ☐ |", "| ☑ | ☑ |"


def make_repo(folder: pathlib.Path, states: dict[str, str], slices: list[dict] = SLICES) -> None:
    (folder / "work/rounds").mkdir(parents=True)
    (folder / "work/_slices.json").write_text(json.dumps(slices), encoding="utf-8")
    rows = "".join(f"| {nr} slice {state}\n" for nr, state in states.items())
    (folder / "work/checklist.md").write_text(f"| Slice | Plan | Commit |\n|---|---|---|\n{rows}", encoding="utf-8")
    (folder / "work/rounds/R01-open.md").write_text("Status: open\n", encoding="utf-8")
    (folder / "work/rounds/R02-planned.md").write_text("Status: planned\n", encoding="utf-8")


def load_loop():
    spec = importlib.util.spec_from_file_location("slice_loop", SCRIPT)
    module = importlib.util.module_from_spec(spec)
    sys.modules["slice_loop"] = module
    spec.loader.exec_module(module)
    return module.Loop()


def check(name: str, got, expected) -> bool:
    print(f"{'ok  ' if got == expected else 'FAIL'} {name}: {got!r}" + ("" if got == expected else f", expected {expected!r}"))
    return got == expected


def main() -> int:
    passed = True
    start = os.getcwd()
    with tempfile.TemporaryDirectory() as temp:
        try:
            first = pathlib.Path(temp, "first")
            make_repo(first, {"01": OPEN, "02": OPEN, "03": OPEN})
            result = subprocess.run([sys.executable, str(SCRIPT), "--dry-run"], cwd=first, capture_output=True, text=True, encoding="utf-8")
            passed &= check("dry run leaves out the planned round", result.stdout.split(), ["01", "03"])

            os.chdir(first)
            loop = load_loop()
            passed &= check("open count leaves out the planned round", loop.open_count(), 2)
            passed &= check("round with open slices is not done", loop.all_done(), False)

            second = pathlib.Path(temp, "second")
            make_repo(second, {"01": DONE, "02": OPEN, "03": DONE})
            os.chdir(second)
            loop = load_loop()
            passed &= check("open round done although a planned slice is open", loop.all_done(), True)
            passed &= check("nothing ready once the open round is done", loop.ready_slices(), [])

            third = pathlib.Path(temp, "third")
            make_repo(third, {"02": OPEN}, [{"nr": "02", "deps": "–", "round": "R02"}])
            result = subprocess.run([sys.executable, str(SCRIPT), "--yes"], cwd=third, capture_output=True, text=True, encoding="utf-8",
                                    env={**os.environ, "PATH": ""})
            passed &= check("open round without slices exits cleanly", result.returncode, 0)
            passed &= check("open round without slices says why", "no slices" in result.stdout + result.stderr, True)
        finally:
            os.chdir(start)
    return 0 if passed else 1


if __name__ == "__main__":
    sys.exit(main())
