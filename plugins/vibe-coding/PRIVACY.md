# Privacy Policy – vibe-coding

_Last updated: 2026-10-24_

vibe-coding is a skill (instructions, templates, the text of the `/slice` command and local helper scripts: `render_slices.py` and the `slice-loop` scripts). It runs entirely inside your Claude session; the hands-off loop additionally starts the `claude` CLI on your machine.

- **No data collection.** The plugin does not collect, store, transmit or sell any personal data or usage data.
- **No network access of its own.** The plugin contains no servers, MCP connectors, telemetry or analytics. Its scripts only read the files in the repository you name and write files locally. `slice-loop.ps1` and `slice-loop.sh` start the local `claude` CLI, which talks to Anthropic under your own agreement and settings, and never push.
- **Your code stays where it is.** The skill reads the repository you name and changes no product code. What Claude does with the content it reads is governed by your agreement with Anthropic and your Claude settings, not by this plugin. The skill writes planning and handover files into that repository:
  - Committed in one round-start commit on the repository's integration branch: the `work/` folder (without `work/_raw/`), `.claude/commands/slice.md`, `.claude/scripts/slice-loop.ps1` and `.claude/scripts/slice-loop.sh`, `.gitignore` and `.gitattributes` (missing lines appended, no existing line changed), and `CLAUDE.md` only where the repository has none.
  - Local, never committed: `work/_raw/` (working material), `.slice-loop/` (loop logs; the loop scripts append it to `.git/info/exclude` when it is missing there) and a repository-local git identity (`git config --local`), set only with your approval. The global git configuration is never changed.
  - Later, when you run `/slice` or the loop: a branch and worktree `slice-NN` while a slice is built, then one squash commit per slice on the integration branch (this is where product code changes, one slice at a time). The commit carries the plan `work/plans/<date>-slice-NN.md`, the checklist tick, the entries in the round record, the repository's own protocol entry if `work/conventions.md` names one, and the documents it lists as "must change with a change". In auto mode (the loop) `/slice` removes the merged `slice-NN` branch and its own worktree after the squash merge, nothing else. `/slice close` commits the closed round record. Nothing is ever pushed.
- **Research only for new technology.** The skill does no web research by default. Only when a round's brief brings technology or packages the repository does not use yet, it asks Claude to use whatever web search your session already provides. The skill instructs that search queries contain only generic technology terms – never code, internal names, customer data or secrets from your repository. Without web access it writes from model knowledge and marks the findings as unverified.
- **No credentials.** The plugin never reads, asks for or stores passwords, tokens or API keys.

Questions: open an issue at https://github.com/vompa/vibe-coding/issues.
