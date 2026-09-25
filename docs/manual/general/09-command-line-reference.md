[AICB – General Documentation](README.md) &middot; chapter 9 of 12

# 9 Command-line reference

`aicb` is the command-line interface of AIContextBuilder. It runs the same analysis engine as the desktop application, but writes its result to a file, reports success and failure through exit codes, and can therefore be used from scripts, build servers and other tools. It is also the way to start the MCP server and to invoke a single MCP tool without a client.

The analysis verb `analyze` needs MSBuild on the machine — a .NET SDK or Visual Studio provides it. The other verbs work without it. Self-contained publishing removes the .NET runtime dependency, not the MSBuild one.

## 9.1 Invocation, help and version

```
aicb <verb> [options]
```

| Verb | Purpose |
|---|---|
| `init` | Wire `aicb` into a project for an MCP client: the `.mcp.json` server entry, the agent skills and the symbol guard. |
| `analyze` | Run the Roslyn analysis on a solution and write the context document. |
| `export` | Re-render the context document from an existing session database, without a new analysis. |
| `import` | Import a constellation JSON (templates, presets, profiles, app settings) into a database. |
| `list` | List built-in and custom master data. |
| `mcp` | Start the MCP server over stdio. |
| `call` | Invoke exactly one MCP tool once and print its result. |

Every verb accepts `--help` (also `-h` and `-?`), which prints its options and their descriptions. `--version` prints the product version. A mistyped option name produces a suggestion, and arguments can be read from a response file (`@file`) when a command line becomes too long.

Three short option aliases exist: `-s` for `analyze --solution`, `-o` for `--output`, and `-f` for `--file`. They are not registered uniformly across verbs; in particular, `export --solution` has no `-s` alias.

Results are written to standard output; errors, warnings and notes normally go to standard error. One current exception is the multiple-installation warning from `aicb init`, which is written to standard output. Both streams are set to UTF-8 without a byte order mark at startup, so redirected output stays valid UTF-8. `aicb mcp` reserves standard output for the JSON-RPC channel and writes everything else to standard error.

## 9.2 Exit codes

The same convention applies to every verb, and it is the interface a script should key on:

| Code | Meaning |
|---|---|
| `0` | Success. |
| `1` | User error: invalid arguments, missing files, unknown ids. |
| `2` | Runtime error: an unexpected exception, or a partial import. |
| `3` | Cancelled (Ctrl+C). |
| `4` | `migration_failed`: the schema of the session or configuration database could not be migrated. |
| `5` | `msbuild_not_found`: the MSBuild bootstrap failed. |
| `6` | `quality_gate_failed`: `analyze --fail-on` matched. The Markdown is still written. |

| Verb | Codes you can receive |
|---|---|
| `init` | `0`, `1` |
| `analyze` | `0`–`6` |
| `export` | `0`, `1`, `2`, `3`, `4` |
| `import` | `0`, `1`, `2`, `3`, `4` |
| `list` | `0`, `1`, `2`, `4` |
| `mcp` | `0`, `1`, `2` |
| `call` | `0`, `1`, `2`, `3` |

`export`, `import` and `list` never return `5`, because they need no MSBuild. Only `analyze --fail-on` returns `6`, and `init` returns only `0` or `1`.

## 9.3 `aicb init`

Wires `aicb` into a project directory so that an MCP client can find it. It writes three kinds of artefact: the `.mcp.json` server entry, the agent skills under `.claude/skills/`, and the symbol guard together with the harness configuration that loads it. No database, no Roslyn and no MSBuild are involved — this is the step before any of that.

| Option | Values | Default | Meaning |
|---|---|---|---|
| `--path <dir>` | directory | current directory | The project directory to wire up. |
| `--force` | flag | off | Overwrite artefacts that are already there. Without it, an existing `aicb` entry or skill file is left untouched, which is what makes re-running safe. |
| `--skills <context\|all>` | `context` or `all` | `context` | Which agent skills to write. `context` writes the aicb-csharp-context skill only; `all` adds the aicb-code-review and aicb-code-simplifier review pair plus aicb-usage-check. |
| `--hooks <auto\|none\|all\|claude-code\|codex\|opencode>` | one of the listed values | `auto` | Which agent harnesses get the symbol guard. `auto` installs it for the harnesses already used in this project. |

Example:

