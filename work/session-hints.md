# Hints for slice sessions

Repository-specific experience for the sessions that work a slice. They add to `.claude/commands/slice.md` and `work/conventions.md`; every round appends what it learned. The slice-board pane attaches this file to the request that starts a slice session.

- Worktree: `git worktree add .claude/worktrees/slice-NN -b slice-NN plugin-vibe-coding`, then work inside that folder; `.claude/worktrees/` belongs in `.git/info/exclude`. The squash merge runs in the main checkout, never in the worktree.
- A control hook asks for facts before the first edit of each file and before the first shell command of a session: state the request in one sentence and what the command or write does, then repeat the same call once.
- Git Bash rewrites an argument that starts with `/` into a Windows path (`/slice …` becomes a path under the Git installation): set `MSYS_NO_PATHCONV=1` for such calls and pass commit messages with `git commit -F <file>`, never inline.
- Inside bash heredocs `\n` becomes a line break and `\\` a single backslash: write scripts and long files with the file-writing tool, not with heredocs; Python one-liners with backslashes break the same way.
- The file-writing tool writes CRLF on Windows. `.gitattributes` normalises to LF on commit, but tests and `grep` read the working copy: convert new files to LF before running the tests (for example `python -c` with `newline="\n"`).
- Use `python` (3.13 here), not `python3`, which is only a Store stub. The loop test needs `bash` and `pwsh` on PATH and takes about a minute; run it in the background with a log in the session's scratch folder and read the exit code from the log, never through a pipe.
- Everything is English, including round files, test names and commit texts. No absolute paths, user or machine names, personal names or private mail addresses in any file; `tests/markers_test.py` scans the skill folder – check `work/` and `tests/` with the same regex before a commit.
- The `/slice` command and both loop scripts are a contract read by `tests/markers_test.py` and `tests/loop_test.py`: change the test first (red), then the command or script.
- Both loop scripts stay functionally identical: a change to `slice-loop.sh` is mirrored in `slice-loop.ps1` in the same slice, and `tests/loop_test.py` runs both shells.
- Never touch `plugins/vibe-rebuild/` or `rebuild-loop.*` from a vibe-coding slice. Never push; `main` is the release branch.
