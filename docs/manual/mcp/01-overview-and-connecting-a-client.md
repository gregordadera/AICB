[AICB – MCP Server](README.md) &middot; chapter 1 of 12

# 1 Overview and connecting a client

`aicb mcp` starts the AIContextBuilder MCP server (Model Context Protocol). It makes the analysis engine available to an AI coding agent as a set of **tools**: the agent connects to the server, asks questions such as "who calls `OrderService.Submit`?", and gets its answer from a Roslyn analysis of your solution instead of from a text search.

This chapter covers what the server is, how to start it, what a client has to be told, which clients and protocol revisions are served, what identity the server reports, and exactly what your agent reads at the handshake.

## 1.1 What the MCP server is

- **It is not a separate program.** `aicb mcp` is a verb of the same `aicb` command you use for everything else. There is nothing extra to install for the server itself.
- **One server process per client, stdio transport.** The server speaks JSON-RPC on standard input/output. A client starts it as a child process and talks to it over that channel. When the client disconnects (stdin closes) or the process is cancelled, the server shuts down cleanly with exit code `0`.
- **Session-bound.** The server keeps an analysis of your solution warm. Most tools take a `sessionId`; every tool that takes one also accepts the absolute path of a `.sln`, `.slnx` or `.slnf` file directly and analyzes it on first use, so calling `analyze_solution` first is optional. Answers come from that cached analysis graph; after you edit `.cs` files, `refresh_session` rebuilds it and `get_diagnostics` is the fast pre-build check.
- **A curated tool pool.** The server registers its whole tool surface but exposes a curated pool. Without further configuration that is the built-in `Default` profile with **54 tools** covering all nine task facets. The built-in `Full Select` profile serves the unnarrowed **72**: start the server with `--mcp-profile mcp-profile/full` for it. The environment variable `AICB_MCP_TOOLS` overrides the pool for the process (`all`, `lean`, or a comma-separated list of tool class names) and wins over the active profile.
- **Read-only with respect to your code.** Nothing any tool writes is anything Roslyn reads, so every answer is about the tree you wrote. Tools that persist something outside the analysis — `apply_solution_config`, `export_markdown`, `install_agent_hooks`, `save_session`, `remember_codebase`, `refresh_remembered`, `import_constellation` and `diff_review` with `recordRegressions: true` — say so in their own descriptions.
- **Nothing leaves your machine.** The server has no outbound network capability at all.

## 1.2 Starting the server: `aicb mcp`

The verb describes itself as:

> `Start the MCP server (Model Context Protocol, stdio JSON-RPC) - for Claude Code / Cursor / Cline. With --db-path profile-aware (render slots + tool set + skill from the active MCP profile); --mcp-profile pins which profile that is, for this process only.`

You normally do not start it yourself — your MCP client starts it from its configuration. The command has exactly two options:

| Option | Effect | Default |
|---|---|---|
| `--db-path <file>` | Binds the server to a specific `aicb` configuration database and makes it profile-aware: `export_markdown` renders through the active MCP profile, the exposed tool set follows that profile, and its working style shapes the server instructions. The database also supplies the per-solution configuration (layer, exclusions, test detection). | none — the **standard configuration database is resolved automatically** |
| `--mcp-profile <id>` | Pins the active MCP profile for **this process**. The pin is process-local: it writes nothing back, so a second server or the GUI keeps its own active profile. An unknown id aborts the start. | none — the profile marked active in the configuration database applies |

### `--db-path` and the standard configuration database

"Without `--db-path`" does **not** mean "without a database". When you omit the option, the server resolves the standard configuration database — the same one the GUI uses, on Windows `%APPDATA%\AIContextBuilder\user-data\aicb.acb` — and announces the path on stderr:

```text
No --db-path given; using the standard config DB (same as the GUI): <path>
```

The database is created and migrated on first start if it does not exist, so a first-time user without a GUI starts profile-aware rather than profile-blind. Only if that resolution or the migration fails does the server start without a profile, with a warning:

```text
warning: standard config DB path could not be resolved (<reason>); starting DB-free (default profile's pool).
```

