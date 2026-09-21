# Changelog

Versions follow `Major.Minor.Series.Build`. The build number rises by one for every
change that lands, so gaps between published versions are normal — not every build is
released.

## 0.5.464.31 — first public release

The first release published outside the author's own machine.

**MCP server and CLI** (`dotnet tool install -g AIContextBuilder` from nuget.org, Windows / Linux / macOS)

- A Roslyn-backed MCP server (`aicb mcp`, stdio) that answers the questions a coding
  agent has before it edits C#: callers and blast radius, implementations and
  overrides, covering tests, injected dependencies, side effects, dead code, dependency
  cycles, live compiler diagnostics — and packs task-sized context for a model.
- Serves both current MCP protocol revisions (`2026-07-28` and `2025-11-25`) from one
  binary.
- Self-init: every tool accepts the absolute `.sln` / `.slnx` / `.slnf` path as its
  session; no separate analyze step.
- A lean default tool pool across nine task facets; the full surface is one profile
  switch away (`--mcp-profile mcp-profile/full`).
- `aicb init` wires a project in one step: `.mcp.json`, the `aicb-csharp-context` agent
  skill, and — for Claude Code, Codex and OpenCode — the optional symbol guard.
- CLI verbs `init`, `analyze`, `export`, `import`, `list`, `mcp` and `call` (one tool,
  once, from a plain shell).

**Desktop app** (Windows, installer or portable ZIP from the release assets)

- Curate by hand what a model sees: pick types and methods, set a detail level per
  node, watch the token estimate, render the context document, and copy, save or send
  it to a model profile you configured (local models included).
- Workspace with solution tabs, snapshots, sessions, insights and the MCP usage view;
  light and dark theme.

**Privacy.** Analysis runs entirely on your machine. The CLI and the MCP server have
no network capability at all; the desktop app sends a document to a model only when
you press *Send to API*. No telemetry, no update check, no crash reporting.

**Known limits.** Analysis needs MSBuild (a .NET SDK or Visual Studio) on the machine.
The Windows downloads are not code-signed yet, so SmartScreen asks once. C# only;
third-party analyzers and source generators are not run.