```sh
cd C:\repo\MyApp
aicb init --skills=all --hooks claude-code
```

Behaviour:

- `--hooks` is validated before anything is written. An unknown value is exit `1` with the accepted values listed.
- `--path` must exist; otherwise exit `1`.
- Each artefact is reported as one line: `created`, `updated`, `kept` or `refused`, followed by the path and a short detail. If at least one artefact is refused, `init` reports an error and returns `1`. A refusal always means an existing file that `init` will not risk rewriting — an unusable `.mcp.json`, a harness wiring it cannot read, or a path it may not write — so the fix is yours: repair the file, or point `--path` elsewhere.
- When `--hooks auto` finds no harness marker in the project, no guard is installed and the command says so explicitly, together with the way to install one anyway (`--hooks claude-code|codex|opencode`, or `--hooks all`).
- Once a guard is installed it *blocks*: a C# symbol search is refused and redirected to the aicb tools. The output names, per harness, the wiring file whose `aicb` entry removes the guard again. `--hooks none` writes no enforcement on the next run; it does **not** remove an installation that is already there.
- Skills are written to `.claude/skills/` only. A harness that gets the guard but no skill is named in the output — where such a harness looks for skills has not been measured, and `init` does not guess.
- A harness that does not read the shared `.mcp.json` is named as well, because the server entry written above stays invisible to it until you add the entry to that harness's own configuration.
- If more than one `aicb` installation is found, a warning lists them: every MCP client starts the *first* one on the search path, so updating another one changes nothing a client runs. The warning names how to remove the extra installation.
- The last line is always the same reminder: `Restart or reconnect your MCP client, then call server_info to confirm it took.`

Note: `init` has no preview mode. `--force` is broader than "overwrite what is already there": it also replaces an `aicb` entry that you deliberately pointed at a wrapper script or a debug build, and it rewrites the harness wiring back to its canonical form.

Note: the harness detection on `auto` is deliberately conservative. A Claude Code user whose `.claude/` folder contains only their own `skills/` directory is not detected, because the detection must not read a marker that `init` itself created. The message `No agent harness detected here, so no symbol guard was installed.` is not a failure — pass `--hooks claude-code` explicitly.

The concepts behind these artefacts — what the symbol guard does, how the MCP client is wired, and how to remove it — are described in the MCP manual.

## 9.4 `aicb analyze`

Runs the Roslyn analysis on a solution and writes the context Markdown. Optionally it reuses a stored snapshot instead of analysing again, writes a snapshot itself, renders through a run template, and enforces a quality gate.

| Option | Alias | Required | Default | Meaning |
|---|---|---|---|---|
| `--solution <path>` | `-s` | yes | — | The `.sln` file to analyze. |
| `--output <path>` | `-o` | yes | — | Exact path of the generated `.md`. Missing parent directories are created. |
| `--session-db <path>` | | no | — | An existing SQLite session database. When its stored fingerprint matches the solution, the stored analysis is reused and the Roslyn run is skipped. |
| `--emit-session-db <path>` | | no | — | Path at which the session database is written after the run. Created if it does not exist. |
| `--force` | | no | off | Bypass the snapshot mode and always run a full Roslyn analysis. |
| `--layer-profile <path>` | | no | role-based heuristic | Path to a layer-mapping profile (JSON). |
| `--run-template <id>` | | no | full default render | Id of a run template (built-in or your own). |
| `--format <tag\|yaml>` | | no | see below | Inner notation of the `.md` file. The file name stays `.md`. |
| `--fail-on <expression>` | | no | no gate | Quality gate; exit `6` when the expression matches. |

Example:

```sh
aicb analyze -s C:/repo/App.sln -o C:/out/app-context.md \
  --emit-session-db C:/out/app.acb \
  --run-template manual-refactoring \
  --format yaml \
  --fail-on "critical>0 OR debt>120min"
```

### What a run prints

On success, standard output carries a small report. Without a stored profile:

```
No layer profile - using role-based heuristic.
Solution analyzed: MyApp
Projects: 12
Wrote context MD: C:\out\app-context.md
Session DB updated: C:\out\app.acb
```

With `--layer-profile`, the first line names the profile that was loaded. With a snapshot hit, the first line becomes `Snapshot hit (file-set hash v2:A1B2C3D4E5F60718); skipping Roslyn analysis.`, and if the emitted database is the one that was read, the last line becomes `Session DB already current; no new snapshot written.` A passing quality gate prints `Quality gate passed (--fail-on "<expression>").`

