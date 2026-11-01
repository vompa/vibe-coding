"""--notify of the hands-off loop: a problem or a question of a slice wakes the chat, nothing else does, nothing is lost.

Usage: python tests/slice_notify_test.py
"""
import json
import os
import pathlib
import subprocess
import sys
import tempfile

SCRIPT = pathlib.Path(__file__).resolve().parent.parent / "plugins/vibe-coding/skills/vibe-coding/assets/slice_loop.py"


def make_repo(folder: pathlib.Path, is_open: bool = True) -> None:
    (folder / "work/rounds").mkdir(parents=True)
    (folder / ".slice-loop").mkdir()
    (folder / "work/_slices.json").write_text(json.dumps([{"nr": "01", "deps": "–"}]), encoding="utf-8")
    (folder / "work/checklist.md").write_text("| 01 a | ☐ |\n", encoding="utf-8")
    (folder / "work/rounds/R01.md").write_text(f"Status: {'open' if is_open else 'closed'}\n", encoding="utf-8")


def add_events(folder: pathlib.Path, *events: dict) -> None:
    with open(folder / ".slice-loop/events.jsonl", "a", encoding="utf-8", newline="\n") as handle:
        for event in events:
            handle.write(json.dumps(event, ensure_ascii=False) + "\n")


def notify(folder: pathlib.Path, checks: int = 1) -> str:
    env = {**os.environ, "SLICE_WATCH_SECONDS": "0", "SLICE_WATCH_MAX": str(checks), "PYTHONUTF8": "1"}
    done = subprocess.run([sys.executable, str(SCRIPT), "--notify"], cwd=folder, env=env, capture_output=True, encoding="utf-8", check=False)
    assert done.returncode == 0, done.stderr
    return done.stdout


def test_problems_and_questions_are_named_and_finished_slices_are_not():
    with tempfile.TemporaryDirectory() as root:
        folder = pathlib.Path(root)
        make_repo(folder)
        (folder / ".slice-loop/notify.seen").write_text("0\n", encoding="utf-8")
        add_events(folder,
                   {"type": "slice_merged", "slice": "01"},
                   {"type": "slice_parked", "slice": "02", "reason": "Which tax rate?", "question": "yes"},
                   {"type": "slice_parked", "slice": "03", "reason": "tests red"},
                   {"type": "slice_left", "slice": "04", "reason": "check red"},
                   {"type": "slice_stalled", "slice": "05"},
                   {"type": "slice_parked", "slice": "06", "reason": "NEEDS-DECISION: Which licence?", "question": "yes"},
                   {"type": "loop_stopped", "reason": "uncommitted changes"})
        lines = notify(folder).splitlines()
        assert len(lines) == 6, lines
        assert lines[4].startswith("SLICE-QUESTION: 06 Which licence?")
        assert lines[5].startswith("SLICE-PROBLEM: the loop stopped: uncommitted changes")
        assert lines[0].startswith("SLICE-QUESTION: 02 Which tax rate?") and "slice-02.answer" in lines[0]
        assert lines[1].startswith("SLICE-PROBLEM: 03 parked: tests red")
        assert lines[2].startswith("SLICE-PROBLEM: 04 left behind: check red")
        assert lines[3].startswith("SLICE-PROBLEM: 05 stalled")


def test_a_restart_goes_on_where_the_last_one_stopped():
    with tempfile.TemporaryDirectory() as root:
        folder = pathlib.Path(root)
        make_repo(folder)
        add_events(folder, {"type": "slice_left", "slice": "01", "reason": "before the chat"})
        # The first start begins at the end of the history: an old problem wakes nobody.
        assert notify(folder).startswith("SLICE-NOTIFY: no problem after 1")
        # What happens between two starts is not lost, and is told once.
        add_events(folder, {"type": "slice_left", "slice": "02", "reason": "between two starts"})
        assert "between two starts" in notify(folder)
        assert notify(folder).startswith("SLICE-NOTIFY: no problem after 1")


def test_it_ends_when_no_round_is_open():
    with tempfile.TemporaryDirectory() as root:
        folder = pathlib.Path(root)
        make_repo(folder, is_open=False)
        assert notify(folder, checks=5).startswith("SLICE-NOTIFY: no open round")


if __name__ == "__main__":
    for name, fn in list(globals().items()):
        if name.startswith("test_"):
            fn()
            print("ok  ", name)
