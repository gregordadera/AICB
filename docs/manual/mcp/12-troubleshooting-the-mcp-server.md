[AICB – MCP Server](README.md) &middot; chapter 12 of 12

# 12 Troubleshooting the MCP server

This chapter is for the person who runs `aicb` as an MCP server and reads what an agent reports back. The server has no window of its own: nearly every problem surfaces either as a message in a tool answer, as a client-side error such as `MCP error -32000: Connection closed`, or as a line in the stderr log of your MCP client. The sections below are ordered by symptom. Each one names the message you will see, the cause, and what to do about it.

Two rules make the rest of this chapter easier to use:

- **Do not judge freshness from the tool you called.** Every session-bound answer that may be out of date carries its own note (a `staleness` JSON member or a `<!-- staleness: … -->` comment). Read the note, not the clock.
- **Read the leading note before the list.** Several tools put a caveat about the analysis run, or about an empty scope, ahead of their data. That caveat is often the actual answer to "why does this look wrong?".

## 12.1 The client does not list any `aicb` tools

**Symptom.** Your MCP client shows no `aicb` server or no `aicb` tools, or it reports that it cannot start the command.

**Cause and solution.** The server is started by the client from an entry in the project's `.mcp.json`:

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

`"command": "aicb"` requires `aicb` to be on your `PATH`. The installer puts it there (unless you untick that task); the portable ZIP does not, because it only unpacks files. For a portable copy, write the full path into the JSON and double every backslash:

```json
{ "mcpServers": { "aicb": { "command": "C:\\path\\to\\this\\folder\\cli\\aicb.exe", "args": ["mcp"] } } }
```

Check the setup step by step:

1. Open a **new** terminal and run `aicb --version`. If the command is not found, use the full path to `aicb.exe` in the `.mcp.json` entry instead.
2. In your project directory, run `aicb init`. It writes the `.mcp.json` entry and the agent skill, and reports per file what it did. It never overwrites an existing artefact (`aicb init --force` does).
3. Restart or reconnect your MCP client. A client reads its server list at startup; a running client will not see a new entry. Consoles, editors and agents that were already open also see a changed `PATH` only after a restart.
4. Ask the agent to call `server_info`. If that answers, the connection works.

**Note.** OpenCode does not read the shared `.mcp.json`; it discovers MCP servers only through its own `opencode.json`. Add the `aicb` entry there by hand, or the server stays invisible to it. `aicb init` prints this gap in its output when it detects that harness.

**Two installations on one machine.** If `aicb` exists twice (for example the desktop installer and a .NET global tool), only the **first** one on `PATH` is ever started, and updating the other one changes nothing a client runs. `aicb init` warns when it finds more than one and lists which is used and which is ignored. Keep one: uninstall the global tool, or uninstall the desktop app under Windows Settings > Apps.

## 12.2 Protocol revision and transport

The server speaks both current MCP protocol revisions over stdio from the same tool pool. The client picks the one it knows:

| Revision | Entry point |
|---|---|
| `2026-07-28` | `server/discover` — stateless, every request carries its own metadata |
| `2025-11-25` | `initialize` handshake |

This matters because MCP has no fall-forward: a client that speaks only an older revision cannot reach a server that speaks only a newer one. `aicb` answers both entry points, and it also serves older revision handshakes (for example `2025-06-18`, which some clients still negotiate), so you do not have to configure or match a revision.

Two limits are worth knowing:

- **stdio only.** There is no HTTP/SSE transport, so the HTTP-specific parts of the newer revision (session headers, resumability, OAuth) do not apply here.
- **Server instructions are delivered, not pushed.** After you change the active profile in the GUI, restart the server. A running client is not told that the instructions changed.

**Note.** The tool list has a lifetime of 15 minutes and the server never sends a `tools/list_changed` notification. A profile change made outside the running server (for example in the GUI) reaches it only after a restart; until then `server_info` reports it as config drift. After the restart, a client picks up the new list when its cached copy expires or when it reconnects.

## 12.3 `Tool '<name>' is not in the active profile`

**Symptom.**

```
Tool '<name>' is not in the active profile - call list_mcp_profiles to see the profiles and their tools, then restart the server with 'aicb mcp --mcp-profile <id>' to run under a different one.
```

**Cause.** The exposed tool set is decided by an MCP profile. The Default profile serves 54 of the 82 registered tools, while `Full Select` serves the 72-tool lean core. The remaining routes are explicit: `compare_public_api` needs the `api-surface` bundle (or an override), and nine uncatalogued session/memory/database tools are reachable only through `AICB_MCP_TOOLS`.

