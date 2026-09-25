[AICB – General Documentation](README.md) &middot; chapter 1 of 12

# 1 Introduction

## 1.1 What AIContextBuilder is

AIContextBuilder (`aicb`) is a Roslyn-based tool that turns a C#/.NET solution into dense, structured Markdown for LLM consumption, and exposes the same analysis engine as an MCP server so that coding agents can navigate your code semantically instead of by text search.

Roslyn is Microsoft's .NET compiler platform — the engine behind the C# compiler and the C# language services in editors and IDEs. AICB uses it to build a symbol graph of your solution (types, members, references, inheritance, interfaces, dependency injection registrations) and to derive facts from that graph: who calls what, what a change would affect, where a method is implemented, which methods touch the file system or a database, how complex they are, which tests cover them. Those facts answer questions on their own, and they feed the Markdown context documents that AICB renders from the same analysis.

The tool prints its own one-line description:

```text
aicb - Roslyn-based .NET Markdown context generator for AI/LLM workflows. (c) Gregor Dadera - free for individuals and small organizations; see LICENSE.txt for the thresholds.
```

AICB is not an IDE, a build tool or a refactoring tool. It reads your solution and reports on it; it does not compile or run your code. The one exception is the desktop app's Details tab, which can edit and save a source file — everywhere else, AICB only tells you things.

## 1.2 The problem it solves

`grep` finds substrings. It does not know what a symbol is. A search for a type name returns every line that happens to contain that text, and it misses the places where the compiler — not the text — creates the reference. Before an edit, an agent (or you) needs different answers: who calls this, how far does a change reach, where is this implemented, what does this method touch, and how much context does this task need.

AICB answers those questions from the symbol graph. The difference is not cosmetic: in the current measurement, a search that returns 153 line positions where 40 consumer types are meant is harder for a model to use than the aggregated answer, and a reference that exists only in the compiler's view is invisible to a text search entirely. The sections "How AICB differs from text search" and "How AICB differs from a language server" below spell this out with the measured numbers.

One convenience is worth knowing from the start: every tool that takes a session also accepts the absolute path to a `.sln`, `.slnx` or `.slnf` file directly and analyzes it on first use. There is no separate preparation step between you and an answer.

## 1.3 Who it is for

Three groups of users are visible in the product today, in the order in which it serves them:

1. **Developers who drive a coding agent on a C#/.NET solution** (Claude Code, Cursor, Cline, Codex, OpenCode). This is the primary audience: `aicb init` and `aicb mcp` exist for it, and the agent skill that `aicb init` installs teaches an agent when to reach for which tool — and when plain `grep` is still the right choice.
2. **Developers at the shell**, who ask a single semantic question with `aicb call` or generate a context document with `aicb analyze` and paste it into a chat.
3. **Desktop app users**, who curate what goes into an exported context document — run templates, detail presets, Markdown profiles, quality profiles — and configure how a solution is analyzed: namespace exclusions, test detection, layer mapping, and the MCP profiles a client sees.

A related group gets the quality and architecture half: `solution_metrics` with a gate expression (`aicb analyze --fail-on`), layer profiles with violation checks, cycle detection, a technical-debt estimate and `list_insights` are useful to whoever owns code quality. Note that there is no team feature behind them — no shared server and no multi-user state; see "What AICB does not do" below.

### License

AICB is closed source. The license is free of charge for natural persons (private, hobby and educational use), for accredited educational institutions (teaching, learning and non-commercial research), and for organizations that reach none of three thresholds:

- 100 employees,
- EUR 10 million annual turnover,
- 21 developers.

A subsidiary counts together with its group, and the thresholds measure your organization only — the size of your clients does not matter, including when you work on their premises. Once your organization reaches or exceeds one of the thresholds, a commercial license is required before further use; you have 90 days from first reaching a threshold to arrange it, and use stays free of charge until then. Terms are agreed individually.