An explicitly given `--db-path` behaves differently for a file that does not exist: it is treated as a user hint and is **not** created silently. You get

```text
warning: --db-path not found (<path>); starting without a profile (default profile's pool).
```

and the server starts with the default profile's pool. A schema migration failure on the given database produces

```text
warning: --db-path schema migration failed (<reason>); starting without a profile.
```

With a usable database the server prints the profile it actually serves, for example:

```text
Active MCP profile: 'Default' (mcp-profile/default); tool set: methods:server_info,analyze_solution,…; skill: (none).
```

The line is extended with `[pinned via --mcp-profile; not persisted]` when you pinned a profile.

Note: `aicb mcp --help` describes `--db-path` as optional with a DB-free fallback when it is omitted. In practice the standard configuration database is resolved automatically as described above, and the server starts without a profile only when that resolution or its migration fails.

### `--mcp-profile`

`--mcp-profile <id>` pins the active MCP profile for the lifetime of the process. The ids are the ones `list_mcp_profiles` reports (or the `MCP Profiles` panel in the GUI); the four built-in profiles are `mcp-profile/default`, `mcp-profile/full`, `mcp-profile/refactoring-focus` and `mcp-profile/debugging-focus`. On success the server says:

```text
Pinning the MCP profile to '<id>' for this process (--mcp-profile); the profile persisted in the config DB is left unchanged.
```

Pinning at start also keeps `tools/list` stable for the lifetime of the process, which the newer protocol revision asks for. There is no runtime switch: changing the profile means restarting the server with a different id.

A pin that cannot be applied is the one case in which the server refuses to start instead of degrading to the default profile. That covers every way it can fail — no configuration database, missing file, failed migration, unknown id, hidden profile:

```text
error: unknown MCP profile '<id>' (--mcp-profile). Available: <ids>.
error: --mcp-profile '<id>' could not be applied (see above). Refusing to start on a different profile.
```

The exit code is `1`. An unknown id lists the ids that would work, because over stdio you have no other way to discover them. Hidden profiles are rejected on the same grounds: they are not listed, so pinning one would be an invisible configuration.

### What else the server announces at startup

All diagnostics go to stderr, never to the protocol channel. Whether you see them depends on your client; most clients keep a server's stderr in their own log. Besides the lines above, the server writes:

| Message | Meaning |
|---|---|
| `warning: MSBuild could not be registered (<reason>). analyze_solution/refresh_session will fail; the remaining tools stay usable.` | The MSBuild bootstrap failed. Analysis and session tools will not work; the rest of the tool surface does. |
| `MCP tool curation: <tool set>; spec=<spec>; active MCP profile=<profile>; session auto-refresh=<mode>.` | Which pool is exposed right now (a static count under `AICB_MCP_TOOLS`, or the live profile count), the tool-set specification in effect, the profile, and the session auto-refresh mode (`off`, `reactive` or `proactive`). |

Exit codes of the verb:

| Exit code | Meaning |
|---|---|
| `0` | Clean shutdown: the client disconnected (stdin closed) or the process was cancelled. |
| `1` | `--mcp-profile` could not be applied. The server refuses to start on a different profile than the one you asked for. |

## 1.3 The stdio channel

stdout **is** the JSON-RPC channel. A single stray line written to stdout — by product code, by a library, or by MSBuild or Roslyn during an analysis — puts a non-JSON line into the protocol stream. A strict client treats that as a protocol violation and tears the connection down: the server process keeps running, but every client on it is left with `Connection closed` and no way back. This is the one failure mode a stdio server cannot survive, so the server protects the channel in two layers:

- **Logging is redirected to stderr.** Every log record the server and its libraries produce goes to stderr, at every level.
- **Every other writer is redirected too.** `Console.Out` is pointed at stderr before anything else can write, so no code path in the process — including one written later — can put a byte into the protocol channel. The transport itself is unaffected: it holds its own handle on standard output. Redirecting to stderr rather than discarding is deliberate: a stray write is a defect you want to see.