**Solution.**

1. Call `list_mcp_profiles` if the active profile exposes it. It lists every profile with its id, its tool selection and whether it is active. A custom profile can switch this core tool off; `server_info` is the only core tool that cannot be disabled.
2. Restart the server with the profile you want, for example `aicb mcp --mcp-profile mcp-profile/full`. The pin is process-local: it does not change the profile stored in the config DB. The same ids are visible in the GUI under `MCP Profiles`.
3. There is **no runtime switch**. The active profile is fixed when the server starts, because the tool list must not depend on a previous tool call. Changing it always means a restart.

**`AICB_MCP_TOOLS` — the operator override.** The environment variable `AICB_MCP_TOOLS` takes precedence over the active profile. `all` exposes every registered tool, literal `lean` exposes the 72-tool lean core, and a comma-separated list narrows the set to those tool classes. Empty or unset means no environment override, so the config file and active profile decide. A list prefixed with `methods:` names individual tools instead of classes.

**`list_mcp_profiles` needs a config DB.** On a server that started without one it answers:

```
MCP profiles require a config DB. Start the server with: aicb mcp --db-path <db>.
```

**Inside `batch` and `measure`.** Sub-queries follow the same active pool as direct calls. A sub-query whose tool is read-only but outside the profile is refused individually with a message that names the same remedy:

```
'<tool>' IS read-only and dispatchable, but it is NOT in the active profile: <batch|measure> sub-queries follow the same active pool as tools/call, so a narrowed profile is narrowed here too (a direct call is refused by the same rule). Run list_mcp_profiles to see the profiles and their tools, then restart the server with 'aicb mcp --mcp-profile <id>' - or widen AICB_MCP_TOOLS - to expose it.
```

**Note.** A blocked call attempt is still recorded in the usage telemetry, so `usage_report` can show that an agent reached for a tool the profile did not expose.

## 12.4 The agent sent an argument name the tool does not have

This is the most dangerous MCP error class, because one of its two forms produces no error at all. An MCP client binds the arguments it recognizes and drops the rest without a word.

**Form A — the wrong name belongs to a required parameter.** The call fails, and the server makes the failure diagnosable:

```
<ExceptionType>: <cause> - This is an ARGUMENT-BINDING failure: the call never reached the tool, so retrying it unchanged fails identically. <tool> takes: <parameters, required marked>. You sent: <…>. Not a parameter of this tool: <…>.
```

If the parameter inventory cannot be read, the middle part falls back to:

```
Compare your arguments against this tool's input schema in tools/list - argument names are NOT uniform across the tool surface.
```

**Form B — the wrong name belongs to an optional parameter.** The call succeeds and answers a **different question** than the one asked. The server therefore appends a disclosure to every successful answer that contains an argument it does not declare:

```
<!-- ignored-arguments: <names> are not parameters of <tool> and had NO effect on this answer - it was computed as if they had not been sent. <tool> takes: <parameters>. -->
```

Read that comment literally: the answer is correct **for the call as it was bound**, not for the call as it was meant.

**Example.** A query that used `namespaceFilter` on `find_by_concurrency_risk` returned the solution-wide answer and reported `scope: "solution"`, including matches from the namespaces the caller believed were excluded. The parameter is called `scope`. With the correct name the same query is restricted to the intended namespace.

**What to do.** Compare the parameter names you (or your agent) sent with the ones the tool publishes. The exact inventory is in the failure message, in the `ignored-arguments` comment, or in `tools/list`. The server also accepts `symbol` as an alias for several symbol-shaped parameters, including `interfaceName`, `typeName`, `query`, `interface`, `methodName` and `method`, and rewrites it silently; `usage_report` counts those rewrites as `aliasApplied`.

**Limits of the disclosure.** Up to 8 dropped names are listed, each reduced to identifier characters and capped at 64 characters. The disclosure stays silent for a tool that is unknown or publishes no arguments — a half-known inventory would accuse the caller on the strength of a failed lookup. The failure message caps the echoed cause and the parameter inventory at 400 characters each.

## 12.5 `MCP error -32000: Connection closed`

**Symptom.** A tool call answers `MCP error -32000: Connection closed`, and the server is unreachable for the rest of the MCP session.

**What it is not.** The obvious diagnosis — "a tool exception ended the stdio loop" — is wrong. It was tested against a real server process with seven failure shapes (an unknown session, a deliberate `McpException`, an unbindable argument type, an unknown argument name, and more): every one came back as a clean error response, and the server answered a liveness probe afterwards.

