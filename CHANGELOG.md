# Changelog

Versions follow `Major.Minor.Series.Build`. The build number rises by one for every
change that lands, so gaps between published versions are normal — not every build is
released.

## 0.5.464.35 — two answers about C# code that were quietly wrong

Analysis-engine changes, so they reach the MCP server, the CLI and the desktop app alike.

- **`resolve_injection` discloses optional constructor dependencies.** A constructor
  parameter with a default (`IFoo? foo = null`) that nothing in the registration set fills
  used to fall between two answers — the tool listed what was registered, never whether it
  arrived. The answer now carries an `optionalDependencies` axis naming every such consumer,
  with a verdict of `yes`, `no` or `unknown` per construction. The verdict follows **who
  selects the constructor**: the container when the consumer is registered by type, the
  argument list when a factory lambda or a hand-built instance constructs it. Where the
  analyzer cannot see how the consumer is built — construction inside a helper method,
  `ActivatorUtilities`, several constructors to choose between, two types of the same short
  name — it answers `unknown` with a reason rather than a plausible guess. Answers for
  services with no optional consumer are byte-identical to before.
- **A static constructor no longer shares its caller entry with the parameterless one.**
  `static C()` and `C()` were registered under one key, so `find_usages` merged the callers
  of the two bodies and could not tell which one called what. The static constructor now
  keys as `C.static C()`, in `find_usages`, `call_graph`, `impact_of_change` and the
  exported Markdown.
- **Saved snapshots:** the payload format moves to 56, so a snapshot written by an older
  version is re-analyzed instead of loaded. Nothing is lost; the first analysis after the
  update takes its usual time.
- The desktop app is otherwise unchanged since 0.5.464.32.

## 0.5.464.33 — manuals linked from the package page

- Full manuals as PDF (General, MCP server, Desktop app) in
  [`docs/manual/`](https://github.com/gregordadera/AICB/tree/main/docs/manual), linked from the
  README and therefore from the nuget.org package page.
- No code change: the MCP server and CLI behave exactly like 0.5.464.32. Published on
  nuget.org only; the desktop app stays at 0.5.464.32.

## 0.5.464.32 — one installation per machine

- **The installer removes an existing .NET tool** (option, preselected). The installer
  contains the same MCP server and CLI; with both installed, Windows starts the
  installer's `aicb` first, so `dotnet tool update` updated a copy no MCP client ran.
  Now one `aicb` per machine, and a desktop-app update brings the MCP server along. If
  the tool is still running as an agent's MCP server, the installer asks you to close
  the agent and retry.
- **`aicb init` warns when `aicb` is installed more than once** and names the copy that
  actually runs.
- The installer's last page says that consoles, editors and agents that were already
  open see the new `PATH` only after a restart.
- Published builds report a plain version number (`0.5.464.32`) without a build commit
  suffix.
- Install guidance in README, Getting started and the `aicb-csharp-context` skill:
  Windows with the desktop app → installer only; everywhere else → the .NET tool.

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