Fatal background failures are reported on stderr as well, before the process goes: an unhandled exception (`FATAL: unhandled exception - the aicb MCP server is terminating: <error>`) and an unobserved task exception (`WARNING: unobserved task exception in the aicb MCP server: <error>`). The server cannot prevent such a termination, but it turns a silent death into a named one.

Note: `Connection closed` is a channel problem, not a tool crash. Ordinary tool failures do not close the connection — they come back to the client as clean error responses.

## 1.4 Connecting a client

### The quick path: `aicb init`

Run `aicb init` in your project directory. It writes the entry your client needs into `.mcp.json`, writes the agent skill into `.claude/skills/`, and installs the symbol guard for the agent harnesses in use. It never overwrites an existing file unless you pass `--force`, so re-running is safe.

| Option | Effect | Default |
|---|---|---|
| `--path <dir>` | Project directory to wire up. | the current directory |
| `--force` | Overwrite artefacts that are already there. Without it, an existing `aicb` entry or skill file is left untouched. | off |
| `--skills context\|all` | `context` writes the `aicb-csharp-context` skill; `all` adds the `aicb-code-review` / `aicb-code-simplifier` review pair. | `context` |
| `--hooks auto\|none\|all\|claude-code\|codex\|opencode` | Which agent harnesses to install the symbol guard for: the ones already used in this project, none, all, or one by name. | `auto` |

The run reports each artefact with one of four labels — `created`, `updated`, `kept`, `refused` — and ends with:

```text
Restart or reconnect your MCP client, then call server_info to confirm it took.
```

That last line is the step `init` cannot do for you: a client reads its server list at startup. If you only want the server wiring and no guard, pass `--hooks none`. That writes no enforcement; it does not remove an installation that is already there.

Two client-specific limits are named in the output rather than reported as a clean success: the agent skill is written to `.claude/skills/` only (where other harnesses look for skills has not been measured, and `init` does not guess, because a guessed path writes a file nothing loads), and **OpenCode** discovers MCP servers only through its own `opencode.json`, not through the shared `.mcp.json` — add the `aicb` entry there by hand.

### Writing the client entry by hand

`.mcp.json` in your project root holds the server list. The minimal entry is:

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

`command` is resolved by your client through the normal executable search. If `aicb` is not on the `PATH` your client sees, use the absolute path of the executable instead:

```json
{
  "mcpServers": {
    "aicb": {
      "command": "C:\\Tools\\AICB\\aicb.exe",
      "args": ["mcp"]
    }
  }
}
```

On Windows a JSON string needs its backslashes escaped as `\\`. Any `aicb mcp` option can be placed in `args`, for example:

```json
{
  "mcpServers": {
    "aicb": {
      "command": "aicb",
      "args": ["mcp", "--mcp-profile", "mcp-profile/full"]
    }
  }
}
```

Note: do not confuse `.mcp.json` (a client's server list, in your project) with `aicb.mcp.json` (the server's own settings, in your user configuration directory, on Windows `%APPDATA%\AIContextBuilder\aicb.mcp.json`). The server only reads the latter; it never writes it.

### What `aicb init` does to an existing `.mcp.json`

`init` merges the `aicb` entry into the server list it finds and never disturbs the other entries. There are five possible outcomes, each with its own sentence in the report:

| Outcome | Report sentence |
|---|---|
| No file was there | `created with the aicb entry` |
| The file was there, other entries were kept | `aicb entry added, existing entries kept` |
| An `aicb` entry was already there | `already has an aicb entry - left untouched` |
| An `aicb` entry existed and `--force` replaced it | `existing aicb entry replaced (--force)` |
| The file is not usable as a server list | `left untouched - not valid JSON, or a duplicate key, or the top level is not an object, or 'mcpServers' is not an object; fix or remove it and re-run` |

The last row is the load-bearing rule: when the existing document does not parse, contains a duplicate key, or is not a JSON object, the command writes **nothing**. Overwriting a configuration you own is unreachable rather than merely unlikely. Parsing is strict — comments and trailing commas are not accepted — because a tolerant read followed by a write would silently delete whatever the tolerance swallowed. Without `--force`, an existing `aicb` entry is left exactly as it is; you may have pointed it at a different binary, a wrapper script or a debug build.

### After connecting