**What it is.** The **channel**. stdout is the JSON-RPC transport, and a single stray write to stdout — from the product, from a dependency, from MSBuild or Roslyn during an analysis — puts a non-JSON line into the protocol stream. A strict client treats that as a protocol violation and tears the connection down. The process itself stays alive and healthy, which is why looking for a crash finds nothing.

**What the product does.** Two guards protect the channel: `Console.Out` is redirected to stderr, so no code path can put a byte into the JSON-RPC stream, and exceptions that no filter can see (thread-pool callbacks, timers, background tasks) are reported on stderr before the process ends:

```
[aicb] FATAL: unhandled exception - the aicb MCP server is terminating: <exception>
[aicb] WARNING: unobserved task exception in the aicb MCP server: <exception>
```

**What to do.** Read the **stderr log of your MCP client**. Where that log lives is decided by the client, not by `aicb`. The stray line or the exception is in it. Then restart the server and report what you found.

## 12.6 Answers describe the code as it was before your edit (staleness)

**Symptom.** The agent reports something that does not match the code you just wrote: a type is `not_found` although it is in the editor, or a fan-in count does not know a call site you just inserted. The answer carries a note — either a JSON member named `staleness` or a Markdown comment `<!-- staleness: … -->` at the top of the answer.

**The four texts.** Read the one you got; they differ in cause and remedy:

| Situation | Message (core) |
|---|---|
| The automatic re-analysis ran and succeeded | `source files had changed, so <this session> was re-analyzed automatically (incremental\|full reload) before this call was answered - this answer reflects the code as it is now` |
| The automatic re-analysis failed | `source files changed since <this session> was analyzed and the automatic re-analysis FAILED (<reason>), so this answer comes from the pre-edit graph - call refresh_session to retry it explicitly` |
| No automatic re-analysis, live session | `source files changed since <this session> was analyzed, so this answer comes from the pre-edit graph - call refresh_session for a current one` |
| No automatic re-analysis, recalled session | `source files changed since <this session> was remembered, so this answer describes the code as it was - call refresh_remembered for a live re-analysis` |

A `(last checked <timestamp>)` suffix names when the check last looked. The JSON member additionally carries `stale`, and, when an automatic refresh acted, `autoRefreshed` with `mode` (`incremental` or `full-reload`) or `autoRefreshFailed` with the failure type. A successful refresh means the answer is current — the note tells you what happened, not that something is wrong.

**The auto-refresh mode.** There are three modes, and they answer "who pays for the re-analysis":

| Mode | Behaviour |
|---|---|
| `off` | Drift is disclosed and left alone. |
| `reactive` | The server re-analyzes **before** answering, when source files have moved. This is the default. |
| `proactive` | A background watcher starts the refresh when a `.cs` file is saved, so the graph is usually current by the time a tool asks. |

The mode is set when the server starts and cannot be changed while it runs. It comes from the active MCP profile (set it in the GUI) and can be overridden for one process with `AICB_MCP_AUTO_REFRESH`: `off`, `0`, `false`, `no` for `off`; `reactive`; `proactive`, `1`, `on`, `true`, `yes` for `proactive`. An unrecognized value is ignored, so a typo never switches the mode. Note: the legacy value `true` means `proactive`.

**What to do.**

- Under `reactive` (the default), a successful automatic refresh needs no action.
- After a failed automatic refresh, call `refresh_session` explicitly.
- After a **restore or build**, call `refresh_session` with `force: true`. The file-set check reads source files and cannot see build output, so an ordinary call may legitimately answer `changed: false`. `force` costs a full reload.
- A recalled session (created with `recall_codebase`) has no live workspace, so `refresh_session` rejects it. Use `refresh_remembered` or `analyze_solution`.

**Two different staleness axes.** Distinguish them, because the remedies differ:

- **Source staleness** — `not_found` on a type you just wrote. The graph is behind your files. `refresh_session` fixes it; under `reactive` the server already did it.
- **Reference incompleteness** — a plausible but **too short** fan-in list, disclosed through `incompleteProjects`. The graph was built from source that could not resolve its references. Only this axis needs a build first, then `refresh_session(force: true)`.

`refresh_session` returns `{ changed, reason, session, mode }`. `mode` names the path taken: `incremental` means document texts were replayed into the warm snapshot without an MSBuild reload, otherwise `full-reload`. It is absent when nothing was re-analyzed.

