# tests/markers_test.py
import pathlib, re
ROOT = pathlib.Path(__file__).resolve().parent.parent
SKILL = ROOT / "plugins/vibe-coding/skills/vibe-coding"
MARKERS = ["PLAN:", "NEEDS-DECISION:", "SLICE-DONE:", "SLICE-OPEN:", "ALL-DONE", "ROUND-DONE:", "ROUND-OPEN:", "SLICE-READY:", "SLICE-WAIT:"]

def test_command_defines_every_marker():
    text = (SKILL / "references/slice-command.md").read_text(encoding="utf-8")
    for m in MARKERS: assert m in text, m
    assert 'argument-hint: "[status | NN | close] [plan] [auto | parallel] [direct]"' in text
    assert "work/conventions.md" in text and "git merge --squash" in text and "never push" in text.lower()

def test_command_offers_parallel_sessions_outside_auto():
    text = (SKILL / "references/slice-command.md").read_text(encoding="utf-8")
    section = text.split("## 7. Parallel slices", 1)[1]
    assert text.count("(section 7)") >= 3, "status, nothing and the close of a slice point to section 7"
    assert "never in auto mode" in section and "Offer, never start unasked" in section
    assert "Never two sessions on one slice" in section and "ready-to-paste prompt" in section

def test_loop_scripts_read_the_same_markers():
    for name, merge_option in (("slice-loop.sh", "--merge"), ("slice-loop.ps1", "-Merge")):
        text = (SKILL / f"assets/{name}").read_text(encoding="utf-8")
        for m in ("PLAN:", "NEEDS-DECISION:", "SLICE-DONE:", "SLICE-READY:", "SLICE-WAIT:", "SLICE-OPEN:", "ROUND-DONE:", "ROUND-OPEN:"): assert m in text, (name, m)
        assert "/slice" in text and "work/_slices.json" in text and "rebuild" not in text.lower()
        # The merge queue squashes in this checkout and passes the message from a file (F-08).
        assert merge_option in text and "merge --squash" in text and "commit -q -F" in text, name

def test_every_slice_runs_on_its_own_model():
    """A slice runs on the model of its "model" field in _slices.json – never on the model of the session that starts it."""
    command = (SKILL / "references/slice-command.md").read_text(encoding="utf-8")
    assert '"model"' in command and "work/_slices.json" in command
    parallel = " ".join(command.split("## 7. Parallel slices", 1)[1].split())  # the command is hard-wrapped
    assert "never the model of this session" in parallel and "claude --model" in parallel
    for name in ("slice-loop.sh", "slice-loop.ps1"):
        assert "--model" in (SKILL / f"assets/{name}").read_text(encoding="utf-8"), name
    skill = (SKILL / "SKILL.md").read_text(encoding="utf-8")
    assert "`model`" in skill and "cheapest" in skill and "claude --model" in skill
    intake = (SKILL / "references/intake.md").read_text(encoding="utf-8")
    assert "## Model per slice" in intake and "`haiku`" in intake and "`sonnet`" in intake and "`opus`" in intake
    templates = (SKILL / "references/templates.md").read_text(encoding="utf-8")
    assert '"model"' in templates
    renderer = (SKILL / "scripts/render_slices.py").read_text(encoding="utf-8")
    assert '"model"' in renderer

def test_templates_fix_the_formats():
    text = (SKILL / "references/templates.md").read_text(encoding="utf-8")
    assert "Status: open" in text and "| NN " in text and '"round"' in text and "work/conventions.md" in text

def test_no_personal_or_absolute_paths():
    for p in SKILL.rglob("*"):
        if p.is_file():
            t = p.read_text(encoding="utf-8", errors="ignore")
            assert not re.search(r"[A-Za-z]:\\Users|/home/|/Users/|@gmail", t), p

def _section(start, end=None):
    """The command text between two headings, whitespace normalised (the command is hard-wrapped)."""
    text = (SKILL / "references/slice-command.md").read_text(encoding="utf-8")
    body = text.split(start, 1)[1]
    if end: body = body.split(end, 1)[0]
    return " ".join(body.split())

def test_worktree_recipe_is_prescribed_in_section_3():
    section = _section("## 3. Plan and build the slice", "## 4. Close the slice")
    assert "git worktree add .claude/worktrees/slice-NN -b slice-NN <integration branch>" in section
    assert ".git/info/exclude" in section and "only where it follows this recipe" in section
    assert "The squash always runs in the main checkout" in section