Redistribution, modification, repackaging and competing products are not permitted. The software contains no license server and no activation token; compliance is your own responsibility. `LICENSE.txt` ships with the product and carries the summary; the full bilingual End-User License Agreement (EULA) is published as `EULA.md` in the public repository github.com/gregordadera/AICB. The chapter "License, installation and updates" has the details.

## 1.4 The three faces

AICB has three faces, and they are not three independent programs: all three run the same Roslyn analysis and the same rendering engine.

| Face | What it is | Where it runs |
|---|---|---|
| The desktop app | The graphical curation and configuration surface — and the only face that can edit a source file | Windows only |
| The command line (`aicb`) | Seven verbs for analysis, export, import, listing, wiring and the MCP server | Windows, Linux, macOS |
| The MCP server (`aicb mcp`) | A stdio JSON-RPC server that offers the semantic tools to a coding agent | Windows, Linux, macOS |

The MCP server and the CLI install from nuget.org; the desktop app downloads from GitHub Releases as a Windows installer or a portable ZIP.

### The desktop app

The desktop app is where you load a solution, browse it in a tree, and read the context document AICB renders from it. It is also where the master data lives: run templates, detail presets, Markdown profiles, quality profiles and MCP profiles are managed here, together with the settings that decide how a solution is analyzed. It is the only face that can edit a source file — the Details tab opens a file in a real editor and writes it back with Save or `Ctrl+S`, keeping its original encoding and line endings; a file that is missing or fails to load stays read-only. The desktop app can also send a rendered context to an LLM endpoint you configure — that is what its "Send to API" button does, and the endpoint may be a local model.

![The desktop app with a solution loaded: the solution tree on the left, the generated context document on the right](img/aicb-main.png)

### The command line

`aicb` is a .NET global tool for Windows, Linux and macOS:

```sh
dotnet tool install -g AIContextBuilder
```

It has seven verbs:

| Verb | What it does |
|---|---|
| `aicb init` | Wires AICB into this project for an MCP client: adds the `aicb` entry to `.mcp.json`, writes the agent skill to `.claude/skills/`, and installs the symbol guard for the agent harnesses the project uses. Existing files are kept unless you pass `--force`. |
| `aicb analyze` | Runs Roslyn analysis on a solution and emits context Markdown. |
| `aicb export` | Re-renders Markdown from an existing session database, without a Roslyn re-run. |
| `aicb import` | Imports a constellation JSON into a target database (templates, presets, constellations). |
| `aicb list` | Lists built-in and custom master entities; `run-templates`, `detail-presets` and `model-profiles` are three of fourteen kinds. |
| `aicb mcp` | Starts the MCP server (stdio JSON-RPC) for Claude Code, Cursor, Cline and other MCP clients. |
| `aicb call` | Invokes one MCP tool once and prints its result — no server, no client needed. |

Run `aicb <command> --help` for the options of a verb.

### The MCP server

`aicb mcp` starts an MCP (Model Context Protocol) server over stdio JSON-RPC. It is a verb of the same `aicb` command, not a separate program: installing the CLI installs the server.

By default the server exposes a lean pool of 54 tools covering all nine task facets — General, Exploration, Refactoring, Debugging, Review, Testing, Documentation, Architecture and Performance. The unnarrowed pool of 72 tools is one profile switch away: `--mcp-profile mcp-profile/full` at the command line, or the "Full Select" profile in the desktop app. The environment variable `AICB_MCP_TOOLS` is an operator override; `AICB_MCP_TOOLS=all` exposes every tool the assembly registers, including the opt-in infrastructure tools. One binary serves both current MCP protocol revisions over stdio — the `2025-11-25` handshake and the `2026-07-28` stateless entry point — so clients on either revision connect.

Most tools need an analyzed solution. Every tool that takes a session also accepts the absolute path to a `.sln`, `.slnx` or `.slnf` file directly and analyzes it on first use, so a client can start asking without a preparation step.