### Validation, in this order

Path, format and other inputs listed below are checked before the expensive work starts. The `--run-template` id is an exception: it is resolved after analysis, so an unknown id can fail only after the full run:

1. `--solution` is missing or does not exist → `error: solution not found: <path>`, exit `1`.
2. `--output` is missing → exit `1`.
3. `--session-db` or `--emit-session-db` is a directory → exit `1`.
4. `--session-db` is given, `--emit-session-db` is not, and the file does not exist → exit `1`, with a message naming both ways out. Reading from a cache that is not there is treated as a typo rather than silently creating the file.
5. `--output` is a directory → exit `1`.
6. The `--layer-profile` file does not exist → exit `1`.
7. `--format` is neither `tag` nor `yaml` (trimmed, case-insensitive) → exit `1`. This is deliberately strict: an unrecognized value would otherwise render the tag notation silently *and* override the format configured on the run template.
8. `--fail-on` was given without an expression (the shape a CI script produces from an unset variable) → exit `1`. An invalid expression is parsed and rejected before the analysis starts.

### The run itself

1. **MSBuild bootstrap.** If MSBuild cannot be registered, the run ends with exit `5`.
2. **Snapshot decision**, only when `--session-db` points to an existing file. The file-set fingerprint of the solution is compared against the fingerprint stored with the latest snapshot. The fingerprint covers the solution's `.cs`, `.csproj` and `.xaml` files, ignoring `bin`, `obj`, `.vs`, `node_modules`, `packages` and `TestResults`. A snapshot is reused only when it carries an analysis, was produced by a compatible version of the analysis engine (payload schema and analyzer identity), and the source files have not changed. Because the fingerprint uses file timestamps, a difference is first checked against a content fingerprint — so a branch switch or a save without a content change does not force a re-analysis. On a hit the run prints `Snapshot hit (file-set hash <hash>); skipping Roslyn analysis.` and skips Roslyn. On a miss it says why, for example:
   - `Force flag set; running full Roslyn analysis.`
   - `No usable snapshot in session DB; running full Roslyn analysis.`
   - `Snapshot payload-schema mismatch; running full Roslyn analysis.`
   - `Snapshot analyzer-identity mismatch; running full Roslyn analysis.`
   - `File-set hash drift (current <a>, snapshot <b>); running full Roslyn analysis.`
3. **Analysis.** Without a snapshot hit, Roslyn analyzes the solution. The layer profile precedence is: explicit `--layer-profile` > the default layer profile configured in the database > the `.aicb.json` file next to the solution > the role-based heuristic. Namespace exclusions from the session database or from the `.aicb.json` file are applied and announced.
4. **Render and write.** The document is written to the exact `--output` path. The output-format precedence is: explicit `--format` > the format configured on the run template > `yaml` on the template-less path. `yaml` is the product default; both notations carry the same content, and the file name stays `.md`.
5. **Emit.** With `--emit-session-db`, the analysis is stored as a snapshot carrying the file-set fingerprint, the payload-schema stamp, the code-metric roll-up and the estimated technical debt with its rating. If the emitted database is the one that was read and the run reused its snapshot, nothing is written.
6. **Quality gate**, only with `--fail-on`, and after the Markdown has been written — a failing gate still leaves you the document.

### What the output tells you about itself

The verb reports on standard error every case in which a flag has no effect or in which a configuration source other than the command line drives the run:

- `--force` without `--session-db` → `note: --force has no effect without --session-db (there is no snapshot to bypass).`
- `--layer-profile` on a snapshot hit → `note: --layer-profile is ignored on a snapshot hit; pass --force to re-analyze with it.`
- The analysis scope from the `.aicb.json` file (`analyzePreferredTfmOnly`) on a snapshot hit: the scope is not part of the file-set fingerprint, so the snapshot may have been analyzed under a different scope. Pass `--force` to re-analyze with the current one.
- Namespace exclusion patterns applied from the session database, or from the `.aicb.json` file next to the solution.
- Analysis limited to the preferred target framework per project.
- A default layer profile configured in the database drives the rendered document and the gate.
- A test profile deviating from the default drives test detection.
- Quality producers that failed and were skipped: `gate counts may be incomplete`.