def test_squash_checklist_runs_in_order_in_section_4():
    section = _section("## 4. Close the slice", "## 5. Close the round")
    steps = ["merge the integration branch into slice-NN", "git merge --squash slice-NN", "<<<<<<<", "every line of both sides", "Result:", "never run in one command"]
    for step in steps: assert step in section, step
    positions = [section.index(step) for step in steps]
    assert positions == sorted(positions), "the squash checklist runs out of order"

def test_red_under_load_is_load_and_pipes_hide_exit_codes():
    section = _section("## 4. Close the slice", "## 5. Close the round")
    assert "green when run alone" in section and "is load, not a regression" in section and "Surprises" in section
    assert "`| tail`" in section and "&&" in section and "exit code" in section

def test_commit_messages_are_passed_with_commit_f():
    assert "git commit -F <file>" in _section("## 3. Plan and build the slice", "## 4. Close the slice")
    section = _section("## 4. Close the slice", "## 5. Close the round")
    assert "git commit -F <file>" in section and "never inline" in section

SECTION_3 = ("## 3. Plan and build the slice", "## 4. Close the slice")
SECTION_4 = ("## 4. Close the slice", "## 5. Close the round")

def test_command_names_the_rule_terms():
    text = " ".join((SKILL / "references/slice-command.md").read_text(encoding="utf-8").split())
    assert "assumptions" in text.lower() and "recommend" in text
    for term in ("seam", "tautolog", "stop only", "two axes", "ADR"): assert term in text.lower() or term in text, term

def test_plan_rules_ask_assumptions_in_one_round_and_name_seams():
    section = _section(*SECTION_3)
    for phrase in ("one numbered round", "a recommendation", '"yes" takes', "Facts come from code and docs",
                   "only decisions are asked", "skips the round", "names the seams", "what it misses"):
        assert phrase in section, phrase

def test_test_rules_take_expected_values_from_an_independent_source():
    section = _section(*SECTION_3)
    for phrase in ("independent source", "tautolog", "checks exactly the fault or requirement", "type check",
                   "single test file", "full suite once at the end", "refactor after green"):
        assert phrase in section, phrase

def test_build_stops_only_for_a_real_blocker():
    section = _section(*SECTION_3)
    for phrase in ("Stop only for a real blocker", "missing dependency", "contradiction to the plan", "wrong assumption",
                   "style questions", "a test can settle", "subagent or inline"):
        assert phrase in section, phrase

def test_debugging_starts_from_a_red_command():
    section = _section(*SECTION_3)
    paragraph = section.split("Debugging", 1)[1]
    for phrase in ("fault red", "before any hypothesis", "three to five ranked hypotheses", "fitting seam", "missing seam is itself a finding"):
        assert phrase in paragraph, phrase

def test_review_has_two_axes_and_recheck_after_merge():
    section = _section(*SECTION_4)
    for phrase in ("two axes", "cites the plan line", "unrequested scope", "repository rule beats the general rule",
                   "run the checks again after the merge"):
        assert phrase in section, phrase
    assert section.index("merge the integration branch into slice-NN") < section.index("run the checks again after the merge") < section.index("git merge --squash slice-NN")

def test_adr_only_under_three_conditions():
    section = _section(*SECTION_4)
    for phrase in ("ADR only when", "hard to reverse", "surprise without context", "conflict of goals", "Ruling in the round record"):
        assert phrase in section, phrase

def test_command_stays_short_and_positive():
    """Slice 09 allowed 25 new lines on top of 195 and no new "never" beyond the 16 the command had.
    Slice 04 moves the line limit from 220 to 230: the full-suite lock protocol needs its own paragraph and a status line.
    1.3.0 moves it to 260: the checks proof, reserved finding ids, SLICE-WAIT, the manual-test format check and the
    open-decision scan came out of round R02 of a target repository; section 7 got shorter."""
    text = (SKILL / "references/slice-command.md").read_text(encoding="utf-8")
    assert len(text.splitlines()) <= 260, len(text.splitlines())
    assert text.lower().count("never") <= 16, text.lower().count("never")

