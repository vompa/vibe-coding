# Privacy Policy – vibe-coding

_Last updated: 2026-10-24_

vibe-coding is a skill (instructions, templates and local helper scripts: `render_slices.py` and the `slice-loop` scripts). It runs entirely inside your Claude session.

- **No data collection.** The plugin does not collect, store, transmit or sell any personal data or usage data.
- **No network access of its own.** The plugin contains no servers, MCP connectors, telemetry or analytics. Its scripts (`render_slices.py`, `slice-loop.ps1`, `slice-loop.sh`) only read the files in the repository you name and write files locally; the slice loop starts the `claude` CLI on your machine and never pushes.
- **Your code stays where it is.** The skill reads the repository you name and writes a `work/` folder and `.claude/` files (the `/slice` command and the loop scripts) into that repository. What Claude does with that content is governed by your agreement with Anthropic and your Claude settings, not by this plugin.
- **No research step of its own.** The skill does no web research by default. Only if a round involves new technology, it asks Claude to use whatever web search your session already provides, with queries that contain only generic technology terms – never code, internal names, customer data or secrets from your repository.
- **No credentials.** The plugin never reads, asks for or stores passwords, tokens or API keys.

Questions: open an issue at https://github.com/vompa/vibe-coding/issues.