## 12.7 A result looks wrong: the analysis run was incomplete

**Symptom.** A tool answer leads with:

```
THIS ANALYSIS RUN WAS INCOMPLETE: <n> of <m> scanned projects could not resolve their references (<up to 5 names>[, and <k> more]). <family-specific consequence> Restore/build the solution, then refresh_session and re-run this query.
```

**Cause.** Some projects could not resolve their references, usually because the solution has not been restored or built. Unresolved code still parses, so facts were produced — but the semantic edges into and out of it are missing.

**Why it matters.** The alarm rides on healthy-looking, non-empty lists as well, and that is the point: a plausible answer from an incomplete run is more dangerous than an empty one. Each query family gets its own consequence sentence, because the loss is different on each axis:

| Query family | Tools | What the caveat tells you |
|---|---|---|
| Fan-in | `find_usages`, `impact_of_change`, `find_dead_code`, `find_production_dead`, `instantiation_sites`, `lifecycle_of` | The numbers are short by an unknown number of **ordinary** references, not merely exotic ones. |
| Effects | `find_by_side_effects` | An effect is derived by propagating along call edges, so methods read as **pure** that are not. Treat the result as a floor, never as a passed purity or clean-architecture check. |
| External calls | `calls_external` | A call whose target did not resolve records no external key. An empty result is no evidence that the API goes unused. |
| Code traits | `find_by_code_traits` | `reflection` and `linq-in-loop` exist only where a target resolved; `throws` is pure syntax and unaffected. Treat a zero on the resolved traits as unmeasured. |
| Declarations | `find_implementations`, `get_type_hierarchy` | Interface and base-type identities may not bind, so declaration relationships can be missing or attached to the wrong name. |
| Resource leaks | `find_by_resource_leak` | Both the leak list **and** the `disposableCreationsChecked` denominator are short. A zero here is unmeasured, not leak-free. |
| XAML bindings | `find_unresolved_bindings` | The only axis whose loss runs in **both** directions: a count that is short, or bindings flagged that are fine. Never a clean bill and never a defect list. |
| Event subscriptions | `find_by_event_subscription` | Matches and the `availableEvents` suggestion list are both short, so the discriminator itself is unreliable. |

At most 5 project names are spelled out; the rest is summarized as `and <k> more`.

**A different zero: nothing was scanned.** This is not a run alarm — the run may be fine, the scope was empty:

```
Nothing was scanned - the scope matched no unit: a mistyped or too-deep namespace prefix, or a scope holding only test projects while includeTests is false. This zero is not a finding about any code.
```

**What to do.** Restore and build the solution, then call `refresh_session` with `force: true` and re-run the query. `get_diagnostics` shows which projects are incomplete and how many diagnostics they took with them.

## 12.8 "Unknown session" and other session-resolution failures

A failed session resolution names its actual cause. The three shapes are mutually exclusive, and only one of them is an expired session:

| What you passed | Message |
|---|---|
| A path with a solution extension, but no file there | `No solution file at '<x>'. The sessionId has a solution extension, so it was read as a path to self-initialize from - but no file exists there. Check the path (it must be ABSOLUTE), or pass a session_id returned by analyze_solution. This is NOT an expired session.` |
| An existing solution file, but this host cannot self-initialize | `'<x>' exists, but this host cannot self-initialize a session from a solution path. Call analyze_solution and pass the session_id it returns.` |
| Anything else | `'<x>' is neither a known session_id nor an absolute .sln/.slnx/.slnf path. If you meant a session_id: it is unknown or expired - call analyze_solution first. If you meant a solution: pass its ABSOLUTE .sln/.slnx/.slnf path to self-initialize.` |

Two further messages tell you the session exists but has no live workspace:

- `Session '<x>' is recalled from memory (no live Roslyn workspace). Call refresh_remembered (or analyze_solution) for a live session.`
- `Session '<x>' is no longer live (its workspace was released). Call analyze_solution again.`

**Cause of the second message.** MCP sessions expire and are evicted. Defaults: a session lives 90 minutes from its last use, at most 8 sessions are held at once (the least recently used is evicted), and a background sweep frees expired sessions every 5 minutes. You can override the three values for one server process with the environment variable `AICB_MCP_SESSION`, a comma-separated `key=value` list with the keys `ttlMinutes`, `maxSessions` and `sweepMinutes`, for example `maxSessions=4,ttlMinutes=120`. Keys that are not set keep their default; invalid or non-positive values are ignored.

