# tests/goal_evidence_test.py
"""vibe-rebuild: the goal-contract hook keeps approved contracts frozen; evidence.py closes a slice only on evidence."""
import json, os, pathlib, subprocess, sys, tempfile, time
ASSETS = pathlib.Path(__file__).resolve().parent.parent / "plugins/vibe-rebuild/skills/vibe-rebuild/assets"
HOOK, EVIDENCE = ASSETS / "protect-goal.py", ASSETS / "evidence.py"
PY = sys.executable

def hook(repo, tool, tool_input):
    event = {"tool_name": tool, "tool_input": tool_input, "cwd": str(repo)}
    return subprocess.run([PY, str(HOOK)], input=json.dumps(event), capture_output=True, text=True)

def contract(repo, status):
    path = pathlib.Path(repo, "rebuild/goal/contract-v001.md")
    path.parent.mkdir(parents=True, exist_ok=True)
    path.write_text(f"# Goal contract v001\nStatus: {status}\n", encoding="utf-8")
    return path

def test_hook_blocks_edits_to_an_approved_contract():
    with tempfile.TemporaryDirectory() as repo:
        path = contract(repo, "APPROVED – User, 2026-10-31")
        proc = hook(repo, "Edit", {"file_path": str(path), "old_string": "x", "new_string": "y"})
        assert proc.returncode == 2 and "change-requests.md" in proc.stderr
        proc = hook(repo, "Write", {"file_path": "rebuild/goal/contract-v001.md", "content": "z"})
        assert proc.returncode == 2, "relative paths resolve against cwd"

def test_hook_lets_agents_draft_but_not_approve():
    with tempfile.TemporaryDirectory() as repo:
        path = contract(repo, "READY_FOR_APPROVAL")
        assert hook(repo, "Edit", {"file_path": str(path), "old_string": "a", "new_string": "REQ-02 …"}).returncode == 0
        proc = hook(repo, "Edit", {"file_path": str(path), "old_string": "READY_FOR_APPROVAL", "new_string": "Status: APPROVED"})
        assert proc.returncode == 2 and "Only the user" in proc.stderr
        new = str(pathlib.Path(repo, "rebuild/goal/contract-v002.md"))
        assert hook(repo, "Write", {"file_path": new, "content": "# v002\nStatus: APPROVED\n"}).returncode == 2
        assert hook(repo, "MultiEdit", {"file_path": str(path), "edits": [{"new_string": "  Status: APPROVED"}]}).returncode == 2

def test_hook_ignores_other_files_tools_and_bad_input():
    with tempfile.TemporaryDirectory() as repo:
        contract(repo, "APPROVED")
        assert hook(repo, "Write", {"file_path": "rebuild/goal/change-requests.md", "content": "CR-01"}).returncode == 0
        assert hook(repo, "Write", {"file_path": "rebuild/PRD.md", "content": "Status: APPROVED"}).returncode == 0
        assert hook(repo, "Read", {"file_path": "rebuild/goal/contract-v001.md"}).returncode == 0
        assert subprocess.run([PY, str(HOOK)], input="not json", capture_output=True, text=True).returncode == 0

def ev(repo, *args):
    return subprocess.run([PY, str(EVIDENCE), *args], cwd=repo, capture_output=True, text=True)

def slices(repo, acs):
    path = pathlib.Path(repo, "rebuild/_slices.json")
    path.parent.mkdir(parents=True, exist_ok=True)
    path.write_text(json.dumps([{"nr": "03", "acs": acs}]), encoding="utf-8")

def review(repo, lines):
    path = pathlib.Path(repo, "rebuild/evidence/03/review.md")
    path.parent.mkdir(parents=True, exist_ok=True)
    path.write_text("\n".join(lines) + "\n", encoding="utf-8")
    return "rebuild/evidence/03/review.md"

FAIL, PASS = f'{PY} -c "import sys; sys.exit(3)"', f'{PY} -c "print(42)"'