1. Restart or reconnect your client so it reads the new server list.
2. Ask your agent for something concrete, for example *"find the callers of `OrderService.Submit`"*.
3. Call `server_info` to confirm the connection took and to see the identity and drift report described below.

## 1.5 Clients and protocol revisions

The server serves both current MCP protocol revisions over stdio, from the same tool pool:

| Revision | Entry point |
|---|---|
| `2026-07-28` | `server/discover` — stateless; every request carries its own metadata |
| `2025-11-25` | `initialize` handshake |

This matters because MCP has no fall-forward: a client that speaks only the older revision has no way to reach a server that speaks only the newer one. Serving both means the client picks whichever revision it knows. Older revisions are accepted as well, because the MCP SDK the server is built on keeps its backward compatibility; the server itself does not branch on the revision at any point. Observed against a running server:

| Client | `clientInfo.name` | Protocol revision observed |
|---|---|---|
| Claude Code | `claude-code` | `2026-07-28` and `2025-11-25` |
| Codex | `codex-mcp-client` | `2025-06-18` |
| OpenCode | `opencode` | `2025-11-25` |

The verb description and the README also name Cursor and Cline; neither has been verified against a running server.

Two limits are worth stating plainly:

- **stdio only.** There is no HTTP/SSE transport, so the HTTP-specific parts of the newer revision (session headers, resumability, OAuth) do not apply here.
- **Instructions are delivered, not pushed.** The server sends them at the handshake, but whether a client ever re-reads them is the client's decision. After changing the active profile, restart the server (or reconnect the client) so the agent sees the new instructions.

Two facts matter when a profile changes while a server is running:

- A running server keeps the configuration it started with: the tool list, the instructions and the session auto-refresh mode are fixed at start. A profile edited in the GUI (or by another process writing the configuration database) reaches the server only after a restart or reconnect; until then `server_info` reports the pending change as CONFIG DRIFT.
- `tools/list` carries caching hints: a time-to-live of **15 minutes** and a private cache scope (the list must not be shared between users). The server declares both `tools/list_changed` and `resources/list_changed` but sends neither notification, so a client may keep its cached tool list until that time-to-live expires. Restart the server after changing the active profile, and reconnect the client.

## 1.6 Server identity and handshake metadata

The server introduces itself to every client as:

| Field | Value |
|---|---|
| Server name | `aicb` — deliberately the CLI tool name, not the internal assembly name. This is the name clients and directories display. |
| Server version | The version of the installed binary, the same number `aicb --version` prints. It is protocol- and telemetry-bearing: it travels in the handshake and is recorded with every tool call. |
| Instructions | The fixed text plus the active profile's working style — see below. |
| Capabilities | `logging`, `resources` and `tools`; both `resources` and `tools` declare `listChanged` (the server sends neither list-changed notification). |

The git commit the binary was built from is **not** part of the handshake. `server_info` reports it separately when the assembly's informational version carries one. Public installer, ZIP and dotnet-tool release builds deliberately omit it; development builds can include it. When present, it distinguishes binaries that share a version number; when absent, `server_info` does not guess.

## 1.7 What your agent reads at the handshake

### The delivered text

The instructions are composed from ordered blocks, not from one string. The order is the delivery order, and it is deliberate: everything that changes what the agent **does** stands before everything that merely informs it, so a client that cuts the text keeps the behavior rules. The fixed text is:

```text
AIContextBuilder (aicb) - a Roslyn MCP server that answers questions about a C#/.NET solution. For C# SYMBOL questions use aicb tools, never grep/Read: e.g. find_usages, impact_of_change, find_implementations, find_tests_for and find_symbol. Text search matches only substrings and misses overloads, aliases, partial types and interface dispatch. Symbol-or-text self-test: SYMBOL = C# type, method, interface or member. Plain text = literals, comments, logs/config keys; non-C# files stay with text search.
---
Pre-edit gate: before ANY edit that changes a symbol other code names - a rename included - the FIRST call is impact_of_change; the trigger is the symbol's REACH, not the kind of edit. It returns the transitive fan-in closure, including consumers a compile does not check (a count assertion, a non-exhaustive switch statement) and a direct find_usages does not show.
SELF-INIT: every tool that TAKES a session also accepts the absolute .sln/.slnx/.slnf path directly and analyzes it on first use.
analyze_solution is optional. After editing .cs files: refresh_session FIRST, then get_diagnostics as a fast pre-build check - EVERY session-bound tool, get_diagnostics included, may otherwise answer from the stale pre-edit graph.
On a new solution, check solution_config_status; if an axis (layer / exclusions / test) is uninitialized, run init_solution_config then apply_solution_config (persists a git-tracked .aicb.json next to the .sln).
New to aicb? docs() is the operating manual; list_skills is the full tool map.
list_insights(sessionId) surfaces code-quality / async / design-smell findings.
The session-less tools (server_info / list_skills / usage_report / list_mcp_profiles) take no path at all, and a comparison tool such as verify_claim takes TWO sessions, each of which accepts one.
Tool results are structured for machine reading and may include source locations, confidence or bounded follow-up hints; use the returned evidence when reporting a conclusion.
DB-entity tools outside the default profile's pool, expose them via AICB_MCP_TOOLS: list_run_templates / list_constellations browse the reusable run-templates and constellations in an aicb DB, and import_constellation imports a constellation JSON into one.
```

The line breaks above follow the block boundaries for readability. On the wire the blocks are concatenated without separators; the only line break inside the fixed text is the `---` separator after the self-test. Most blocks end with a space.

What each rule tells the agent:

| Rule | Purpose |
|---|---|
| Identity | What the server is. One sentence — an agent that reads nothing else still knows what it is connected to. |
| Symbol questions | For C# symbol questions use aicb tools, never grep or a file read. Names five examples; explains that text search misses overloads, aliases, partial types and interface dispatch. |
| Symbol-or-text self-test | How to decide in the moment: a symbol is a C# type, method, interface or member; literals, comments and configuration keys are plain text. |
| Pre-edit gate | Before any edit that changes a symbol other code names — a rename included — the first call is `impact_of_change`. The trigger is the symbol's reach, not the kind of edit. |
| Self-init | Every session-taking tool accepts a `.sln`, `.slnx` or `.slnf` path directly. |
| Refresh after edit | `analyze_solution` is optional; after editing `.cs` files call `refresh_session` first, then `get_diagnostics` as the fast pre-build check. |
| Solution configuration | On a new solution, check `solution_config_status`; initialize an uninitialized axis (layer, exclusions, test) with `init_solution_config` and `apply_solution_config`. |
| Manuals | `docs()` is the operating manual, `list_skills` the full tool map. |
| Insights | `list_insights` surfaces code-quality, async and design-smell findings. |
| Call shapes | The session-less tools (`server_info`, `list_skills`, `usage_report`, `list_mcp_profiles`) take no path; a comparison tool such as `verify_claim` takes two sessions. |
| Result shapes | Results are structured for machine reading and may carry source locations, confidence or bounded follow-up hints; report the returned evidence. |
| DB-entity tools | `list_run_templates`, `list_constellations` and `import_constellation` are outside the default profile's pool and are exposed via `AICB_MCP_TOOLS`. |

### Delivery budgets

The server **never truncates** the instructions — it sends the complete composed text. Two client-side budgets shaped the order of the text:

| Boundary | Value | Meaning |
|---|---|---|
| Codex discovery surface | first **512 characters** | Codex documents the first 512 characters as the surface available before deferred tool loading. This is a placement requirement, not a claim that Codex truncates there: the identity line and the discovery rules are placed so that this prefix is self-contained. |
| Claude Code prompt prefix | first **2,048 characters** | The largest prefix of the instructions known to be delivered by a client, measured against Claude Code. |

Both values are **characters**, not bytes, and both protocol revisions use the same budget — the newer revision does not deliver more. The 2,048-character figure is a measurement, not a preference, and it is not a maximum length for the text: a client with a larger budget receives all of it. That is why the fixed text is ordered by delivery priority rather than narrative flow, and why the profile's working style is placed before the reference material instead of appended at the end.