## 12.9 Two analyses of the same solution at once

**Symptom.** A call hangs for a long time and then answers:

```
Gave up waiting for the solution registry after <N>s: the registry is <loading|reloading|applying edits to> '<path>', started <M>s ago. This call never started - it was queued behind that operation, so retrying now would queue again. Wait for the running load to finish, or analyze a smaller solution/filter (.slnf).
```

When a `.sln` path is passed to a tool directly (self-initialization), the equivalent message reads `Gave up waiting for the solution analysis after …`.

**Cause.** There is one gate per solution path. A second caller waits instead of starting a second analysis. The message exists because a caller sees one pending answer and cannot tell a running load from a hung server.

**What to do.** Wait — do not retry, that only queues again. For very large solutions, analyze a `.slnf` filter file instead.

**The wait is adjustable.** The bound is 45 seconds by default and can be changed with the environment variable `AICB_MCP_LOAD_WAIT_MS` (milliseconds). A zero or negative value is refused and the built-in default applies. The GUI and the CLI wait without a bound, which is intended there; only the MCP server uses this limit.

## 12.10 Database-path errors

Tools that need a database validate their `dbPath` argument and answer with one of two messages:

```
dbPath is required (<purpose>).
dbPath is a directory, expected a file: <dbPath>
```

The `purpose` clause names which database is missing, for example `the memory DB to persist into / recall from`, `the aicb DB to save into / compare against` or `the aicb config/master DB to read/write the per-solution config`. The file **need not exist** — it is created and migrated on first use. Only an empty path and a path that names a directory are rejected.

## 12.11 Self-diagnosis

### `server_info` — reachability, build commit and three drift signals

`server_info` answers in one call what the version number alone cannot. Its first line always carries the server name and version; non-release/development builds can additionally carry the **build commit**:

```
aicb MCP server (AIContextBuilder) v<version> (commit <sha>) - Roslyn-based .NET context generator. <license notice>
```

When present, the build commit answers "is the binary I am talking to built from the code I just landed?". Compare it with `git rev-parse HEAD`; the reported SHA is the full one, so a short hash is a prefix of it. Public installer, ZIP and dotnet-tool release builds deliberately omit the commit from their informational version; development builds may include it. A build without a resolvable revision omits the field rather than guessing.

If a config DB is in use, the answer continues with its schema version:

```
Config DB schema: user_version=<n> (<path>).
```

Then come up to three drift signals. They are deliberately **disjoint** — each compares a different thing and is blind to what the others see:

| Signal | Compares | Blind to |
|---|---|---|
| Staleness note in tool answers | Source files against the session | A stale binary; an incomplete analysis run |
| `CONFIG DRIFT` / `VERSION DRIFT` | Tool names and config-DB schema | A smarter fact producer under the same tool names |
| `ANALYZER DRIFT` | The server's build commit against the HEAD of the analyzed repository | Everything outside the analyzed repository |

Work through them in this order when an agent reports something implausible.

**`CONFIG DRIFT`.** The active MCP profile changed since this server started — a GUI edit in the `MCP Profiles` panel, or another process writing the config DB:

```
⚠️ CONFIG DRIFT: the active MCP profile changed since this server started - restart/reconnect the aicb MCP server to load the current configuration (tools, instructions, session auto-refresh mode). In-session the skill-derived instructions never refresh, the auto-refresh mode is fixed at start, and a GUI edit does not update the tool list until restart.
```

The same sentence appears once as a breadcrumb on stderr (`warning: aicb MCP config drift - …`), because `server_info` is a rare call. **Solution:** restart or reconnect the server.

**`VERSION DRIFT`.** This binary and the config DB disagree. Two schema variants and one tool-pool variant exist:

```
⚠️ SCHEMA DRIFT: the config DB is at schema v<N>, newer than this binary's latest known migration v<M> - the DB was migrated by a NEWER aicb build; this binary lags it. Rebuild/reinstall the standalone tool to catch up.
```

```
⚠️ PENDING MIGRATION: the config DB is at schema v<N>; this binary ships migrations up to v<M> (<k> pending) - run the app/GUI (or a --db-path start) to migrate the DB.
```

```
⚠️ TOOL POOL DRIFT: the active profile persists <k> tool name(s) this binary does not register ('<a>', '<b>', …). Two causes look identical here and the fixes are opposite: either the DB profile was written by a NEWER build (then rebuild/reinstall the standalone tool), or the tool was RETIRED and the profile still names it (then re-save the profile in the GUI's 'MCP Profiles' panel, which rewrites the selection without it - a rebuild would only repeat this message). The entry is inert either way: an unknown name is ignored when the tool set is resolved.
```