### The quality gate `--fail-on`

The expression grammar is:

```
expression   := and-expression ( "OR" and-expression )*
and-expression := comparison ( "AND" comparison )*
comparison   := metric operator number [unit]
operator     := > | >= | < | <= | = | == | !=
```

Metric names and operators are case-insensitive. `AND` binds stronger than `OR`, and there are **no parentheses** — an expression such as `(critical>0 OR warning>10) AND debt>60min` is rejected as a user error (exit `1`). The number is an integer; an optional unit suffix such as `min` is accepted and ignored, so `debt>120min` means 120 minutes.

| Metric | Meaning |
|---|---|
| `critical`, `warning`, `info`, `ok` | The insight counts per severity. |
| `debt` | The estimated total remediation effort in minutes. |
| `complexity-max` | The highest cyclomatic complexity of any method. |
| `ce-max` | The highest efferent coupling of any type (its outgoing dependencies). |
| `ca-max` | The highest afferent coupling of any type (its incoming references). |
| `methods` | The number of methods. |
| `types` | The number of types. |

Both sides of an `AND` or `OR` are always evaluated, so a failing combination can name every clause that matched. Only the clauses that actually contributed are reported:

```
quality gate failed: debt>500 (--fail-on "critical>0 AND warning>10 OR debt>500").
```

The profiles the gate uses are resolved, not hard-coded: in the CLI/headless graph the active MCP profile's `TemplateId` is considered first, followed by that context template's quality-profile slot, the application setting, and the built-in default. The layer profile follows the precedence above, and the test profile is the one active in the database. Without a database, or on any failure to read one, the gate safely falls back to the built-in defaults and stays functional.

## 9.5 `aicb export`

Re-renders the context document from a persisted session database, **without** running Roslyn. No MSBuild bootstrap is involved, so exit code `5` is unreachable here.

| Option | Alias | Required | Meaning |
|---|---|---|---|
| `--session-db <path>` | | yes | The database to re-render from. |
| `--output <path>` | `-o` | yes | Exact output path. Missing parent directories are created. |
| `--run-template <id>` | | no | The same template-driven render as `analyze --run-template`. |
| `--solution <name\|path>` | | no | Selects one solution in a database that holds several. |
| `--format <tag\|yaml>` | | no | Same precedence as `analyze`. |

Example:

```sh
aicb export --session-db C:/out/app.acb -o C:/out/app-context.md --solution App
```

A session database — in particular the shared default configuration database that the desktop application fills for every loaded solution — can carry more than one analyzed solution:

- Exactly one analyzed solution → it is rendered.
- None → user error (exit `1`) with a pointer to create one first (`aicb analyze ... --emit-session-db <db>`).
- More than one **without** `--solution` → user error with a listing, never a silent guess.
- `--solution` prefers exact matches: the full canonical path, the solution name (file name without `.sln`), or the file name, all case-insensitive. Only when there is no exact match does it fall back to a case-insensitive substring match on the path — so `App` matches `App` and not also `AppCore`. A selector that matches several entries is an error with the matches listed.

On success it prints:

```
Re-rendered from session DB (no Roslyn): C:\repo\App.sln
Projects: 12
Wrote context MD: C:\out\app-context.md
```

## 9.6 `aicb import`

Imports a constellation JSON — a bundle of templates, presets, profiles and app-settings keys — into a target SQLite database. Three phases: read, preview, apply. No Roslyn and no MSBuild.

| Option | Alias | Required | Default | Meaning |
|---|---|---|---|---|
| `--file <path>` | `-f` | yes | — | The constellation JSON file to import. |
| `--db-path <path>` | | yes | — | The target database: the master-entity/configuration database, explicitly **not** a session snapshot database. Created if it does not exist. |
| `--mode <SkipExisting\|Replace>` | | no | `SkipExisting` | Behaviour on id conflicts. `SkipExisting` leaves existing entries untouched; `Replace` overwrites them. Parsed case-insensitively; an empty value counts as `SkipExisting`. |
| `--preview` | | no | off | Dry run: show the preview and write nothing. |

Example:

```sh
aicb import -f C:/share/team-constellation.json --db-path C:/out/app.acb --mode Replace --preview
```

Behaviour:

- The per-section preview is printed **always**, with or without `--preview`:
  ```
  Preview for 'Team defaults':
    RunTemplate: new=2, conflicts=1, unchanged=3, skipped-built-in=4
    app-settings keys: 2
  ```
- `--preview` stops after the preview and writes nothing.
- If the file carries app-settings keys, a note on standard error points out that their JSON-backed values can also touch the global app-settings file.
- The import is **not transactional**. Per-item errors are collected and reported as warnings, and the exit code becomes `2` so that a script can detect a partial import. A fully successful import prints `Imported into <path>: applied=<n>, skipped=<n>, app-settings-keys=<n>.`

## 9.7 `aicb list`

Lists built-in and custom master data. This verb is read-only; there is no verb that creates, changes or deletes master data.

| Parameter | Required | Meaning |
|---|---|---|
| `kind` (positional) | yes | The master-entity type to list — see the table below. |
| `--json` | no | JSON instead of the table. |
| `--db-path <path>` | no | Source database. Without it, only the built-ins are listed. |

The fourteen kinds (compared case-insensitively):

| Kind | Content |
|---|---|
| `run-templates` | Run templates. |
| `detail-presets` | Detail presets. |
| `model-profiles` | Model profiles. |
| `prompts` | Prompts. |
| `md-profiles` | Markdown profiles. |
| `tag-schemata` | Tag schemata. |
| `test-descriptions` | Test descriptions. |
| `context-templates` | Context templates. |
| `expansion-strategies` | Expansion strategies. |
| `pipeline-profiles` | Pipeline profiles. |
| `quality-profiles` | Quality profiles. |
| `mcp-profiles` | MCP profiles. |
| `test-profiles` | Test profiles. |
| `compression-rules` | Compression rules. |

Examples:

```sh
aicb list run-templates --db-path C:/out/app.acb
aicb list mcp-profiles --json
```

Behaviour:

- Without `--db-path`, a throwaway database is created in a temporary directory, migrated and deleted afterwards, so only the built-in entries appear. The table header then says `(built-ins only - pass --db-path to include custom)`.
- `--db-path` must point to an existing file. Unlike `import --db-path`, `list` does not create it.
- The table is one line per entry: two spaces, the id, `  -  `, the name, and the flags in brackets — `built-in` or `custom`, extended by `, overridden` and `, hidden` where they apply. Rows are sorted by id (case-insensitive) so the output is stable and column-aligned. A closing line states the counts, for example `14 entries (9 built-in, 5 custom).`
- `--json` prints a JSON array of objects with the keys `Id`, `Name`, `IsBuiltIn`, `IsOverridden` and `IsHidden`.
- An unknown kind is exit `1` and prints the full list of valid kinds.

## 9.8 `aicb mcp`

Starts the MCP server: Model Context Protocol over stdio JSON-RPC, for Claude Code, Cursor, Cline and other MCP clients. The server concepts — profiles, tool pools, sessions and the agent artefacts — are described in the MCP manual; this section covers the command's options and runtime behaviour.

| Option | Required | Default | Meaning |
|---|---|---|---|
| `--db-path <path>` | no | the standard configuration database is resolved automatically | The master/configuration database. With it the server is profile-aware: rendering follows the active MCP profile, the exposed tool set follows its selection, and its skill shapes the server instructions. |
| `--mcp-profile <id>` | no | the profile stored as active in the configuration database | Pins the active MCP profile for this server process only. |

Example:

```sh
aicb mcp --db-path "%APPDATA%\AIContextBuilder\user-data\aicb.acb" --mcp-profile mcp-profile/full
```

Behaviour:

- **Standard output is reserved for the protocol.** Everything this verb prints goes to standard error.
- Without `--db-path`, the standard configuration database — the same one the desktop application uses, `%APPDATA%\AIContextBuilder\user-data\aicb.acb` — is resolved and, on first start, created and migrated. Which database is in effect is always announced on standard error, never silently. If that resolution fails, the server warns and starts without a profile.
- An explicitly given `--db-path` that does not exist is a **warning**, not a silent creation: a typo must not produce a new database. An automatically resolved standard database *is* created on first start.
- A failed schema migration is a warning, and the server starts without a profile.
- `--mcp-profile` is the one rule of this verb that does not fail open. An unknown or hidden profile id, a missing configuration database or file, or a failed migration makes the server **refuse to start** with exit `1`, listing the valid ids on standard error. Serving a different profile than the operator asked for — silently, over stdio, where nobody reads a warning — is the failure this prevents. The pin is process-local and writes nothing back: a second server or the desktop application keeps its own active profile.
- On a successful profile resolution, the server reports on standard error which profile it serves, whether it was pinned, the effective tool set and whether a skill is attached.
- A failure to register MSBuild is not fatal: a warning is printed, `analyze_solution` and `refresh_session` will fail, and the remaining tools stay usable.
- The server watches two kinds of drift: a configuration drift (a profile edited in the desktop application while this server runs is detected and reported on `server_info`; restart or reconnect the server to load it) and a version drift (this binary compared against the database it read, reported on `server_info`).
- Every MCP tool call is recorded in the `tool_calls` table of the configuration database, fail-open. A server started without a database records nothing.
- The server has **no** `--solution` option: the solution comes with each tool call, and a `.sln` path passed to a session-taking tool initializes the session on first use.
- One binary serves both current MCP protocol revisions over stdio: `2026-07-28` via `server/discover` (stateless) and `2025-11-25` via the `initialize` handshake. Only stdio is supported — there is no HTTP or SSE transport, so session headers, resumability and OAuth of the newer revision do not apply here.

## 9.9 `aicb call`

Invokes **one** MCP tool exactly once and prints its result. No server, no client, no JSON-RPC handshake. This is useful for validating a tool live after an update, and as a plain shell one-liner.

| Parameter | Required | Meaning |
|---|---|---|
| `tool` (positional) | yes | The MCP tool name, for example `find_usages`, `server_info` or `batch`. |
| `--sln <path>` | no | An absolute `.sln` path. It is bound to the tool's `sessionId`/`solutionPath` argument and analyzes the solution once (self-init). Omit it for a tool that needs no session, such as `server_info`. |
| `--arg <name=value>` | no, repeatable | One tool argument per occurrence. |
| `--db-path <path>` | no | An optional configuration database. Without it the tool runs database-free. |

Examples:

```sh
aicb call server_info
aicb call find_usages --sln C:/repo/App.sln --arg symbol=OrderService
aicb call find_by_side_effects --sln C:/repo/App.sln --arg effect=io --arg includeTests=true
aicb call batch --sln C:/repo/App.sln --arg queries='[{"tool":"find_usages","args":{"symbol":"Foo"}}]'
```

Behaviour:

- Each value needs its own `--arg`; a single `--arg` token carries exactly one `name=value` pair. A token without `=`, or with an empty name, is a user error (exit `1`). Repeated names: the last one wins.
- Values are converted to the parameter type: `bool`, `int`, `long`, `double`, enums (case-insensitive) and string arrays. A string array is written as a JSON array or as a comma-separated list. Any other, complex argument is passed as JSON.
- Numbers are read with the invariant culture: `.` is the decimal separator, not `,`. A value such as `0,6` is rejected with a message that names the cause and the fix.
- Dispatch is generic over the registered MCP tools, so a tool that was just added is callable as soon as it ships, and **every** tool is reachable — including tools outside the default profile's pool and tools that write, such as `install_agent_hooks`. This is the one place where the profile's tool selection does not restrict you; use it deliberately.
- `--db-path` applies the same configuration as `aicb mcp --db-path`, so database-defaulting tools and the self-init pick up the per-solution configuration of the desktop application.
- Standard output carries the tool result, so it can be piped or redirected; diagnostics go to standard error.
- An unknown tool or a missing or invalid argument is reported as the tool's own message, exit `1`. Any other unexpected failure is exit `2`.
- A failure to register MSBuild is only a warning; tools that need no solution still run.

## 9.10 Environment variables

The following variables are read by the shipped product. Set them for the process that starts the server; they do not persist anywhere.

```sh
# Windows (PowerShell)
$env:AICB_MCP_TOOLS = "all"

# Linux / macOS
export AICB_MCP_TOOLS=all
```