def _skill_part(name, start, end=None):
    """A part of a skill file between two headings, whitespace normalised."""
    body = (SKILL / name).read_text(encoding="utf-8").split(start, 1)[1]
    if end: body = body.split(end, 1)[0]
    return " ".join(body.split())

def test_templates_hold_session_hints_section():
    section = _skill_part("references/templates.md", "## work/session-hints.md", "\n## ")
    assert "slice sessions" in section and "round by round" in section
    assert "open list" in section and "```" in section

def test_skill_creates_and_lists_session_hints():
    conventions = _skill_part("SKILL.md", "## 2. Conventions", "## 3. Intake")
    assert "work/session-hints.md" in conventions and "references/templates.md" in conventions and "later rounds append" in conventions
    after = _skill_part("SKILL.md", "## 6. After the round", "## Rules")
    assert "work/session-hints.md" in after.split("**Git-ignored", 1)[0], "the committed-files list names the hints"
    assert "session-hints.md" in _skill_part("SKILL.md", "## Output structure")

def test_command_reads_session_hints_and_names_it_in_parallel_prompts():
    assert "work/session-hints.md" in _section("## 2. Read first", "## 3. Plan and build")
    assert "when it exists" in _section("## 2. Read first", "## 3. Plan and build")
    assert "work/session-hints.md" in _section("## 7. Parallel slices")

def test_conventions_template_splits_the_check_scope():
    line = _skill_part("references/templates.md", "- Checks for a slice:", "\n- Full check chain")
    for phrase in ("one screen touched", "cross-page scan tests", "shared code touched", "full suite", "never two full suites at once"):
        assert phrase in line, phrase
    conventions = _skill_part("SKILL.md", "## 2. Conventions", "## 3. Intake")
    assert "one screen" in conventions and "shared code" in conventions

def test_tracked_findings_file_is_marked_by_each_slice():
    intake = _skill_part("SKILL.md", "## 3. Intake", "## 4. Slicing")
    for phrase in ("tracked findings file", "marking format", "done in slice NN", "marks nothing"):
        assert phrase in intake, phrase
    assert "marking format" in _skill_part("references/templates.md", "## Source", "## Brief")
    close = _section(*SECTION_4)
    assert "tracked findings file" in close and "done in slice NN" in close and "before the squash" in close

SECTION_1 = ("## 1. Decide what to do", "## 2. Read first")
SECTION_6 = ("## 6. Marker lines", "## 7. Parallel slices")

def test_parallel_or_auto_run_stops_before_the_squash():
    section = _section(*SECTION_4)
    for phrase in ("`auto` or `parallel`", ".slice-loop/slice-NN.msg", "git rev-parse --git-common-dir",
                   "do not merge", "Commit at ☐", "SLICE-READY: NN", "without both arguments"):
        assert phrase in section, phrase
    assert section.index("Pass the message with `git commit -F <file>`") < section.index(".slice-loop/slice-NN.msg") < section.index("6. Integrate")

def test_slice_ready_is_a_marker_with_its_meaning():
    section = _section(*SECTION_6)
    assert "SLICE-READY: NN" in section
    assert "branch committed, checklist ticked through Checks, squash message written; waits for the merge queue" in section

def test_parallel_prompts_are_short_and_name_the_queue():
    """R02: long pasted prompts duplicated conventions and hints the command reads itself."""
    section = _section("## 7. Parallel slices")
    for phrase in ('"/slice NN parallel auto"', "goal and acceptance cases", "Nothing else is pasted", "work/conventions.md",
                   "merge queue", "slice-loop --merge", "main checkout", "ends with SLICE-READY: NN"):
        assert phrase in section, phrase

def test_orchestrator_runs_cheap_and_long_runs_go_headless():
    section = _section("## 7. Parallel slices")
    for phrase in ("cheaper one", "may refuse to start sessions from background events", "`slice-loop -Parallel`"):
        assert phrase in section, phrase
    handover = _skill_part("SKILL.md", "## 5. Handover", "## 6. After the round")
    for phrase in ("-Yes -Parallel", "may refuse to start sessions from background events", "cheaper model"):
        assert phrase in handover, phrase

SECTION_5 = ("## 5. Close the round", "## 6. Marker lines")