The tool-pool check works on **tool names**; a new parameter on an existing tool is invisible to it — the build commit is the finer-grained signal. Up to 10 names are listed.

**`ANALYZER DRIFT`.** The signal the other two cannot see: the build commit of this binary against the HEAD of the repository holding the analyzed solution.

```
⚠️ ANALYZER DRIFT: this binary was built from a commit <N commits BEHIND | DIVERGED from (<a> ahead, <b> behind)> the HEAD of the repo it is analyzing (<directory>) - <k> of them <touches|touch> an analyzer project. Facts the analyzer produces - fan-in, dead code, side effects - may be the OLDER analyzer's, including a zero that the newer one fills. Rebuild/reinstall the standalone tool. Neither of the other two signals can see this: the staleness trailer compares SOURCE files (unchanged here) and the version/pool check compares tool NAMES (a smarter fact producer keeps every name).
```

There are three further outcomes, and only one of them is a warning:

- `Analyzer: IN SYNC with the analyzed repo - this binary was built from the current HEAD of <directory>.`
- `Analyzer: this binary is <N commits> AHEAD of the analyzed repo's HEAD (<directory>) - built from work that repo does not have yet, so the analyzer is newer than the code, not older.`
- A behind distance where **no** intervening commit touches an analyzer project is reported quietly, with the closing sentence `The analyzer's own code is unchanged across that distance, so the facts it produces are current and this gap is no reason to rebuild.`

The analyzer drift line is silent without an analyzed session, on a repository that does not know this commit (any foreign solution), and whenever the binary has no commit id. It therefore stays silent in the public release builds that deliberately omit the commit.

### `get_diagnostics` — the fast pre-build check

`get_diagnostics` reports the compiler errors, warnings and info messages of the session's solution — the real Roslyn build output, in seconds instead of a full `dotnet build`. It is the tool to run after `refresh_session` when you want to know whether an edit broke the build.

- **Call `refresh_session` first.** The diagnostics are compiled from the session's snapshot, not from the files on disk. Under the shipped `reactive` mode the tool is refreshed for you before it answers, so the explicit call is redundant rather than wrong — and it is the only spelling that is correct in every mode. An answer computed from a graph known to be behind the disk leads with `verdict: 'stale'` and a `verdictReason` before any count.
- **Parameters.** `sessionId`, `severityFloor` (`error`, `warning` (default), `info`, `hidden`), and `scope` (`solution` by default, or a file-path substring). An unknown `severityFloor` is rejected with the valid values. `scope` filters the result, not the work: every project is compiled either way.
- **`incompleteProjects`.** A project whose compilation cannot resolve its core references is not listed in the diagnostics; it is disclosed separately, with the number of diagnostics it took with it. A freshly created, never-built worktree reports every project there — that is the honest unrestored state, not a defect. `verdict: 'inconclusive'` and `reliable: false` say so, and one `dotnet restore` or `dotnet build` makes the tool work for the rest of the session. This verdict is deliberately rare: it fires only when a strict majority of projects are incomplete.
- **Read the counts with their rules.** `incompleteRatio` and `suppressedDiagnosticsTotal` appear whenever even one project is incomplete. `suppressedDiagnosticsTotal` spans every severity and is not deduplicated, while `errorCount` counts errors only and is deduplicated across target frameworks — a total that dwarfs the visible counts means this measured a fraction of the solution.
- **Cascade diagnostics.** A project that resolves its own references but depends on an incomplete project can list `CS0012`, `CS0234`, `CS0246` or `CS0518` although it compiles fine on a real build. Such entries stay listed but are marked `cascadeFromIncomplete: true`, the response counts them as `cascadeClassifiedCount`, and each incomplete project names its `affectedDependents`. Do not read `errorCount` as "N real errors" without this.
- **Reference-binding advisories.** `CS1701`/`CS1702` ("assuming assembly reference X v1 matches X v2") are filtered out on core-resolved projects and disclosed as `referenceBindingAdvisoriesSuppressed`.
- **Live only.** Diagnostics are not persisted, so this needs a live session. A recalled session is rejected; use `refresh_remembered` for a live one. The list is capped at 200; the counts reflect the full set.
- **Compiler diagnostics only.** Third-party Roslyn analyzer diagnostics are out of scope.

### `usage_report` — what the server actually did