| Variable | Values | Default | Effect |
|---|---|---|---|
| `AICB_MCP_TOOLS` | `all`, `lean`, empty, or a selection list | the active MCP profile's tool pool | Assembly-wide tool curation: which tool groups the server exposes. `all` also exposes the opt-in infrastructure tools (session, memory, DB-entity and API-compatibility tools) that no profile menu lists. Literal `lean` selects the complete 72-tool lean core. Empty or unset means no override, so the active profile decides (54 tools in the default profile). A selection list is either a comma-separated list of tool-group names or the `methods:<tool>,<tool>` form naming individual tools. Unknown group names are ignored and a group list with no matches falls back to the lean core; a `methods:` list is used literally, so unknown names can produce an empty tool set and do not trigger that fallback. An explicit spec is static: it does not change when a profile is switched. |
| `AICB_MCP_SESSION` | comma-separated `key=value`, keys `ttlMinutes`, `maxSessions`, `sweepMinutes` | TTL 90 minutes, at most 8 sessions, sweep every 5 minutes | Fine-tuning of the in-memory session cache. The TTL is sliding: every tool access resets the clock. The session limit is the hard memory bound; on overflow the least recently used session is evicted. Invalid or non-positive values are ignored per key, and unset keys keep their default. |
| `AICB_MCP_AUTO_REFRESH` | `Off`/`0`/`false`/`no`, `Reactive`, `Proactive`/`1`/`on`/`true`/`yes` | the active profile's value; profiles the product creates use `Reactive` | Whether a stale MCP session is re-analyzed before a read tool answers, and whether file watchers are armed. `Reactive` repairs a drifted session when a question arrives; `Proactive` additionally watches the solution folder in the background. Missing, empty or unrecognized values mean no override. See "Sessions and staleness" in the MCP manual for the modes. |
| `AICB_MCP_DEBOUNCE_MS` | positive integer (milliseconds) | 15000 (15 seconds) | Debounce of the file watcher in `Proactive` mode: how long the watcher waits for quiet before it refreshes. |
| `AICB_MCP_STALENESS_WINDOW_MS` | positive integer (milliseconds) | 5000 (5 seconds) | Throttle window of the staleness check, so a burst of tool calls does not repeat the directory walk for each one. |
| `AICB_MCP_LOAD_WAIT_MS` | positive integer (milliseconds) | 45000 (45 seconds) | How long a tool call waits at the solution registry's load gate before it is told what is holding it up, instead of blocking. Only the MCP server applies this bound; the desktop application and the other CLI verbs wait without one. |
| `APPDATA` | a directory path | the platform's application-data folder | The root of `%APPDATA%\AIContextBuilder`, from which every settings and database path is derived. An explicitly set value wins on all platforms. On Linux and macOS the same expansion resolves `%VAR%` tokens and converts `\` to `/`. |
| `DOTNET_gcServer` | `0` disables the server garbage collector | server GC is on | The product's builds enable the server garbage collector, and the packed tool carries that setting with it. Setting this variable to `0` turns it off for one process — the environment variable beats the build setting. Use it on a memory-constrained machine. |

### `aicb.mcp.json`

`aicb.mcp.json` is the file-based twin of the two MCP environment variables. It lives in the user configuration directory — `<ApplicationData>/AIContextBuilder/aicb.mcp.json`, on Windows `%APPDATA%\AIContextBuilder\aicb.mcp.json` — and is intended for headless operation without the desktop application.

It is **hand-written and only read**; the server never writes it. Do not confuse it with the `.mcp.json` in your project directory, which `aicb init` writes.

All fields are optional; a field that is not set means "no override". Precedence is: built-in defaults < `aicb.mcp.json` < environment variable. The environment variables remain the quick operator override.

```json
{
  "toolSpec": "all",
  "sessionCache": { "ttlMinutes": 120, "maxSessions": 4 }
}
```

- `toolSpec` uses the same grammar as `AICB_MCP_TOOLS`.
- `sessionCache` accepts `ttlMinutes`, `maxSessions` and `sweepMinutes`; only set, positive values are applied.
- The file is read fail-open: if it is missing, unreadable or malformed, the server starts on the built-in defaults and logs a warning. That warning is the only thing that distinguishes a broken file from a missing one, so check the server's standard error if a setting appears to have no effect.
- Parsing is case-insensitive and tolerates comments and trailing commas, because the file is written by hand.

## 9.11 Typical headless workflows

### Analyze a solution

```sh
aicb analyze --solution C:/repo/App.sln --output C:/out/app-context.md
```

`--solution` and `--output` are required. All inputs are validated before the analysis starts, so a mistyped path is reported immediately as a user error (exit `1`) rather than after a full run.

### Analyze once, reuse the analysis