def test_checks_proof_is_written_and_names_the_tip():
    section = _section(*SECTION_4)
    for phrase in ("Checks proof", ".slice-loop/slice-NN.checks", "`<exit code> <commit SHA> <command>`",
                   "exactly as work/conventions.md writes it", "every baseline command is listed",
                   "checks proof names the branch tip", "rewrite the checks proof with these runs"):
        assert phrase in section, phrase
    steps = ["1. Run the checks", "Checks proof", "5. Commit these edits", "checks proof names the branch tip",
             "a. merge the integration branch", "rewrite the checks proof"]
    assert [section.index(s) for s in steps] == sorted(section.index(s) for s in steps), "proof in steps 1, 5 and 6a"
    for name in ("slice-loop.sh", "slice-loop.ps1"):
        text = (SKILL / f"assets/{name}").read_text(encoding="utf-8")
        assert ".checks" in text and "Baseline check" in text and "left behind" in text, name

def test_finding_ids_come_from_a_reserved_range():
    section = _section(*SECTION_3)
    for phrase in ("reserved range", '"ids"', "New ids", "next free ones", "renumber your own new ids"):
        assert phrase in section, phrase
    assert "New ids" in _skill_part("references/templates.md", "## Slices", "## Decisions")
    assert "`ids`" in _skill_part("references/templates.md", "## work/_slices.json")
    assert "Reserve finding ids per slice" in _skill_part("references/intake.md", "## Both")
    assert "Every entry sets `ids`" in _skill_part("SKILL.md", "## 4. Slicing", "## 5. Handover")
    assert '"ids"' in (SKILL / "scripts/render_slices.py").read_text(encoding="utf-8")

def test_questions_go_under_open_decisions_and_close_scans_for_more():
    assert 'Every question for me is a "NEEDS-DECISION: <question>" line under Open decisions' in _section(*SECTION_4)
    close = _section(*SECTION_5)
    for phrase in ('"user decides"', '"<Name> entscheidet"', '"decision pending"', "outside that section"):
        assert phrase in close, phrase
    assert "user decides" in _skill_part("references/round-close.md", "## Steps", "## Manual test list")
    assert "never only a note under Deferred minors" in _skill_part("references/templates.md", "## work/rounds/", "## work/checklist.md")

def test_manual_test_blocks_have_one_format_and_close_fails_loudly():
    assert "slice-number order" in _section(*SECTION_4) and "one Expected: per step" in _section(*SECTION_4)
    close = _section(*SECTION_5)
    for phrase in ("exactly one Expected: per step", "exactly one Closes:", "is not repaired", "ROUND-OPEN: Rnn manual test list:"):
        assert phrase in close, phrase
    block = close.split("```", 2)[1]
    assert block.count("Expected:") == 2 and block.count("Closes:") == 1 and block.count("Result: ☐") == 1
    reference = _skill_part("references/round-close.md", "## Manual test list", "## Handover message")
    for phrase in ("slice-number order", "exactly one `Expected:` line after each step", "refuses to squash"):
        assert phrase in reference, phrase
    assert "not repaired silently" in _skill_part("references/round-close.md", "## Steps", "## Manual test list")

def test_new_findings_go_into_the_findings_file():
    assert "add new findings there in the file's own format" in _section(*SECTION_4)

def test_raised_test_timeouts_are_recorded_and_reviewed():
    assert "Every timeout or wait you raise in a test goes into the protocol entry" in _section(*SECTION_3)
    assert "every raised timeout or wait in a test is recorded with its reason" in _section(*SECTION_4)

def test_slice_wait_means_still_running():
    section = _section(*SECTION_6)
    assert "SLICE-WAIT: NN <what runs>" in section and "still running, not done" in section
    assert '"SLICE-WAIT: NN <what runs>"' in _section(*SECTION_4) and "not with SLICE-READY" in _section(*SECTION_4)

def test_collect_mode_writes_points_to_a_file():
    intake = _skill_part("references/intake.md", "## Collect mode", "## Both")
    for phrase in ("ich sammle", "work/_raw/intake-Rnn.md", "the moment it is named", "nothing lives only in chat", '"done" / "fertig"'):
        assert phrase in intake, phrase
    assert "Collect mode" in _skill_part("SKILL.md", "## 3. Intake", "## 4. Slicing")
    assert "## work/_raw/intake-Rnn.md" in (SKILL / "references/templates.md").read_text(encoding="utf-8")