`usage_report` reads the server-side tool-call telemetry: every `tools/call` invocation recorded in the config DB's `tool_calls` table. It is cross-client, not a transcript of one chat.

**Read the scope first.** The recording sits on the `tools/call` pipeline only. A sub-query inside `batch` or `measure` records the parent call and no child row, and a one-shot `aicb call` records nothing at all. Every count is therefore a **lower bound**, and a tool at 0 was not called through this door rather than not called.

**Parameters.**

| Parameter | Meaning | Default / limits |
|---|---|---|
| `topTools` | Cap on the per-tool breakdown, ranked by call count. | `30`; clamped to 1..200 |
| `sinceDays` | Count only calls from the last N days; narrows every figure, and the applied cutoff comes back as `windowSinceIso`. | whole log; clamped to 1..3650 |

**What it returns.** Overall totals (calls, errors and error rate, distinct tools and sessions, first and last timestamp, the clients and server versions seen) and a per-tool breakdown: calls, errors, latency and result size, each as average, p50, p90 and maximum. The percentiles are the honest read for a right-skewed latency distribution, where one warmup call drags the average.

Several fields answer specific questions:

- `errorClasses` — the exception-type histogram behind a tool's errors. `McpException` is a **guided** failure the tool raised on purpose (an expired session, an unknown policy token); any other type is a defect suspicion worth chasing.
- `argumentBindingErrors` — how often a caller named an argument the tool does not have, so the call never reached the tool. This is neither a defect nor a refusal; it shows where a tool's argument surface confuses callers.
- `aliasApplied` — how often a tool was called with an accepted alias instead of the real parameter name.
- `protocolVersions` and `clientEras` — the share of calls per protocol revision, and an (era × client) cross-tab. A null protocol version means the row predates this instrumentation (also reported as `preInstrumentationCalls`) and belongs in the denominator; a null client name means the client did not identify itself. `clientEras` is capped at 50 groups.
- `facets` — how often each task facet was addressed. It is omitted until a call has addressed one.
- `poolCoverage` — `poolSize`, `poolToolsFired`, `poolToolsNeverCalled`, `outOfPoolCallsIncluded` and `outOfPoolTools`. Read coverage here, **not** from `distinctTools`: that figure counts every tool ever called, including tools outside the current pool and tools from earlier pools, so holding it against the pool size overstates coverage. And a name in `poolToolsNeverCalled` was never called **top-level**, which is not the same as never called.

**When telemetry is unavailable**, the answer is `available=false` with the note:

```
No telemetry available - the server is running DB-free, or the tool_calls table is not readable.
```

**Privacy note.** Exactly one telemetry field carries free text: the message of a failed exception. Set `AICB_MCP_ERROR_TEXT=off` and only the exception **type** is recorded. The error message is capped at 500 characters. Deleting the recorded data is a GUI action (the `MCP Usage` panel); there is no CLI verb for it.

### `list_skills`, `list_mcp_profiles`, `docs()` and `aicb call`

- `list_skills` is the capability map: every tool appears once in the pool groups (`inPool` or `outOfPool`). `uncatalogued` is a separate name-based section, not a third pool group; its tools can still be in either pool under an override. No profile menu names them, so only `AICB_MCP_TOOLS` can expose them.
- `list_mcp_profiles` lists the profiles, their ids, their tool selections and which one is active. It needs a config DB (see above).
- `docs()` is the server's built-in operating manual, with pages for installation, first context, tool navigation, solution configuration and the glossary.
- `aicb call <tool>` invokes one MCP tool once from a terminal, without a client — useful to reproduce what an agent reported. Example: `aicb call server_info`. It writes nothing to the usage telemetry. Long analyses print progress to stderr as `progress: …`, so stdout stays clean for the result.

## 12.12 What the server writes to stderr at startup

These lines land in your MCP client's stderr log. The server also prints a tool-curation line on every start and warns when `aicb.mcp.json` is invalid. The pinned-profile error is the only case below in which the server does not start.