Store the analysis in a session database and let later runs reuse it while the source files are unchanged:

```sh
# First run: analyze and store the result
aicb analyze -s C:/repo/App.sln -o C:/out/app-context.md --emit-session-db C:/out/app.acb

# Later runs: reuse the stored analysis when the sources are unchanged
aicb analyze -s C:/repo/App.sln -o C:/out/app-context.md --session-db C:/out/app.acb
```

A run that hits the snapshot prints `Snapshot hit (file-set hash <hash>); skipping Roslyn analysis.` and skips the expensive step. Pass `--force` when you want to re-analyze even though the snapshot matches — for example after passing a different `--layer-profile`, which is ignored on a snapshot hit.

### Re-render without a new analysis

When only the notation or the run template changes, re-render from the stored database:

```sh
aicb export --session-db C:/out/app.acb -o C:/out/app-context.md --format tag
aicb export --session-db C:/out/app.acb -o C:/out/app-context.md --run-template manual-refactoring
```

`export` runs no Roslyn and needs no MSBuild. It renders the most recent snapshot of each analyzed solution in the database.

The shared database of the desktop application can contain several analyzed solutions. Name the one you want:

```sh
aicb export --session-db "%APPDATA%\AIContextBuilder\user-data\aicb.acb" --solution App -o app.md
```

Without `--solution`, a database with more than one analyzed solution is a user error with a listing — the tool never guesses.

### A quality gate in CI

```sh
aicb analyze \
  --solution App.sln \
  --output artifacts/context.md \
  --emit-session-db artifacts/context.acb \
  --fail-on "critical>0 OR debt>120min"
```

The Markdown is written before the gate is evaluated, so a failing gate still leaves you the document for the build artifacts. Only the exit code changes to `6`.

A shell script can distinguish the outcomes precisely:

```sh
aicb analyze -s App.sln -o context.md --fail-on "critical>0 OR debt>120min"
status=$?
case $status in
  0) echo "analysis complete, gate passed" ;;
  6) echo "gate violated - context.md was still written" ;;
  1) echo "bad invocation - fix the arguments" ;;
  5) echo "MSBuild not found on this machine" ;;
  *) echo "aicb failed with exit code $status" ;;
esac
```

The same gate as a GitHub Actions step:

```yaml
- name: Analyze and enforce the quality gate
  run: |
    aicb analyze \
      --solution MyApp.sln \
      --output artifacts/context.md \
      --emit-session-db artifacts/context.acb \
      --fail-on "critical>0 OR debt>120min"

- name: Upload the context document
  if: always()
  uses: actions/upload-artifact@v4
  with:
    name: aicb-context
    path: artifacts/context.md
```

`if: always()` is what makes the second step run even when the gate failed — the document exists in both cases.

### Analyze several solutions in a loop

```sh
for sln in src/*.sln; do
  name=$(basename "$sln" .sln)
  aicb analyze -s "$sln" -o "out/$name.md" --emit-session-db "out/$name.acb" || exit $?
done
```

Each solution gets its own document and its own session database. The exit code is propagated, so the loop stops at the first failure.

### Query the code from a shell

`aicb call` answers a single question without starting a server:

```sh
aicb call find_usages --sln C:/repo/App.sln --arg symbol=OrderService
aicb call get_diagnostics --sln C:/repo/App.sln --arg severityFloor=error
```

The result goes to standard output and can be piped or captured. The command reaches every MCP tool, including ones outside the default tool pool.

### What the command line does not do

The CLI is the tool for repeating and automating; the desktop application is the tool for choosing and curating. The following exist only in the desktop application and have no CLI equivalent:

- Creating, editing or deleting master data. `aicb list` is read-only; to bring master data in, create it in the application or import a constellation JSON with `aicb import`.
- LLM runs (sending a document to a model) and their results.
- The interactive selection tree, detail levels and section selection, and the prompt context (role, goal, constraints).
- Switching the active database and managing sessions and snapshots interactively.
- Exporting a constellation. Importing one works from both sides; exporting it is only available in the application.

Both sides meet in the database and in the render path: a solution analyzed in the application can be re-rendered with `aicb export`.

---

[&larr; 8 Insights: the code quality catalog](08-insights-the-code-quality-catalog.md) &middot; [Contents](README.md) &middot; [10 Data, storage and privacy &rarr;](10-data-storage-and-privacy.md)