def test_slice_closes_only_when_every_node_is_evidenced():
    with tempfile.TemporaryDirectory() as repo:
        slices(repo, "AC-03, AC-07")
        assert ev(repo, "start", "03").returncode == 0
        proc = ev(repo, "check", "03")
        assert proc.returncode == 1 and "NOT DONE: 5 node(s)" in proc.stdout and "ac:AC-07" in proc.stdout
        assert ev(repo, "run", "03", "red", "--", FAIL).returncode == 0, "a failing red run is the evidence"
        assert ev(repo, "run", "03", "suite", "--", PASS).returncode == 0
        assert ev(repo, "run", "03", "ac:AC-03", "--", PASS).returncode == 0
        assert ev(repo, "add", "03", "ac:AC-07", "--waived", "covered by parity case BC-04").returncode == 0
        assert ev(repo, "add", "03", "review", "--file", review(repo, ["- AC-03: PASS", "verdict=pass"])).returncode == 1
        assert ev(repo, "add", "03", "review", "--file", review(repo, ["- AC-03: PASS", "- AC-07: PASS", "verdict=pass"])).returncode == 0
        proc = ev(repo, "check", "03")
        assert proc.returncode == 0 and "EVIDENCE OK: 03" in proc.stdout
        assert json.loads(pathlib.Path(repo, "rebuild/evidence/03.json").read_text())["nodes"]["suite"]["exit"] == 0

def test_claims_do_not_count():
    with tempfile.TemporaryDirectory() as repo:
        slices(repo, "–")
        ev(repo, "start", "03")
        assert ev(repo, "run", "03", "red", "--", PASS).returncode == 1, "a passing red run proves nothing"
        assert ev(repo, "run", "03", "suite", "--", FAIL).returncode == 1
        assert ev(repo, "add", "03", "suite", "--waived", "trust me").returncode == 1, "suite cannot be waived"
        record = pathlib.Path(repo, "rebuild/evidence/03.json")
        data = json.loads(record.read_text())
        data["nodes"]["review"] = {"kind": "log", "path": "rebuild/evidence/03/review.md"}  # hand-written claim
        record.write_text(json.dumps(data))
        proc = ev(repo, "check", "03")
        assert proc.returncode == 1 and "claimed" in proc.stdout
        assert ev(repo, "show", "03").returncode == 0, "show never fails"

def test_old_logs_do_not_count():
    with tempfile.TemporaryDirectory() as repo:
        slices(repo, [])
        log = pathlib.Path(repo, "old.log"); log.write_text("ok\nexit=0\n")
        past = time.time() - 3600; os.utime(log, (past, past))
        ev(repo, "start", "03")
        proc = ev(repo, "add", "03", "suite", "--file", "old.log")
        assert proc.returncode == 1 and "older than the slice start" in proc.stdout

def test_start_keeps_the_first_stamp():
    with tempfile.TemporaryDirectory() as repo:
        slices(repo, [])
        ev(repo, "start", "03")
        first = json.loads(pathlib.Path(repo, "rebuild/evidence/03.json").read_text())["started"]
        assert "keeping that stamp" in ev(repo, "start", "03").stdout
        assert json.loads(pathlib.Path(repo, "rebuild/evidence/03.json").read_text())["started"] == first

def test_commit_evidence_needs_a_new_reachable_commit():
    with tempfile.TemporaryDirectory() as repo:
        slices(repo, ["AC-01"])
        env = {**os.environ, "GIT_AUTHOR_NAME": "t", "GIT_AUTHOR_EMAIL": "t@example.org",
               "GIT_COMMITTER_NAME": "t", "GIT_COMMITTER_EMAIL": "t@example.org"}
        git = lambda *a: subprocess.run(["git", *a], cwd=repo, env=env, capture_output=True, text=True, check=True).stdout.strip()
        git("init", "-q")
        subprocess.run(["git", "commit", "-q", "--allow-empty", "-m", "before"], cwd=repo, check=True,
                       env={**env, "GIT_COMMITTER_DATE": "2000-01-01T00:00:00"})
        old = git("rev-parse", "HEAD")
        ev(repo, "start", "03")
        assert "older than the slice start" in ev(repo, "add", "03", "ac:AC-01", "--sha", old).stdout
        git("commit", "-q", "--allow-empty", "-m", "after")
        assert ev(repo, "add", "03", "ac:AC-01", "--sha", git("rev-parse", "HEAD")).returncode == 0
        assert "not found" in ev(repo, "add", "03", "ac:AC-01", "--sha", "deadbeef").stdout

def test_unknown_node_is_refused():
    with tempfile.TemporaryDirectory() as repo:
        slices(repo, ["AC-01"])
        ev(repo, "start", "03")
        proc = ev(repo, "run", "03", "ac:AC-99", "--", PASS)
        assert proc.returncode != 0 and "Unknown node" in proc.stderr

if __name__ == "__main__":
    for name, fn in list(globals().items()):
        if name.startswith("test_"):
            fn(); print("ok  ", name)
