# Privacy Policy – vibe-rebuild

_Last updated: 2026-10-24_

vibe-rebuild is a skill (instructions, templates and two local helper scripts). It runs entirely inside your Claude session.

- **No data collection.** The plugin does not collect, store, transmit or sell any personal data or usage data.
- **No network access of its own.** The plugin contains no servers, MCP connectors, telemetry or analytics. Its scripts (`inventory.py`, `render_slices.py`) only read the folders you point them at and write files locally.
- **Your code stays where it is.** The skill reads the repository you name and writes the plan into a separate plan repository: the plan documents in its `rebuild/` folder, plus `CLAUDE.md`, `README.md`, `.gitignore`, `.gitattributes` and the `/rebuild` command and loop scripts under `.claude/`. What Claude does with that content is governed by your agreement with Anthropic and your Claude settings, not by this plugin.
- **Web research uses Claude's own tools.** The target-stack research step asks Claude to use whatever web search your session already provides. The skill instructs that search queries contain only generic technology terms – never code, internal names, customer data or secrets from your repository.
- **No credentials.** The plugin never reads, asks for or stores passwords, tokens or API keys.

Questions: open an issue at https://github.com/vompa/vibe-coding/issues.