With `--db-path` the server reads the per-solution configuration and the active MCP profile from the configuration database you name; `--mcp-profile <id>` pins the profile for this server process only, without writing anything back. Without `--db-path` it resolves the standard configuration database — the same one the desktop app uses.

### How the three relate

- **One engine.** The desktop app, the command line and the MCP server share the same Roslyn analysis and the same render path. A run template you create in the desktop app can drive a headless export with `aicb analyze --run-template` or `aicb export --run-template`.
- **The MCP server is a verb of the CLI.** There is no separate server executable, and no separate server installation.
- **The desktop app and the MCP server share one configuration database by default** — on Windows `%APPDATA%\AIContextBuilder\user-data\aicb.acb`, elsewhere under the platform's application-data folder. MCP profiles, per-solution namespace exclusions, the test-detection profile and the layer profile are edited in the desktop app and read by the server. The sharing is per machine, not per team.
- **`aicb init` wires a project for a client.** It adds the `aicb` entry to `.mcp.json`, writes the agent skill to `.claude/skills/`, and installs the symbol guard into the agent harness the project uses. It never overwrites an existing file unless you pass `--force`, so re-running is safe; `aicb init --hooks none` installs no guard, and `--hooks` also accepts `auto` (the default), `all`, or one of `claude-code`, `codex` and `opencode`. The guard is not a hint: it refuses a C# symbol search aimed at a type or member name and points at the AICB tool that answers it. Two limits are worth knowing: the agent skill is written to `.claude/skills/` only, and OpenCode discovers MCP servers only through its own `opencode.json`, so an OpenCode user adds the entry there by hand. `aicb init` names both gaps in its output.
- **`aicb call` invokes exactly one MCP tool** — in-process, without a server or a client — and prints the result. It applies no profile filter: it can reach any registered tool, including tools outside the active pool and tools that write configuration. Use it deliberately.

## 1.5 How AICB differs from text search

Both `grep` and AICB can tell you that a name occurs. The difference is what each one understands by "occurs". Three examples show where the symbol graph sees what a text search cannot:

- **Compiler semantics beyond tokens.** In four test classes, the interface names `ICodeAnalyzer` and `IFileSetHasher` appear nowhere as text: the binding is created by an implicit reference conversion at the argument position of a method call. A text search finds zero occurrences of the names; AICB reports the four classes as consumers, because the compiler does.
- **Markup.** In a WPF application, XAML references such as `{x:Type ...}` and `{x:Static ...}` create dependencies that a text search sees only as text and a Roslyn-only tool does not see at all. In AICB's differential benchmark, four of the twenty cases where AICB found a dependency and the language server did not came from markup.
- **Questions a text search cannot formulate.** The transitive fan-in closure; the split between production and test consumers (`productionImpactCount`); classes of side effects (I/O, network, database, serialization, logging, cache, messaging); namespace dependency cycles; dependency injection registrations; complexity and coupling metrics.

Where text search stays the right tool: string literals, comments, log messages, config keys, version strings, and files that are not C# — `.json`, `.csproj`, `.md`. AICB routes those questions to text search rather than guessing from the symbol graph.

## 1.6 How AICB differs from a language server