The MCP profile editor in the GUI previews the composed text under the label `Exactly what the MCP server sends for this profile, shown in two client-specific availability boundaries.` and draws a cut mark at the measured budget, so you can see whether a working style lands above or below the line.

### Omission under a narrowed profile

A rule that names tools is an invitation to call them, and a call the server then refuses is indistinguishable from a wrong tool choice. When the exposed pool does not contain **any** of the tools a rule names, the server therefore leaves that whole rule out of the handshake. Consequences worth knowing:

- The identity line and the discovery rules are never omitted.
- A rule is dropped only when **all** of the tools it names are unavailable; a rule that still names one reachable tool keeps its text, including the names it cannot reach.
- The block about the DB-entity tools is never omitted either, because its subject is precisely tools outside the pool; it keeps the phrase `outside the default profile's pool` **before** every name it mentions, so a client that cuts the text cannot receive a name without the reason not to call it.
- The same exposed set drives listing, callability and the instructions, so "listed", "callable" and "named in the handshake" cannot drift apart — including under the `AICB_MCP_TOOLS` override.

### The working style

The active MCP profile's working style is spliced into the middle of the fixed text, after the behavior rules and before the reference material, under the heading `Working style:`. It is spliced rather than appended because an appended style would stand behind the whole fixed text — well past the measured budget, so no client would ever receive one.

The guarantee is one number: a profile with exactly **one** guidance block is delivered whole. From the second block on the style may be cut by a client with the measured budget; that is deliberate, and the profile editor discloses it instead of promising it away (`Part of this profile's working style falls below the line and is dropped by such a client. Exactly one guidance switch is guaranteed to arrive whole; beyond that it depends on their combined length, which the cut mark above shows.`).

### When the instructions change

Instructions are read **once**, at the handshake; the protocol has no instructions-changed notification. A profile edit therefore reaches the text at the next server start. In between, the `server_info` tool reports the change as CONFIG DRIFT — its signal that the running server serves a different configuration than the database now holds, and that a restart is due.

## 1.8 Unknown arguments are disclosed, not rejected

The MCP SDK binds the arguments a tool knows and drops the rest without a word. When the mistyped name belongs to a **required** parameter, the call fails to bind and you get a visible error. When it belongs to an **optional** parameter, there is no signal at all: the call succeeds and answers a different question than the one you asked. A namespace filter that was silently dropped, for example, turns a local answer into a solution-wide one that reads like a local finding.

### On a successful call

Every successful response that had argument names dropped carries an extra content block of this form:

```text
<!-- ignored-arguments: <names> are not parameters of <tool> and had NO effect on this answer - it was computed as if they had not been sent. <tool> takes: <parameter list>. -->
```

The block is a remark about the request, appended next to the answer rather than spliced into it, so it cannot corrupt the payload. At most eight dropped names are spelled out; the rest are summarized as `(+N more)`. A name is reduced to the identifier characters a real parameter name could contain, and becomes `(unprintable)` when nothing is left. The server stays silent when it cannot speak with authority — for an unknown tool, or a tool whose parameter list it cannot read, no note is emitted, because a half-known inventory would accuse you of sending something invalid on the strength of a failed lookup.

The disclosure is not a refusal. The answer is correct for the call **as bound**, and refusing would turn a working call into a hard failure over what may be a stray field. What the note gives you is the visibility to fix the call. One concrete case worth remembering: the parameter for namespace filtering is named `scope`.

### On a failed call

A mistyped required parameter fails before the tool is entered. The error then names the tool's real arguments instead of only reporting the failure:

```text
<ExceptionType>: <cause> - This is an ARGUMENT-BINDING failure: the call never reached the tool, so retrying it unchanged fails identically. <tool> takes: <parameter list, required ones marked (required)>. You sent: <names>. Not a parameter of this tool: <names>.
```

The message states which arguments the tool takes, which were passed, and which of those are not recognized — so the fix does not require comparing your call against the input schema again. Retrying the same call unchanged is called out explicitly, because it fails identically every time.

---

[Contents](README.md) &middot; [2 Setting up an agent: aicb init &rarr;](02-setting-up-an-agent-aicb-init.md)