| Line (core) | Meaning |
|---|---|
| `No --db-path given; using the standard config DB (same as the GUI): <path>` | Normal case, not a warning. |
| `warning: MSBuild could not be registered (<reason>). analyze_solution/refresh_session will fail; the remaining tools stay usable.` | No MSBuild on the machine. The session tools fail; the rest works. |
| `warning: standard config DB path could not be resolved (<reason>); starting DB-free (default profile's pool).` | No profile applies, but the server runs. |
| `warning: --db-path not found (<path>); starting without a profile (default profile's pool).` | A typo in the path. |
| `warning: --db-path schema migration failed (<reason>); starting without a profile.` | The database exists but cannot be migrated. |
| `warning: MCP profile resolution failed (<reason>); starting without a profile.` | The profile could not be read. |
| `warning: ... aicb.mcp.json ...` | The optional config file was unreadable or invalid; defaults remain in effect. |
| `MCP tool curation: ... active MCP profile=...; session auto-refresh=...` | The resolved tool pool/profile and auto-refresh mode for this process. |
| `error: unknown MCP profile '<id>' (--mcp-profile). Available: <list>.` followed by `error: --mcp-profile '<id>' could not be applied (see above). Refusing to start on a different profile.` | **The only case in which the server does not start** (exit code 1). An explicitly pinned profile is never silently replaced by a different one. |
| `Pinning the MCP profile to '<id>' for this process (--mcp-profile); the profile persisted in the config DB is left unchanged.` | Confirmation, not a warning. |
| `Active MCP profile: '<name>' (<id>)[ pinned via --mcp-profile; not persisted]; tool set: <spec or (lean)>; skill: <set or (none)>.` | Confirmation of what this process serves. |

**Rule of thumb.** The MCP server almost always starts — it prefers to degrade and say so. The one exception is an explicitly pinned, unknown profile.

## 12.13 Server-side guards and limits at a glance

The guards, in the order a call passes them:

1. **Load gate.** A call for a solution that is currently loading waits up to `AICB_MCP_LOAD_WAIT_MS` (default 45 s) and then reports what is holding it instead of blocking mutely.
2. **Profile guard.** A tool outside the active profile is refused with the message in "Tool `<name>` is not in the active profile". The same rule applies per sub-query inside `batch` and `measure`.
3. **Argument binding.** A missing required argument or an unknown argument name produces the binding-failure message; a dropped optional argument is disclosed on the successful answer as `ignored-arguments`.
4. **Tool failure.** Any other exception from a tool is wrapped so that its type, cause and remedy reach you instead of the bare "An error occurred invoking '<tool>'". `McpException` messages and cancellations pass through unchanged. The generic remedy is `Retry the call (optionally after refresh_session, which rebuilds the analysis); if it persists, the cause above is the thing to report.`
5. **`dbPath` guard.** Tools that need a database reject an empty path and a path that names a directory, as described above.
6. **Zero-hit steer.** A symbol query that resolves to nothing adds a `nearest` suggestion naming the closest declared symbol, so a typo is distinguishable from a real empty result. Tools that report a resolution kind use `resolvedKind: "not_found"` for the same purpose. A tool whose empty answer is a legitimate measurement (for example a complexity ranking with nothing above the floor) does not get a suggestion.

Numeric limits you may meet in practice:

| Limit | Value |
|---|---|
| Registered tools / default profile / `Full Select` | 82 / 54 / 72 tools |
| `batch` and `measure` sub-queries per call | 16 |
| `batch` response budget | ~9,000 tokens |
| Read-only tools dispatchable through `batch` and `measure` | 48 |
| Slice-tool budget (`get_context`, `explain_symbol`, `pack_for_task`, `prepare_task`) | default ceiling 10,000 tokens; an explicit `budget` is floored at 8,000 |
| Host inline rendering limit (a larger slice is written out instead of returned inline) | ~50,000 characters |
| `get_diagnostics` list | capped at 200 |
| `usage_report` `topTools` / `sinceDays` | default 30, clamped 1..200 / clamped 1..3650 |
| Incomplete-run alarm: project names spelled out | 5 |
| Dropped-argument notice: names listed / characters per name | 8 / 64 |
| Failure message: cause and parameter inventory | 400 characters each |
| Telemetry error message | 500 characters |
| Session TTL / sessions held / sweep interval | 90 minutes / 8 / 5 minutes |
| Staleness check window (how often the source check runs) | 5 seconds |
| Background-refresh debounce | 15 seconds |
| Registry load-gate wait | 45 seconds |
| `tools/list` cache lifetime | 15 minutes |

The three timing values have environment-variable overrides: `AICB_MCP_STALENESS_WINDOW_MS`, `AICB_MCP_DEBOUNCE_MS` and `AICB_MCP_LOAD_WAIT_MS`. Each takes milliseconds; a zero, a negative or an unparseable value falls back to the built-in default rather than switching the behaviour off.

---

[&larr; 11 Configuration, drift and usage recording](11-configuration-drift-and-usage-recording.md) &middot; [Contents](README.md)