The strongest alternative to AICB is not `grep` but a language server — in this comparison, the Roslyn language server, which has been available inside agents such as Claude Code since December 2025 and ships free. AICB's differential benchmark was run against exactly that alternative, on AICB's own solution (13 projects, about 200,000 lines of C#), with a deliberately chosen sample of twelve symbols. It is a structural comparison, not a general benchmark of answer quality — and it is explicit about where the language server wins.

**What a language server does better:**

- Point questions — "where is X defined", "who calls X" — are built into the agent, free, and answer the common case.
- It sees unsaved editor buffers; AICB reads from disk.
- It returns navigable positions; AICB's answers are mostly symbol-level.
- It does real fuzzy matching; `find_symbol` matches case-insensitively by substring.
- It reports analyzer diagnostics; AICB reports compiler diagnostics only.
- It is incremental; AICB needs `refresh_session` after an edit.

**What a language server structurally cannot do:**

- Transitive closure — it reports one level; AICB reports the closure.
- Test/production separation — for the protocol, a reference is a reference.
- A risk judgment for a change.
- Test coverage — it has no concept of a test.
- Code metrics — complexity, coupling, lines of code.
- XAML.
- State an honest negative: an empty answer from a language server is indistinguishable from the client having forgotten to ask; AICB's tools write their negatives into the answer, for example `implementations: (none)`.

The single number that shows the difference, measured against AICB 0.5.464.33: for the enum `RunType`, AICB reports **40 direct consumers and 1,064 transitive ones**, 516 of them in production code; the language server reports individual reference positions instead of the aggregated consumer graph.

Aggregation is the other half of it. Re-running the AICB side against 0.5.464.33 while retaining the benchmark's language-server payload, `find_usages` answered with 1,079 bytes covering 40 types, where the reference list answered with 41,237 bytes covering 153 positions — about **38 times more compact**. The two answers serve different purposes: an editor needs positions to click through, while a language model benefits from aggregation by consumer type.

## 1.7 What AICB does not do

AICB is deliberately narrow. Knowing the limits saves time:

| Limit | What it means |
|---|---|
| C#/.NET only | Roslyn is the foundation. C# and .NET projects are understood; XAML/AXAML markup is read for bindings and resources. Other languages are out of scope. |
| Windows-only desktop app | The `aicb` command line and the MCP server run on Windows, Linux and macOS. The desktop app runs on Windows only. |
| stdio only | The MCP server speaks stdio JSON-RPC. There is no HTTP/SSE transport. |
| No multi-user state | The configuration database is a local SQLite file on your machine. Apart from client-wiring files created by `aicb init` (such as `.mcp.json` and agent-specific hook or settings files), the only AICB analysis/configuration artifact intended to travel with your repository is the git-tracked `<Solution>.aicb.json` sidecar next to the `.sln`; it carries configuration, not results. |
| No live editor buffer | AICB analyzes the files on disk. Unsaved changes in your editor are invisible until you save; a session that has already analyzed a solution re-reads it with `refresh_session`. |
| Compiler diagnostics only | `get_diagnostics` reports compiler errors and warnings. It does not run your third-party analyzers or source generators, so "0 errors" is not the same as "clean in the sense of your IDE". |
| Symbol-level answers | Most tools name the declaring type and member rather than a file-and-line position you can click. For position-level navigation, use your IDE or a language server. |
| No fuzzy search | `find_symbol` matches case-insensitively by substring. A typo returns no hits; a `nearest` suggestion names the closest declared symbol. |
| Diagnostics are not cached | `get_diagnostics` compiles on every call. Its `scope` parameter makes the answer smaller, not the work. |
| No outbound network | The CLI and the MCP server have no outbound network capability at all. The desktop app can send a rendered context to an LLM endpoint you configure, and only when you press "Send to API". |
| A local call log | The MCP server records the tool calls it handles in your configuration database — that is what `usage_report` and the desktop app's usage panel read. The log stays on your machine and nothing is transmitted. |

Note: opening a solution runs its MSBuild build logic to resolve references — exactly as Visual Studio or `dotnet build` does. Analyze only solutions you trust.

## 1.8 How this manual is organized

This manual is the General volume. It covers the product itself, the `aicb` command line, and the configuration that all three faces share. Two companion volumes go deeper: "MCP server" documents the tools, profiles and session model that an agent sees, and "Desktop app" documents the desktop application's windows, panels and settings. Where a topic belongs to one of those volumes, this manual refers to it by title instead of repeating it.

---

[Contents](README.md) &middot; [2 License, installation and updates &rarr;](02-license-installation-and-updates.md)
