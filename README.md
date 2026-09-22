# AIContextBuilder (`aicb`)

[![M8ven Score](https://m8ven.ai/badge/mcp/gregordadera-aicb-zb5d9e?v=677e2e58f84eb0a4e92f2063b588e004)](https://m8ven.ai/mcp/gregordadera-aicb-zb5d9e)

**Roslyn-based .NET → dense, LLM-optimized Markdown context.** `aicb` turns a
C#/.NET solution into structured Markdown built for AI models, and exposes the
same engine as an **MCP server** so coding agents (Claude Code, Cursor, Cline, …)
can navigate your code *semantically* instead of by text search.

> **Status:** free for individuals and for organizations below the EULA
> thresholds — see [License](#license). The MCP server and CLI install from
> nuget.org; the Windows desktop app downloads from
> [GitHub Releases](https://github.com/gregordadera/AICB/releases). Closed source — the public repository
> [`gregordadera/AICB`](https://github.com/gregordadera/AICB) carries the documentation, the licence and the
> releases.

## Why

`grep` finds substrings. `aicb` understands the **Roslyn symbol graph** —
overloads, partial types, interface dispatch, DI registration — and answers the
questions an agent actually has *before* it edits:

- **Who calls / uses this? What's the blast radius?** — `find_usages`,
  `impact_of_change` (transitive fan-in, including consumers a compile won't catch).
- **Where is this implemented / overridden?** — `find_implementations`,
  `find_overrides`, `get_type_hierarchy`.
- **What grep can't see** — `find_by_side_effects`, `find_dead_code`,
  `detect_circular_dependencies`, `resolve_injection`, `calls_external`.
- **Pack just enough context for a task** — `get_context`, `pack_for_task`,
  `prepare_task` (edit-ready: covering tests + siblings), `explain_symbol`,
  `export_markdown`.

Every tool also accepts the `.sln` path directly as its `session_id`
(**self-init**) — no separate analyze step needed.

## Install

`aicb` comes in two forms that share one analysis engine. **Install one of them per
machine:**

- **Windows, and you want the desktop app:** the installer. It contains the MCP server
  and CLI as well, so one update brings both to the same version. If the .NET tool is
  already installed, the installer offers to remove it (on by default).
- **Everything else** (Linux, macOS, CI, or no desktop app): the .NET tool.

Both put an `aicb` command on `PATH`. With both installed, the installer's copy is the
one that runs, and `dotnet tool update` would update a copy nothing starts; `aicb init`
warns when it finds more than one.

### MCP server and CLI — Windows, Linux, macOS

A .NET global tool. It needs the **.NET 8 SDK**, which is also what analyzing a
solution needs.

```sh
dotnet tool install -g AIContextBuilder
aicb --version
```

`dotnet tool update -g AIContextBuilder` updates it later. The MCP server is not a
separate program: `aicb mcp` is a verb of this same command.

### Desktop app — Windows

Download from [GitHub Releases](https://github.com/gregordadera/AICB/releases):

- `AIContextBuilder-Setup-<version>.exe` — installer (needs administrator rights;
  puts the `aicb` command on `PATH` unless you untick it). Consoles, editors and agents
  that were already open see the new `PATH` only after a restart.
- `AIContextBuilder-<version>-win-x64.zip` — portable, no installation: `gui\aicb-ui.exe`
  is the desktop app, `cli\aicb.exe` the same CLI/MCP server as above.

Both are self-contained, so no .NET *runtime* is needed to start them — but opening a
solution runs MSBuild, so the machine still needs a **.NET SDK or Visual Studio** to
analyze anything. The installer is not code-signed yet: Windows SmartScreen shows
"Windows protected your PC", and *More info → Run anyway* continues. Every release
lists SHA-256 checksums for its files.

## Use as an MCP server

From your project directory:

```sh
aicb init
```

That writes the pieces a client needs — the `.mcp.json` entry below and the
[agent skill](#agent-skills) — and reports what it did per file. It never
overwrites (`--force` if you want it to), so re-running is safe.

**It also installs a blocking hook, and you should know that before it fires.**
If the project shows a marker for an agent harness aicb knows (`.claude/`,
`.codex/`, `.opencode/`), `init` writes the **symbol guard** into it and wires it
up. The guard is not a hint: it **refuses** a C# symbol search — a grep or a file
read aimed at a type or member name — and points at the aicb tool that answers it
properly. That is what makes the tools get used rather than grepped past, and it
is also the one thing in this install that changes how your agent behaves.

```sh
aicb init --hooks none        # install nothing of the sort
aicb init --hooks claude-code # or codex / opencode / all — install it deliberately
```

To remove a guard that is already installed, delete the aicb entry from the
harness's own configuration — `.claude/settings.json`, `.codex/hooks.json` or
`opencode.json`. `--hooks none` governs what the *next* run writes; it does not
undo an installation. `aicb init` prints both the path and this sentence whenever
it installs one.

Two limits worth knowing if you are not on Claude Code. The agent skill is written
to `.claude/skills/` and nowhere else — where OpenCode and Codex look for skills
has never been measured here, and `init` does not guess, because a guessed path
writes a file nothing loads. And OpenCode discovers MCP servers only through its
own `opencode.json`, not through the shared `.mcp.json` — measured against a
running client, not read off documentation — so an OpenCode user adds the aicb
entry there by hand. `aicb init` names both gaps in its output rather than
reporting a clean success over them.

To do it by hand instead: drop an `.mcp.json` in your project root.

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

Then ask your agent something like *"find the callers of `OrderService.Submit`"* —
it will reach for the semantic tools instead of grep.

### Protocol compatibility

One binary serves **both** current MCP protocol revisions over stdio, from the
same tool pool:

| Revision | Entry point |
|---|---|
| `2026-07-28` | `server/discover` — stateless, every request carries its own metadata |
| `2025-11-25` | `initialize` handshake |

This matters because MCP has no fall-forward: a client that speaks only the older
revision has no way to reach a server that speaks only the newer one. Serving both
means the client picks whichever revision it knows, so `aicb` connects to harnesses
that have already moved to `2026-07-28` and to those that have not.

Both revisions are pinned by an integration test that drives the real server over
raw stdio JSON-RPC (`McpDualEraProtocolTests`):
per revision it asserts that the entry point answers, that `tools/list` is narrowed
to the active profile, that a pooled tool dispatches, and that a tool *outside* the
pool is refused.

Two limits worth stating plainly:

- **stdio only.** There is no HTTP/SSE transport, so the HTTP-specific parts of the
  newer revision (session headers, resumability, OAuth) do not apply here.
- **Server instructions are delivered, not pushed.** On `2026-07-28` they travel in
  the discover result, but whether a client ever re-discovers is the client's
  decision — so after changing the active profile, restart the server to be sure the
  agent sees the new instructions.

### Agent Skills

[`skills/aicb-csharp-context/`](https://github.com/gregordadera/AICB/blob/main/skills/aicb-csharp-context/SKILL.md) is an
[Agent Skill](https://agentskills.io) that teaches an agent *when* to reach for
these tools — the routing table, the pre-edit blast-radius gate, and when plain
grep is still right. It uses only standard `SKILL.md` fields, so it works in any
skills-compatible agent. `aicb init` writes it to `.claude/skills/aicb-csharp-context/`
for you; copy or symlink that folder to `~/.claude/skills/` to have it in every
project rather than one.

It has to be copied there — the `dotnet tool` install cannot do it. A tool install
unpacks the package into a `.store` directory beside the launcher, and no agent scans
that for skills, so a `SKILL.md` shipped inside the nupkg would land on disk and never
be found. That is what `aicb init` is for.

Two further skills ship alongside it and are **opt-in**: `aicb init --skills=all` also
writes [`aicb-code-review`](https://github.com/gregordadera/AICB/blob/main/skills/aicb-code-review/SKILL.md) and
[`aicb-code-simplifier`](https://github.com/gregordadera/AICB/blob/main/skills/aicb-code-simplifier/SKILL.md), a post-change review pair
— one for correctness, one for unnecessary complexity — that checks its own findings
against aicb facts rather than guessing from the diff. They stay out of a default `init`
because they are an opinion about how you work, not part of the tool.

The `aicb-` prefix is not decoration. `code-review` and `code-simplifier` are common
names: an agent may already have a built-in command or a personal skill under either,
and a same-named skill loses silently — nothing reports the collision.


By default `aicb mcp` exposes a **lean 54-tool pool** covering all nine task
facets — the semantic/structural set that complements grep/Read, minus a
long-tail of tools whose signal did not hold up. Those are still registered and
one profile switch away: `--mcp-profile mcp-profile/full` serves the unnarrowed 72.
Set `AICB_MCP_TOOLS=all` to add the opt-in infrastructure tools on top. With
`--db-path` it is
profile-aware (reads the per-solution exclusions / test / layer config and the
active MCP profile from an `aicb` config DB), and `--mcp-profile <id>` pins which
profile that is for this server process — process-local, it writes nothing back,
so a second server or the GUI keeps its own. Pinning at start also keeps
`tools/list` stable for the lifetime of the process, which is what the newer
protocol revision asks for.

## CLI

```
aicb init      Wire aicb into this project (.mcp.json + the agent skill + the symbol guard).
aicb analyze   Run Roslyn analysis on a solution and emit context Markdown.
aicb export    Re-render Markdown from an existing session DB (no Roslyn re-run).
aicb import    Import a constellation JSON into a target DB.
aicb list      List built-in + custom master entities (run-templates / detail-presets / model-profiles).
aicb mcp       Start the MCP server (stdio JSON-RPC) for Claude Code / Cursor / Cline.
aicb call      Invoke ONE MCP tool once and print its result — no server, no client needed.
```

`aicb call` is the shortcut worth knowing: it answers a single semantic question from a
plain shell, and it reaches **every** tool — including the opt-in ones outside the
default profile's pool:

```sh
aicb call find_usages --sln C:/repo/App.sln --arg symbol=OrderService
```

Run `aicb <command> --help` for options.

## Per-solution configuration (optional)

`aicb` can tailor analysis per solution — namespace exclusions, a test-detection
profile, and a layer-mapping profile. The MCP guided-setup tools
(`solution_config_status` → `init_solution_config` → `apply_solution_config`)
write this both to a config DB and to a git-tracked `<Solution>.aicb.json`
sidecar next to the `.sln`, so the config travels with your repo. Omit `dbPath`
to use the default config DB.

One sidecar setting has no wizard and is written by hand — analysis scope:

```json
{ "analyzePreferredTfmOnly": true }
```

A multi-targeted project (`<TargetFrameworks>net8.0;netstandard2.0</…>`) is
loaded once per target framework, so every source file is analyzed N times. With
this key set, `aicb` analyzes only the newest target framework's instance of each
project. The markdown export drops from N copies of each project to one.

The type and method **inventory** is unchanged — every symbol a query can name is
still there. Two things do change, and both are pinned by tests: a fan-in edge whose
only source is a non-preferred instance is lost, so `find_usages`, `impact_of_change`
and `call_graph` can report a smaller blast radius; and transitive side-effect facts
shift, because the narrower run sidesteps a separate index defect that let the
alphabetically-last instance overwrite the preferred one. `find_dead_code` does not
turn false-positive on this — it abstains when fan-in is unknown rather than claiming
a symbol is dead.
Default is off, and on a solution without multi-targeting the setting does
nothing at all — the saving is entirely solution-specific (measured: 63 % of the
documents on `dotnet/roslyn`, 0 % on nopCommerce and on mapperly).

## Documentation

Full manuals (PDF, English, written against `0.5.464.32`):

- [General](https://github.com/gregordadera/AICB/blob/main/docs/manual/AICB-General.pdf) — installation, licence, CLI reference, the context document, analysis rules, troubleshooting
- [MCP server](https://github.com/gregordadera/AICB/blob/main/docs/manual/AICB-MCP-Server.pdf) — client setup, profiles, all 82 tools with their parameters
- [Desktop app](https://github.com/gregordadera/AICB/blob/main/docs/manual/AICB-Desktop-App.pdf) — every page, panel, dialog and setting of the Windows app

Shorter guides: [`docs/GETTING-STARTED.md`](https://github.com/gregordadera/AICB/blob/main/docs/GETTING-STARTED.md), [`docs/TOOLS.md`](https://github.com/gregordadera/AICB/blob/main/docs/TOOLS.md),
[`docs/LICENSING.md`](https://github.com/gregordadera/AICB/blob/main/docs/LICENSING.md).

## Security

**The MCP server never modifies the code it analyses.** Nothing any tool writes is
anything Roslyn reads, so an answer is always about the tree you wrote. What it
*does* write is named rather than implied: `apply_solution_config` persists a
git-tracked `<Solution>.aicb.json` sidecar next to the `.sln` and returns its path,
`install_agent_hooks` installs the symbol guard into your agent harness's own
configuration on explicit request, and `export_markdown` writes the file you point
`outputPath` at. Every tool that persists anything says so in its own `tools/list`
description.

**The desktop app is the deliberate exception.** Its Details tab is a real editor:
a source file that loads cleanly becomes editable and can be written back with Save
or `Ctrl+S`, keeping its original encoding and line endings. A file that is missing
or fails to load stays read-only. The MCP server and the CLI cannot do this at all —
the capability is not in those assemblies.

**Nothing leaves your machine unless you send it.** The CLI and the MCP server have
no outbound network capability whatsoever: the product's single `HttpClient` is
registered in the desktop graph alone, so it is absent rather than switched off. The
desktop app can send a rendered context to an LLM — that is what its "Send to API"
button does, and the endpoint may be a local model — and it does so only on your
action. There is no telemetry, no update check, no crash reporting and no analytics
anywhere in the product.

One caveat, unchanged: opening a solution runs its MSBuild build logic to resolve
references — exactly like Visual Studio or `dotnet build` — so **only analyze
solutions you trust**. `aicb` does **not** load or run your solution's third-party
Roslyn analyzers or source generators (`get_diagnostics` returns compiler
diagnostics only). Details and how to report a vulnerability:
[`SECURITY.md`](https://github.com/gregordadera/AICB/blob/main/SECURITY.md).

## License

**Free to use** for:

- private, hobby and educational use by natural persons,
- accredited educational institutions, for teaching, learning and
  non-commercial research,
- organizations that reach **none** of these three thresholds: 100 employees,
  EUR 10 million annual turnover, 21 developers.

The thresholds measure **your** organization only — the size of the clients you
work for does not matter, including on their premises.

Once your organization reaches one of them, a commercial licence is required
before further use, and you have 90 days to arrange it; terms are agreed
individually, so please get in touch. A
[donation](https://github.com/sponsors/gregordadera) is welcome but separate — it
does not replace a licence where one is required. The software contains no
technical verification of any of this: no licence server, no activation token, no
telemetry. Compliance is your own responsibility.

Redistribution, modification, repackaging, and competing products are not
permitted. See [`LICENSE.txt`](https://github.com/gregordadera/AICB/blob/main/LICENSE.txt) for the summary and
[`EULA.md`](https://github.com/gregordadera/AICB/blob/main/EULA.md) for the full bilingual EULA.

## Support

Questions, bugs and feature requests: [GitHub Issues](https://github.com/gregordadera/AICB/issues). Please
include `aicb --version` and — for the MCP server — the output of the `server_info`
tool. Security issues go the private route described in `SECURITY.md`, not into a
public issue.

"AIContextBuilder" and "AIContextBuilder for .NET" are unregistered trademarks of
Gregor Dadera.