def test_conventions_template_limits_test_workers():
    assert "Test worker limits under load" in (SKILL / "references/templates.md").read_text(encoding="utf-8")
    assert "--maxWorkers=3" in (SKILL / "references/templates.md").read_text(encoding="utf-8")

def test_status_shows_ready_to_merge():
    section = _section(*SECTION_1)
    assert "ready to merge" in section and "ticked through Checks" in section

def test_step_6a_names_slice_ready():
    section = _section(*SECTION_4)
    assert "before the squash or SLICE-READY" in section

def test_full_suite_takes_and_releases_the_lock_in_section_4():
    section = _section(*SECTION_4)
    for phrase in ("Full-suite lock", ".slice-loop/full-suite.lock", "mkdir", "New-Item -ItemType Directory", "without `-Force`",
                   "`owner`", "ISO-8601", "right after the suite", "red or green"):
        assert phrase in section, phrase
    assert "full suite" in _section("## 2. Read first", "## 3. Plan and build") and "lock" in _section("## 2. Read first", "## 3. Plan and build")

def test_held_lock_waits_and_orphaned_lock_is_reported():
    section = _section(*SECTION_4)
    for phrase in ("retry every minute", "slice-MM exists", "60 minutes", "30 minutes",
                   "SLICE-OPEN: NN lock held by slice MM since <time>", "leave it untouched"):
        assert phrase in section, phrase

def test_status_shows_the_held_lock():
    section = _section(*SECTION_1)
    assert "full-suite.lock" in section and "owner" in section

def test_conventions_template_and_skill_point_to_the_lock():
    line = _skill_part("references/templates.md", "- Checks for a slice:", "\n- Full check chain")
    assert "never two full suites at once" in line and ".slice-loop/full-suite.lock/" in line
    local = _skill_part("SKILL.md", "**Git-ignored", "- **`/slice`, later:**")
    assert ".slice-loop/full-suite.lock/" in local

def test_release_version_is_consistent():
    import json
    manifest = json.loads((ROOT / "plugins/vibe-coding/.claude-plugin/plugin.json").read_text(encoding="utf-8"))["version"]
    skill = re.search(r'^\s+version: "([^"]+)"', (SKILL / "SKILL.md").read_text(encoding="utf-8"), re.M).group(1)
    changelog = re.search(r"^## (\S+) – \d{4}-\d{2}-\d{2}", (ROOT / "plugins/vibe-coding/CHANGELOG.md").read_text(encoding="utf-8"), re.M).group(1)
    assert manifest == skill == changelog == "1.3.1", (manifest, skill, changelog)

def test_marketplace_validation_is_not_strict_but_the_plugins_are():
    """slice-board carries no version on purpose (every commit is an update), so only the marketplace check tolerates warnings."""
    workflow = (ROOT / ".github/workflows/validate.yml").read_text(encoding="utf-8")
    assert "claude plugin validate . &&" in workflow
    assert "claude plugin validate --strict plugins/vibe-rebuild" in workflow and "claude plugin validate --strict plugins/vibe-coding" in workflow
    assert "validate --strict ." not in workflow
    conventions = (ROOT / "work/conventions.md").read_text(encoding="utf-8")
    assert "validate --strict ." not in conventions and "claude plugin validate ." in conventions

def test_plugin_readme_documents_the_round_features():
    text = " ".join((ROOT / "plugins/vibe-coding/README.md").read_text(encoding="utf-8").split())
    for item in ("session-hints.md", "/slice NN parallel", "`--merge`", "`-Merge`", "SLICE-READY:", "full-suite.lock"):
        assert item in text, item

def test_root_readme_names_the_merge_queue_cases():
    text = (ROOT / "README.md").read_text(encoding="utf-8")
    loop = " ".join(text.split("**Loop test**", 1)[1].split("**Renderer test**", 1)[0].split())
    for item in ("merge queue", "--merge", "rule-based resolution"):
        assert item in loop, item
    markers = " ".join(text.split("**Markers test**", 1)[1].split("\n", 1)[0].split())
    assert "SLICE-READY:" in markers and "full-suite lock" in markers

if __name__ == "__main__":
    for name, fn in list(globals().items()):
        if name.startswith("test_"): fn(); print("ok  ", name)
