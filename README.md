# AIContextBuilder (`aicb`)

<!-- mcp-name: io.github.gregordadera/aicb -->

[![NuGet Version](https://img.shields.io/nuget/v/AIContextBuilder)](https://www.nuget.org/packages/AIContextBuilder)
[![NuGet Downloads](https://img.shields.io/nuget/dt/AIContextBuilder)](https://www.nuget.org/packages/AIContextBuilder)
[![MCP Registry](https://img.shields.io/badge/MCP%20Registry-listed-1584ad)](https://registry.modelcontextprotocol.io/v0.1/servers?search=io.github.gregordadera%2Faicb)
[![License](https://img.shields.io/badge/license-custom%20EULA-lightgrey)](https://github.com/gregordadera/AICB/blob/main/EULA.md)
[![M8ven Verified](https://img.shields.io/badge/M8ven%20Verified-publisher%20verified-4c1)](https://m8ven.ai/mcp/gregordadera-aicb-zb5d9e)

**Give coding agents a Roslyn-accurate map of your C#/.NET solution.** `aicb`
answers questions about callers, implementations, dependency injection, tests,
side effects and change impact, then packs the relevant code into compact
Markdown for an LLM. It runs locally as an MCP server and CLI; a Windows desktop
app adds visual context selection, analysis and editing.

> The software is closed source. This public repository contains its
> documentation, licence and releases. It is free for individuals, education and
> organizations below the [licence thresholds](#licence-at-a-glance).

## See it answer a code question

Ask your coding agent:

> What could be affected if I change `ColorMixerService`? Use AICB.

Or call the same tool from a terminal:

```sh
aicb call impact_of_change --sln C:/repo/App.sln --arg symbol=ColorMixerService
```

Abridged output from the bundled `ColorMixer.SelectionLab` sample:

```json
{
  "symbol": "ColorMixerService",
  "resolvedKind": "type",
  "directCount": 1,
  "transitiveCount": 2,
  "risk": "low",
  "productionImpactCount": 2,
  "directImpact": { "items": ["DemoCompositionRoot"] }
}
```

The desktop app's **MCP Usage** page records calls locally and separates guided
refusals from suspected defects:

[![AICB MCP Usage statistics showing calls, sessions, latency and the most-used tools](https://raw.githubusercontent.com/gregordadera/AICB/main/docs/assets/aicb-mcp-usage.png)](https://www.dadera.de/en/aicb-mcp.html)

That answer comes from the Roslyn symbol graph, not a substring search. AICB
distinguishes overloads, follows interface and override relationships, understands
partial types and records DI construction paths.

## Build context that fits the task

AICB does more than answer individual symbol questions. It can assemble a focused,
task-specific context package for an agent instead of sending an unfiltered source
dump:

| Need | Tool | What it returns |
|---|---|---|
| Read one symbol in context | `get_context` | The symbol plus its direct dependencies and callees |
| Explore a named symbol with selected surroundings | `explain_symbol` | Callers, callees, implementations, tests or other requested dimensions |
| Pack context for a natural-language goal | `pack_for_task` | Goal-named symbols and their semantic neighbourhood |
| Prepare to edit | `prepare_task` | The goal-focused context plus covering tests and likely siblings such as a factory or validator |
| Check the response cost first | `measure` | The exact token count of one or more planned tool answers, without returning their large payloads |

The focused context tools accept a **token budget**. Explicitly named seed symbols
stay in the package; AICB first reduces method detail and then removes less-relevant
surrounding content when the budget is tight. It does not cut text in the middle of
a block, and a leading note discloses types, tests or siblings that were omitted.
Whole-document rendering can use the same budget pipeline through a pipeline profile,
including a configurable overshoot allowance and an optional trimming report.

The result is **AI-Builder-MD**: structured Markdown for an LLM, containing the
selected code together with symbol relationships, architecture graphs, semantic
metadata and provenance. It can use the established tag notation or YAML. See the
[context-document guide](https://github.com/gregordadera/AICB/blob/main/docs/manual/general/05-the-context-document-ai-builder-md.md)
and the [task-packing tools](https://github.com/gregordadera/AICB/blob/main/docs/manual/mcp/09-tool-reference-markup-export-review-and-insights.md#92-packing-and-exporting-context).

### Add explicit meaning with AI annotations

AICB works without annotations. Where source structure and conventions are not
enough, optional `<ai>` tags in XML documentation let a developer state the intended
role of a type or method explicitly:

```csharp
/// <ai
///   role="service"
///   layer="Application"
///   responsibility="Coordinates order validation and submission."
///   stability="Stable"
/// />
public sealed class OrderService
```

Annotations can describe semantics such as role, domain, architectural layer,
priority, stability, responsibility and side effects. Explicit values take
precedence over heuristic inference; sentinel values such as `none` can deliberately
suppress inference for one field. AICB preserves provenance so an agent can
distinguish source-derived facts, author-provided meaning and inferred hints. The
[AI annotation reference](https://github.com/gregordadera/AICB/blob/main/docs/manual/general/03-core-concepts.md#39-the-ai-annotation)
documents the supported forms and fields.

[![AIContextBuilder desktop app with a loaded solution](https://raw.githubusercontent.com/gregordadera/AICB/main/docs/assets/aicb-main-light.png)](https://www.dadera.de/en/aicb-gui.html)

## How analysis and memory work

```text
.sln / .slnx / .slnf + C# + XAML/AXAML
                 ↓
        MSBuild + Roslyn semantic models
                 ↓
  AICB facts and consolidated semantic indexes
                 ↓
 individual answers or budgeted AI-Builder-MD
```

AICB is more than a response cache around Roslyn. During analysis it walks the
solution's C# documents, records declarations, calls, type references and other
facts, then consolidates caller and type fan-in, implementations, resolved markup
references and transitive side-effect classifications. Tools traverse or project
that warm model for a particular question; context tools select and render a
task-specific slice. This does **not** mean that every possible answer or runtime
relationship is precomputed.

An MCP session belongs to one `aicb mcp` process and pins both the analyzed graph
and its Roslyn workspace. A second server process builds its own session. The
desktop app, CLI and MCP server use the same analysis and rendering engine and can
share configuration and persisted snapshots through the local database, but they
do not share one live in-memory graph. Within one session, only one refresh runs at
a time; concurrent callers join it. A source-only edit can take the incremental
path, replaying changed document text without reloading the workspace. When that
path is unavailable, or when `force: true` is requested, AICB fully reloads it.

### What the model can and cannot prove

- AICB analyzes statically visible C# and selected XAML/AXAML relationships. Code
  reached only through reflection, runtime assembly scanning, dynamic configuration
  or an external consumer can remain invisible.
- DI analysis recognizes statically readable Microsoft-DI-shaped registrations;
  runtime-produced registrations are disclosed as dynamic or unknown rather than
  invented.
- XAML binding analysis resolves paths only where the source and data type are safe
  to establish. Unknown scopes are skipped conservatively.
- A reported side effect is a conservative static contact classification propagated
  through known call edges. It is not general data-flow, taint or runtime state
  analysis.
- Responses disclose stale sessions, unresolved projects and capped result sets.
  Read `staleness`, `incompleteProjects`, `totalFound` and `truncated` before treating
  an empty or short answer as proof.

The question-first [architecture, limits and evidence guide](https://github.com/gregordadera/AICB/blob/main/docs/ARCHITECTURE.md)
explains what lives in memory, how refresh and context selection work, which claims
are measured, and which benchmarks have not yet been published.

## Where it helps

| Question | Tool |
|---|---|
| Who calls or uses this? | `find_usages` |
| What is the blast radius of a change? | `impact_of_change` |
| Where is this interface implemented or overridden? | `find_implementations`, `find_overrides` |
| Which tests exercise this symbol? | `find_tests_for` |
| What gets injected here? | `resolve_injection` |
| Which code has side effects or calls an external API? | `find_by_side_effects`, `calls_external` |
| What context does an agent need for this task? | `explain_symbol`, `prepare_task`, `pack_for_task` |
| How large would these answers be before I pull them? | `measure` |
| Where is this property or resource used in XAML/AXAML? | `find_binding_usages`, `find_resource_usages` |
| Which markup bindings cannot be resolved safely? | `find_unresolved_bindings` |
| What changed between two analyzed states? | `semantic_diff`, `diff_review` |
| Does this change set violate a policy or public contract? | `evaluate_change_set`, `compare_public_api` |

The desktop app turns code-quality, security, design and architecture findings
into an actionable review queue:

[![AICB Insights page with prioritized code-quality, security, design and architecture findings](https://raw.githubusercontent.com/gregordadera/AICB/main/docs/assets/aicb-gui-insights.png)](https://www.dadera.de/en/aicb-gui.html)

AICB is most useful for non-trivial C#/.NET solutions and semantic questions that
plain text search cannot answer reliably. It is not a general-purpose code search
tool and does not analyze non-.NET projects. The first question opens and analyzes
the solution, which can take seconds to minutes; later questions reuse the warm
session.

## Install

Install **one** form per machine:

| You want | Install | Platform |
|---|---|---|
| MCP server and CLI | [.NET global tool](https://www.nuget.org/packages/AIContextBuilder) | Windows, Linux, macOS |
| Desktop app plus the same MCP server and CLI | [Windows installer or portable ZIP](https://github.com/gregordadera/AICB/releases/latest) | Windows |

The .NET tool needs the **.NET 8 SDK**:

```sh
dotnet tool install -g AIContextBuilder
aicb --version
```

Update it later with `dotnet tool update -g AIContextBuilder`.

The Windows downloads are self-contained, but analyzing a solution still needs
MSBuild from a .NET SDK or Visual Studio. The installer is not code-signed yet, so
Windows SmartScreen displays a warning; every release provides SHA-256 checksums.

## Connect a coding agent

Run this from the project you want the agent to work on:

```sh
aicb init
```

It writes the MCP configuration and the `aicb-csharp-context` agent skill without
overwriting existing files. If it detects Claude Code, Codex or OpenCode project
configuration, it also installs a **symbol guard** that blocks C# symbol searches
by grep and redirects the agent to the semantic tool. This intentionally changes
agent behaviour. Opt out with:

```sh
aicb init --hooks none
```

Client-specific status:

| Client | MCP setup | Skill and guard |
|---|---|---|
| Claude Code | `.mcp.json` written by `aicb init` | Skill and optional guard installed |
| Codex | Add `aicb mcp` through the client's MCP configuration | Optional guard supported; skill location is not guessed |
| OpenCode | Add `aicb mcp` to `opencode.json` | Optional guard supported; skill location is not guessed |
| Cursor / Cline / other stdio clients | Add command `aicb` with argument `mcp` | Use the published skill if the client supports Agent Skills |

Manual `.mcp.json` configuration for clients that read it:

```json
{
  "mcpServers": {
    "aicb": {
      "command": "aicb",
      "args": ["mcp"]
    }
  }
}
```

Verify the connection by asking the client to call `server_info`. Every analysis
tool accepts an absolute `.sln`, `.slnx` or `.slnf` path as its session, so no
separate analyze step is required. See the [five-minute guide](https://github.com/gregordadera/AICB/blob/main/docs/GETTING-STARTED.md)
for setup, first questions and troubleshooting.

## Tool sets and Agent Skills

| Set | Size | Purpose |
|---|---:|---|
| Default MCP profile | 54 tools | Curated semantic and structural tools for normal agent work |
| Full analysis profile | 72 tools | Default set plus the measured long tail |
| Complete server surface | 82 tools | Full profile plus opt-in infrastructure tools |

Start the full analysis profile with
`aicb mcp --mcp-profile mcp-profile/full`. Set `AICB_MCP_TOOLS=all` to add
the infrastructure tools. The generated [tool reference](https://github.com/gregordadera/AICB/blob/main/docs/TOOLS.md) documents
the default set; the [MCP server manual](https://github.com/gregordadera/AICB/blob/main/docs/manual/mcp/README.md)
documents all 82 tools and their parameters, and alongside them sessions and
staleness, profiles, pools and facets, and what `aicb init` writes — twelve
chapters in Markdown, readable in the browser and by an agent, and also
published as a [PDF](https://github.com/gregordadera/AICB/blob/main/docs/manual/mcp/AICB-MCP-Server.pdf).

Four Agent Skills ship in [`skills/`](https://github.com/gregordadera/AICB/tree/main/skills):

- `aicb-csharp-context` routes semantic C# questions to the right tool.
- `aicb-code-review` checks a completed change for correctness.
- `aicb-code-simplifier` looks for unnecessary complexity.
- `aicb-usage-check` reports what this server was actually reached for.

The last three are opt-in: `aicb init --skills=all`.

## CLI at a glance

```text
aicb init      Connect a project to the MCP server and install the agent skill.
aicb analyze   Analyze a solution and emit context Markdown.
aicb export    Re-render Markdown from an existing session database.
aicb import    Import a constellation JSON.
aicb list      List built-in and custom profiles and presets.
aicb mcp       Start the stdio MCP server.
aicb call      Invoke one MCP tool without an MCP client.
```

Run `aicb <command> --help` for options.

## Local by default

- The CLI and MCP server have no outbound network capability and do not modify
  the source code they analyze.
- There is no telemetry, analytics, update check, account or licence server.
- The desktop app sends context to an LLM only when you press **Send to API**;
  the endpoint may be a local model. Its Details tab is also a real editor and
  saves a file only when you explicitly use Save.
- Opening a solution runs its MSBuild logic to resolve references. Analyze only
  solutions you trust. AICB does not run third-party Roslyn analyzers or source
  generators.

A small number of explicitly named tools can write configuration or an export;
their tool descriptions state this. The complete threat model and private
reporting route are in [`SECURITY.md`](https://github.com/gregordadera/AICB/blob/main/SECURITY.md).

## Licence at a glance

Use is free for:

- private, hobby and educational use by natural persons,
- accredited educational institutions for teaching, learning and
  non-commercial research,
- organizations that reach **none** of these thresholds: 100 employees,
  EUR 10 million annual turnover, 21 developers.

The thresholds apply to your organization, not to your clients. After first
reaching any one threshold, you have 90 days to agree a commercial licence; use
remains free during that period. Contact `aicb@dadera.de`. There is no technical
licence enforcement. Redistribution, modification, repackaging and competing
products are not permitted. See the [plain-language guide](https://github.com/gregordadera/AICB/blob/main/docs/LICENSING.md),
[`LICENSE.txt`](https://github.com/gregordadera/AICB/blob/main/LICENSE.txt) and the full bilingual [`EULA.md`](https://github.com/gregordadera/AICB/blob/main/EULA.md).

## Documentation and support

- [Getting started](https://github.com/gregordadera/AICB/blob/main/docs/GETTING-STARTED.md) — install, connect and ask the first question
- [Tool reference](https://github.com/gregordadera/AICB/blob/main/docs/TOOLS.md) — generated reference for the default MCP profile
- [Architecture, limits and evidence](https://github.com/gregordadera/AICB/blob/main/docs/ARCHITECTURE.md) — in-memory model, refresh, context selection, static-analysis boundaries and benchmark status
- **[MCP server manual](https://github.com/gregordadera/AICB/blob/main/docs/manual/mcp/README.md)** — the full reference in twelve Markdown chapters: connecting a client, `aicb init`, sessions and staleness, profiles and facets, every tool, troubleshooting
- **[General reference manual](https://github.com/gregordadera/AICB/blob/main/docs/manual/general/README.md)** — the full reference in twelve Markdown chapters, with the printable PDF in the same folder
- **[Desktop app reference manual](https://github.com/gregordadera/AICB/blob/main/docs/manual/desktop-app/README.md)** — the full reference in eleven Markdown chapters, with the printable PDF in the same folder
- [Changelog](https://github.com/gregordadera/AICB/blob/main/CHANGELOG.md) and [latest release](https://github.com/gregordadera/AICB/releases/latest)

Questions and feature requests are welcome in
[GitHub Discussions](https://github.com/gregordadera/AICB/discussions). Report bugs
through [GitHub Issues](https://github.com/gregordadera/AICB/issues); if GitHub does
not offer a **New issue** button, use Discussions. Include `aicb --version` and,
for MCP problems, the output of `server_info`. Report security issues privately as
described in [`SECURITY.md`](https://github.com/gregordadera/AICB/blob/main/SECURITY.md).

"AIContextBuilder" and "AIContextBuilder for .NET" are unregistered trademarks of
Gregor Dadera.
