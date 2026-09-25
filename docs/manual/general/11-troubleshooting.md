[AICB – General Documentation](README.md) &middot; chapter 11 of 12

# 11 Troubleshooting

This chapter lists the problems you are most likely to meet, what causes them, and what to do about them. Each entry names the symptom exactly as it appears on screen, because the fastest way to use the chapter is to search it for the message you are looking at.

Two areas have their own manuals: problems that belong to the MCP server (tool pools, sessions, drift) are described in the MCP manual, and problems that belong to the desktop application's panels and editors are described in the desktop application manual. The entries below are the ones that apply to the product as a whole.

## 11.1 Startup and installation

### `MSBuild not found` — the application does not start

**Symptom.** A dialog titled `MSBuild not found` appears, and after you close it the application exits with exit code `1`.

```
AIContextBuilder could not find a compatible MSBuild installation.

Tried:
  - MSBuildLocator.RegisterDefaults
  - MSBuildLocator.QueryVisualStudioInstances
  - vswhere.exe -> VS\MSBuild\Current\Bin
  - Newest .NET SDK in %ProgramFiles%\dotnet\sdk

Possible causes:
  - Visual Studio is installed, but the '.NET desktop development' or 'MSBuild Tools' workload is missing.
  - Neither VS nor a .NET SDK is installed.

Diagnostics (in a PowerShell):
  & "C:\Program Files (x86)\Microsoft Visual Studio\Installer\vswhere.exe" -latest -products * -requires Microsoft.Component.MSBuild -property installationPath
  dotnet --list-sdks

The application will exit.
```

**Cause.** To load a C# solution, the application needs an MSBuild installation, which comes either with a .NET SDK or with Visual Studio. It tries four routes in this order: the locator's default discovery, the newest Visual Studio instance the locator knows, `vswhere.exe`, and the newest .NET SDK under `%ProgramFiles%\dotnet\sdk`. The last three are Windows-only. If all four fail, there is no analysis workspace and the application cannot continue.

**What to do.** Install a .NET **SDK** (not just the runtime), or Visual Studio with the `.NET desktop development` or `MSBuild Tools` workload. The two commands printed in the dialog tell you what the machine currently has:

| Command | What it shows |
|---|---|
| `& "C:\Program Files (x86)\Microsoft Visual Studio\Installer\vswhere.exe" -latest -products * -requires Microsoft.Component.MSBuild -property installationPath` | the installation path of the newest Visual Studio that has the MSBuild component |
| `dotnet --list-sdks` | every .NET SDK installed on the machine |

Note: a self-contained installation removes the dependency on the .NET **runtime**, not the dependency on MSBuild. See "License, installation and updates".

### The same problem on the command line

`aicb analyze` stops with exit code `5` and writes to stderr:

```
error: MSBuild registration failed on <platform>: <reason>. Make sure the .NET 8 SDK is installed and reachable via 'dotnet --info'. On Windows a global.json next to the .sln can help disambiguate SDK versions.
```

The CLI uses only the first of the four routes, so on Windows the message points at the SDK rather than at Visual Studio.

`aicb mcp` and `aicb call` do **not** stop. `aicb mcp` starts with this warning on stderr:

```
warning: MSBuild could not be registered (<reason>). analyze_solution/refresh_session will fail; the remaining tools stay usable.
```

`aicb call` uses a different warning because it can invoke session-less tools directly:

```
warning: MSBuild could not be registered (<reason>). Tools that analyze a solution (self-init / analyze_solution) will fail; others still run.
```

That warning is a prediction, not a startup failure: the tools that need a loaded solution (`analyze_solution`, `refresh_session`) fail later, while database-bound queries, `server_info` and `docs` keep working. The remedy is the same as above.

### Do you need the .NET runtime?

| Installation form | Needs the .NET runtime? |
|---|---|
| Setup installer (Windows) | No — self-contained, the runtime is included |
| ZIP archive (Windows) | No — self-contained |
| `dotnet tool install -g AIContextBuilder` | Yes — a .NET tool is framework-dependent and needs the .NET 8 SDK, which is also what analyzing a solution needs |

### Windows SmartScreen warns about the download

**Symptom.** On first start of the installer or of the unpacked `aicb-ui.exe`, Windows shows "Windows protected your PC" and blocks the file.

**Cause.** The delivered files are not code-signed.

**What to do.** Choose `More info` and then `Run anyway`. The same instruction is in `LIESMICH.txt` next to the unpacked files and in the README of the public repository; every release also lists SHA-256 checksums for its files.

### `Database is newer than this build`

**Symptom.** A dialog titled `Database is newer than this build` appears and the application exits with exit code `2`.

```
This database was written by a newer version of AIContextBuilder.

Database schema: <N>
This build knows: <M>

The application will exit rather than write to it, because an older
build would silently save the outdated shape back. Update
AIContextBuilder, or point the database path in the app settings
(Storage) at a different file.
```

**Cause.** The database was written by a newer version than the one you just started. The usual way this happens is two installations side by side: an unpacked ZIP that is newer than the installed version was started once and upgraded the shared database under `%APPDATA%\AIContextBuilder\`. Schema upgrades are one-way; a newer database cannot be downgraded.

**What to do.** Either bring the older installation to the same version, or choose a different database path under `Settings > Storage`. A newly chosen path starts with an empty database. See also "Data, storage and privacy".

Note: only the desktop application refuses to start. The MCP server tolerates a newer database and reports the difference through `server_info`; the CLI verbs neither refuse nor report it.

| Host | Behavior with a database that is newer than the build |
|---|---|
| Desktop application | Dialog `Database is newer than this build`, exit code `2` |
| MCP server (`aicb mcp`) | Starts anyway; reports the drift through `server_info` |
| CLI verbs (`aicb analyze`, `aicb export`, …) | Neither refuses nor reports |

The same check applies when you switch databases in the desktop application: `Target DB schema version <N> is newer than this app's latest (<M>). Upgrade the app or pick a different DB.`

### `Database migration failed`

**Symptom.** A dialog titled `Database migration failed` appears and the application exits with exit code `2`.

```
AIContextBuilder could not update the database schema.

Error: <message>

The application will exit. Verify that the database path in the
app settings (Storage) is reachable and writable.
```

**Cause.** The schema migration could not be completed — for example the path is unreachable, the file is read-only, the file is not a valid database, or a migration committed and the follow-up foreign-key check found violations:

```
Schema migration v<N> committed but PRAGMA foreign_key_check reported <K> violation(s). Inspect the DB and decide whether to delete the offending rows or restore missing parent rows. First few rows: <table#rowid->parent>; …
```

**What to do.** Check the database path under `Settings > Storage` and make sure the folder is reachable and writable. If another program (typically a backup tool) is holding the file, close it and start the application again. If the message reports foreign-key violations, keep a copy of the database and contact support (see the Support section below).

### `'…' is not an AIContextBuilder database`

**Symptom.** When you switch or create a database, or start with a manually edited path:

```
'<path>' is not an AIContextBuilder database: the file must end in '.acb'. Rename it (and point Storage.DatabasePath at the renamed file), or pick a '.acb' file.
```

**Cause.** The application's own database must end in `.acb`; the default is `aicb.acb` under `<BasePath>\user-data`. The rule exists so that one SQLite file cannot be used under two names by two parts of the product, which would look like data that comes and goes.

**What to do.** Rename the file so that it ends in `.acb` and point `Storage.DatabasePath` in `%APPDATA%\AIContextBuilder\app-settings.json` at the renamed file — or pick an existing `.acb` file in the dialog. The file dialog deliberately offers only `.acb`.

Note: a database path that you pass explicitly to a CLI verb or to an MCP tool is not checked against this rule; there you are naming a specific existing file on purpose.

### The settings file could not be read

**Symptom.** The application starts normally, but the database path, the base path and the lists of recently opened solutions and databases are back at their defaults, and a notice bar appears at the top of the window:

```
Application settings - Your settings file could not be read, so this session is running on DEFAULTS - including the database path, which is why your sessions and solutions may look missing (<reason>). A copy of it is preserved at <path>.
```

**Cause.** `%APPDATA%\AIContextBuilder\app-settings.json` could not be parsed (or could not be opened at all). Because that file also carries the database path, the application then runs against the default database — which is why your sessions, solutions and runs appear to be gone. They are not: only the pointer to them was lost.

**What to do.**

1. Open `%APPDATA%\AIContextBuilder\app-settings.json` and restore the `Storage.DatabasePath` value, or select the old database again under `Settings > Storage`.
2. The unreadable file is preserved next to itself as `app-settings.json.corrupt-<timestamp>`. If the notice says that no copy could be made, copy the file elsewhere before you open a solution, because opening a solution rewrites the settings file from the defaults.

If the file could not even be opened, the notice reads `Application settings - Your settings file could not be opened (<reason>), so this session may be running on DEFAULTS - including the database path.`

### The start takes a long time

**Symptom.** Several seconds pass after you start the application before a window appears.

**Cause.** The windowless part of the startup does the work before the main window exists; a splash screen is shown on its own thread while it runs. The one case that can turn seconds into a long wait is the automatic backup: if it is enabled (default: off) and its interval has elapsed, it runs synchronously before any window is created. With a large base path and a large database this can add tens of seconds. A **failed** backup run does not advance its timestamp, so the delay repeats on every start until the cause is fixed.

**What to do.** Wait for the window. If the delay repeats, read the startup notice bar — it names the reason (see "Automatic backup reports"). If you do not need the automatic backup, switch it off under `Settings > Storage`.

### `Unfinished runs from previous session`

**Symptom.** At startup a dialog appears with three buttons:

```
During the previous app session, <N> run(s) did not finish cleanly:

  - <name> (<type>, started <yyyy-MM-dd HH:mm>)
  ... and N more

What should happen with them?
  Yes       = Mark as Cancelled (close cleanly)
  No        = Pause for later resume
  Cancel    = Leave unchanged (decide later)
```

**Cause.** Runs that were still marked as running when the previous session ended — typically after a crash, a hard kill or a power loss.

**What to do.** `No` is the least lossy choice if you still care about the run: it is paused so you can resume it later. `Yes` closes it cleanly as Cancelled. `Cancel` (or closing the dialog) leaves everything as it is and asks again at the next start. The list shows at most five entries; the rest are summarized as `... and N more`.

If the recovery itself fails, a warning titled `Crash recovery` appears and the application starts anyway:

```
Crash recovery failed.

Error: <message>

The app will start anyway; unfinished runs remain with status=Running.
```

Note: `Iteration` and `Preselection` run templates are not yet released — only `Manual` templates can be selected. The recovery dialog concerns runs of any type that were left running.

## 11.2 Analyzing a solution

### `error: solution not found` / `Solution file not found`

**Symptom (CLI).** `error: solution not found: <path>` on stderr, exit code `1`.

**Symptom (desktop application).** A dialog titled `Open solution`:

```
Solution file not found:
<path>
```

**Cause.** The given path does not exist. The desktop application shows this dialog only when the solution is unknown to it; a known solution whose file has moved offers to relocate it instead (next entry).

**What to do.** Check the path, the drive letter and the file name. If the solution was moved, see the next entry.

### The solution has moved

**Symptom.** When you open a known solution or a stored session, a relocate dialog appears. It shows the old path and asks you to pick the new location.

**Cause.** The stored solution path no longer exists — typical when a database was carried to another machine, or after a folder was renamed.

**What to do.** Point the dialog at the solution's new location and confirm. The application updates its record and continues opening. The same dialog is used when you open a stored session whose solution has moved.

Follow-up messages you may see:

| Message | Title |
|---|---|
| `Solution file still not accessible at:\n<path>` | `Open solution` |
| the error of the failed database update | `Relocate solution` |
| `Session no longer exists.` | `Open Session` |
| `The associated solution could not be found.` | `Open Session` |

### The solution was never built — the most important case

**Symptom.** Answers come back and look plausible, but they are too small. Typical examples:

- A side-effect query (`find_by_side_effects`) answers `count: 0` while its own `methodsScanned` counter reports thousands of methods — which reads like a passed architecture check.
- An external-call query (`calls_external`) answers zero for an API the solution obviously uses, for example `System.IO.File` in a solution whose job is writing files.
- `get_diagnostics` lists every project under `incompleteProjects`.

**Cause.** Roslyn cannot resolve the projects' references: no `obj/` folder, no NuGet restore, or a missing targeting pack for the target framework. Unresolved code still parses, so facts are produced — but without the call edges and type identities the answers are derived from. Nothing looks broken; the numbers are simply wrong.

**How the application tells you.** Every affected answer carries an alarm that qualifies the **run**, not the individual answer — so it also appears over a healthy-looking, non-empty list:

```
THIS ANALYSIS RUN WAS INCOMPLETE: <k> of <n> scanned projects could not resolve their references (<names>, and <r> more). <consequence> Restore/build the solution, then refresh_session and re-run this query.
```

The middle sentence is worded per question family, because something different breaks in each case:

| Question family | What the alarm tells you |
|---|---|
| Fan-in, dead code, instantiation | The numbers are short by an unknown number of **ordinary** references, not merely exotic ones |
| Side effects and external calls | Effects are derived by propagating along call edges, so a method whose calls did not resolve is reported as **pure** — treat the result as a floor, never as a passed purity or clean-architecture check |
| Resource leaks | Both the leak list and the count of creations checked are short — treat a zero here as unmeasured, never as leak-free code |
| XAML bindings | Breaks in **both** directions: an unresolved scope is silently skipped (under-reporting), while a view model whose generated members did not bind looks checkable but is not (false reports) |
| Event subscriptions | A subscription is recorded only where the left-hand side resolved to an event, so both the matches and the `availableEvents` list are short — treat an empty list as unmeasured, never as an absence |
| Code traits, interface and base-type relationships | The resolved traits (`reflection`, `linq-in-loop`) and the declaration relationships can be missing or attached to the wrong candidate — treat them as partial evidence |

If a query's scope matched nothing at all, the answer says so instead:

```
Nothing was scanned - the scope matched no unit: a mistyped or too-deep namespace prefix, or a scope holding only test projects while includeTests is false. This zero is not a finding about any code.
```

**What to do.**

1. Build the solution once, from the command line in the solution's directory:

```sh
dotnet restore
dotnet build
```

2. Tell the session about it: call `refresh_session` (MCP), or load the solution again in the desktop application.
3. Repeat the query. `get_diagnostics` is the fastest check that the run is now complete: `incompleteProjects` should be empty.

Note: a freshly cloned repository is the most common case. If the solution cannot be built on your machine (a missing targeting pack, for example), the alarm stays — and the answers stay marked as incomplete, which is exactly what the marking is for.

### What `incompleteProjects` means for a number

**Symptom.** `get_diagnostics` reports `errorCount` — possibly a large one, possibly a suspiciously small one — next to `incompleteProjects`, `incompleteRatio` and `suppressedDiagnosticsTotal`.

**Cause and meaning.** A project whose core references do not resolve (for example `System.Object` is missing because a targeting pack is not installed, or the project is not restored) would produce thousands of cascade errors (`CS0518`, `CS0234`, `CS0246`). Such projects are therefore not listed as diagnostics; they are disclosed separately under `incompleteProjects`, each with the project name and the number of diagnostics that were suppressed with it. The counts around them mean different things:

| Field | Meaning |
|---|---|
| `errorCount` | Errors only, deduplicated across target frameworks |
| `suppressedDiagnosticsTotal` | Everything from the chosen severity floor upward that the incomplete projects contributed, **not** deduplicated — a multi-targeted project counts once per target framework. Read it as a magnitude, not as one half of a ratio with `errorCount`: a total that dwarfs `errorCount + warningCount + infoCount` means that only a fraction of the solution was measured |
| `cascadeClassifiedCount` | Diagnostics from projects that **do** resolve but inherit broken references from an incomplete project. They are never filtered away; they are marked `cascadeFromIncomplete: true`, and each `incompleteProjects` entry names its `affectedDependents` (transitively) |
| `referenceBindingAdvisoriesSuppressed` | `CS1701`/`CS1702` assembly-version advisories without a source location; they cannot be fixed from source and are filtered out |
| `verdict: 'inconclusive'`, `reliable: false` | Set only when a strict majority of the scanned projects are incomplete. The disclosure (`incompleteRatio`, `suppressedDiagnosticsTotal`) is not rationed the same way: it appears as soon as a single project is incomplete |
| `projectsScanned` | The denominator: how many projects were scanned |

**What to do.** Build the solution, then `refresh_session`. Only after that is `errorCount` a statement about the solution.

### Load problems that are not shown in a dialog

**Symptom.** Symbols are missing from answers, and no dialog appears.

**Cause.** Problems while loading a project (an unsupported project type, a broken project file, a missing target) are logged as `[Workspace] <kind>: <message>` rather than shown in the interface. In the desktop application they land in `%APPDATA%\AIContextBuilder\aicb.log`; in the MCP server they go to stderr. A project of an unsupported type therefore drops out of the analysis without a visible message.

**What to do.** Check `aicb.log` (desktop application) or the stderr log of your MCP client for `[Workspace]` entries; make sure the project type is one Roslyn can load; restore and build the solution.

### The analysis is cancelled

**Symptom (CLI).** `cancelled.` on stderr, exit code `3`.

**Cause.** You pressed Ctrl+C, or the operation was cancelled. This is the intended way to stop an analysis; the workspace is cleaned up.

**What to do.** Run the command again when you are ready.

### Two analyses of the same solution at the same time

**Symptom.** A call hangs for a while and then answers:

```
Gave up waiting for the solution registry after <N>s: the registry is <loading|reloading|applying edits to> '<path>', started <M>s ago. This call never started - it was queued behind that operation, so retrying now would queue again. Wait for the running load to finish, or analyze a smaller solution/filter (.slnf).
```

When a session initializes itself from a `.sln` path, the same message reads `Gave up waiting for the solution analysis after …`.

**Cause.** There is one gate per solution path. A second caller waits instead of starting a second analysis; the MCP server gives up after 45 seconds by default, so that you learn what is holding the gate instead of waiting silently.

**What to do.** Wait — do not retry, because a retry queues behind the same operation again. For very large solutions, analyze a solution filter (`.slnf`) instead of the whole solution.

Note: the wait can be changed for the MCP server with the environment variable `AICB_MCP_LOAD_WAIT_MS` (milliseconds). The desktop application and the CLI wait without a limit.

## 11.3 LLM and network errors

The desktop application can send a generated context document to an LLM: Anthropic, OpenAI, or `Custom` for any local OpenAI-compatible server (Ollama, llama-server, LM Studio, vLLM, and others). Errors are returned as a message on the result, not as a crash. For HTTP errors the provider's own response body is included, truncated to 800 characters.

### The message catalogue

| Situation | Message |
|---|---|
| Model name missing | `Anthropic: ModelName is required.` / `OpenAI: ModelName is required.` / `Local: ModelName is required.` |
| API key missing | `Anthropic: ApiKey is required.` / `OpenAI: ApiKey is required.` |
| Endpoint missing (local) | `Local: Endpoint is required (e.g. http://localhost:11434/v1).` |
| Key would be sent in cleartext | `Anthropic: API key not sent over plain HTTP to a non-localhost host. Use an HTTPS endpoint.` (the same for OpenAI; local: `Local: bearer token not sent over plain HTTP to a non-localhost host. Use an HTTPS endpoint or omit the API key for unauthenticated local servers.`) |
| HTTP error status | `Anthropic HTTP <code>: <body>` / `OpenAI HTTP <code>: <body>` / `Local HTTP <code>: <body>` |
| Timeout | `<provider> timeout: HttpClient default timeout exceeded.` (the HTTP client timeout is 5 minutes) |
| Network error | `<provider> network error: <message>` |
| Other error before the stream starts | `<provider> unexpected error: <message>` |
| You cancelled the call | `Cancelled.` |
| Response could not be read | `Response parse error: <message>` (Anthropic: `Anthropic response parse error: <message>`) |
| Unknown provider | `Unsupported provider '<x>'. Supported: Anthropic, OpenAI, Custom (local OpenAI-API-compatible: Ollama / llama-server / LM Studio / vLLM / etc.).` |
| No result recorded | `LlmClientDispatcher: no response captured.` |

For `HTTP 401` and `HTTP 403` the provider's body tells you whether the key is wrong or the account has no credit; these statuses are not retried.

Note on local endpoints: enter the base URL of your server (for example `http://localhost:11434/v1`). A bare host is completed to `/v1/chat/completions`, an already versioned base (for example `/v1beta`) gets `/chat/completions`, and a full chat-completions path is accepted unchanged.

### A truncated answer

**Symptom.**

```
Stream ended unexpectedly (no finish_reason/[DONE] received; response may be truncated).
```

For Anthropic the wording is `Anthropic stream ended unexpectedly (no stop_reason/message_stop received; response may be truncated).` The partial text received so far is kept and delivered together with the message.

**Cause.** A healthy stream ends with a finish marker. If the marker is missing, the connection was closed before the model finished — a clean end of the connection is not proof that the answer is complete.

**What to do.** Repeat the run. If it happens repeatedly, check a proxy or firewall between you and the provider, or — for a local server — whether the server ran out of memory.

### Rate limits and automatic retries

The application retries a failed call automatically for these status codes: `429`, `500`, `502`, `503`, `504`, and for network and timeout errors. If the provider sends a `Retry-After` header, that value is used (capped at the maximum backoff); otherwise the wait grows exponentially from the base backoff.

| Setting (`Settings > General`, section `LLM Retry`) | Default | Meaning |
|---|---|---|
| `Max attempts` | `3` | Total attempts per call; `1` means no retry |
| `Base backoff (seconds)` | `1` | First retry delay; doubled on each further attempt (1s → 2s → 4s …) |
| `Max backoff (seconds)` | `30` | Upper bound for a wait, including a provider `Retry-After` value |

Changes take effect after an application restart. A cancellation by you is never retried, and neither is `401`/`403` — retrying a wrong key would only repeat it.

### Before a run: cost estimate and context window

A single `Manual` call starts without a cost pre-flight. For the `Iteration` and `Preselection` run types — **not yet released**, see the note below — the application estimates the token budget before sending and asks for confirmation when the estimate reaches the configured threshold:

| Setting (`Settings > General`, section `Run Confirmation`) | Default |
|---|---|
| `Confirm threshold (tokens)` | `50000` |

Note: the comparison is "greater than or equal", so a threshold of `0` means the application asks before **every** run, not never.

Independent of the run type, a request whose input plus maximum response would exceed the model's context window triggers a warning before sending, with the estimated size and the model's window. Lower the token budget or pick a model with a larger window.

Note: `Iteration` and `Preselection` run templates are wired but not finished, so they are not released yet; only `Manual` templates can be selected. `Pipeline` exists in the stored data model only and executes nothing.

## 11.4 Data and persistence

### Switching or creating a database fails

All messages from `Settings > Storage` appear as the error of the operation:

| Situation | Message |
|---|---|
| Empty path | `Database path is empty.` |
| Wrong extension | see `'…' is not an AIContextBuilder database` above |
| Schema version unreadable | `Could not read schema version: <message>` |
| Target database is newer | `Target DB schema version <N> is newer than this app's latest (<M>). Upgrade the app or pick a different DB.` |
| Target needs migrations | `Target DB needs <N> migration(s); confirm to apply them.` |
| Background work running | `Cannot switch DB while <k> background task(s) are active.` / `Cannot create DB while <k> background task(s) are active.` |
| Activity slot not available | `Could not reserve DB-Swap activity slot: <message>` |
| Settings file could not be written before the swap | `JSON write failed before swap: <message>` |
| Migration failed, rollback succeeded | `Migration failed: <message>. JSON rolled back to previous path.` |
| Migration failed, no previous path | `Migration failed: <message>. No previous path to roll back to - JSON points to the new (broken) target.` |
| Rollback failed as well | appended to the previous message: ` Rollback itself failed: <message>.` |
| Swap succeeded, cache refresh incomplete | `Swap succeeded but cache-invalidation partially failed: <message>. Restart the app to refresh stale caches.` |
| Creating a database where a file already exists | `File already exists: <path>. Use Switch for an existing DB.` |
| Directory could not be created | `Could not create directory: <message>` |

Each message also tells you what state the settings file is in afterwards — whether it was rolled back to the previous path, whether there was no previous path, or whether the rollback itself failed. That is the information you need for the next step.

### A stored snapshot is not reused

**Symptom.** An analysis that normally reuses a stored snapshot runs fully instead, without an error.

**Cause.** The stored snapshot no longer matches the running build — the persisted format or the identity of the analysis engine changed (typically after an update) — or the file-set hash could not be computed reliably. The application discards the snapshot and analyzes fully rather than risk loading an incompatible one.

**What to do.** Nothing; the full analysis is the correct reaction. The only thing worth knowing is why an analysis takes longer once after an update.

### `attempt to write a readonly database`

**Symptom.** This message appears while the application is writing to the database.

**Cause.** A second process holds the database file: a running MCP server instance, a second desktop application instance, or a backup program. When the holder is an archiver, SQLite's open succeeds but is silently downgraded to read-only, so every write fails with this message.

**What to do.** Check whether a second instance of the application or an `aicb mcp` process is running (an MCP server that an agent keeps alive is the usual case), close it if it is not needed, and restart the application.

### Automatic backup reports

The automatic backup reports when something is missing or failed: `Partial` and `Failed` are shown in the startup notice bar, prefixed with `Automatic backup at startup - `. It also reports a successfully written archive when the last-backup timestamp could not be stored. A clean backup with successful bookkeeping, and a start on which none was due, stay silent.

| Situation | Message |
|---|---|
| Base path does not exist | `BasePath does not exist: '<path>'.` |
| Backup folder cannot be created | `Could not create backup folder: <message>` |
| Backup failed | `Backup failed: <message>` |
| No free file name | `Could not find a free backup file name in '<folder>' after 100 attempts.` |
| Archive written | `Backup written to <path>` |
| … with locked files | ` (skipped <k> locked file(s): <names> and <r> more)` |
| … without the database | ` (database NOT archived: <reason>)` — for example `path unusable - <message>` |
| … with a failed timestamp write | `The archive was written, but the backup timestamp could not be stored (<reason>) - so this backup will run again at the next start.` (or, with the backup switched off: `… the last-backup time still shows the previous run.`) |

Note: an incomplete archive is renamed with a `-partial` marker before the `.zip` extension, and the newest complete archive is never removed by the retention rule — so a series of partial backups cannot evict the last archive that actually contains your database.

The bar is dismissible, and the dismissal is deliberately not remembered: a problem that is still there reports again at the next start.

### A note cannot be saved

**Symptom.** In the `MCP Usage` panel:

```
The note could not be saved: the call it belongs to is no longer in the database. It was probably cleared in the meantime.
```

For any other error the message is `The note could not be written: <message>`.

**Cause.** The tool call the note belongs to was deleted in the meantime, so the note's foreign key no longer resolves. The two texts are split on purpose: only this case gets the explanation, while every other failure (a locked file, a wrong database path) carries the real error message.

**What to do.** For the first case there is nothing to do — the call is gone. For the second, read the message: it names the actual cause.

### An imported usage report seems to be missing

**Symptom.** You imported an MCP usage report, but the numbers in the `MCP Usage` panel do not change.

**Cause.** An imported report is stored **beside** the live data, as a named snapshot — it appears in the `Snapshots` region of the panel, not in the live figures above it, which always aggregate only the local calls.

**What to do.** Switch to the `Snapshots` region. When there are no local calls but an imported snapshot exists, the panel selects that region for you.

## 11.5 Diagnostic means

| Means | Where | What it shows |
|---|---|---|
| `aicb.log` | `%APPDATA%\AIContextBuilder\aicb.log` (desktop application only) | Warnings and errors of the desktop application; rotates at 1 MiB, with `aicb.log.1` to `aicb.log.3` as archives; the file can be copied while the application runs |
| `load-perf.log` | `%APPDATA%\AIContextBuilder\load-perf.log` (desktop application only) | Solution-load phase timings, no errors; enabled with `Settings > General` → `Record solution-load performance timings`; does not rotate |
| `app-settings.json` | `%APPDATA%\AIContextBuilder\app-settings.json` | Storage paths and the recent lists |
| `server_info` | MCP tool, or `aicb call server_info` | Version, build commit, config-database schema version, and drift between binary, config database and the analyzed repository |
| Staleness remark | attached automatically to affected MCP answers | whether the answer came from a graph older than the files on disk; see "Sessions and staleness" in the MCP manual |
| `THIS ANALYSIS RUN WAS INCOMPLETE` | attached automatically to affected MCP answers | how many projects could not resolve their references (see "The solution was never built") |
| `get_diagnostics` | MCP tool | Compiler errors and warnings in seconds instead of a full `dotnet build` |
| `list_mcp_profiles` / `list_skills` | MCP tools | which tools the active profile exposes, and which exist outside it |
| `usage_report` / `MCP Usage` panel | MCP tool / desktop application | what the server actually did, per tool call |
| stderr of the MCP client | client-dependent | startup warnings, Roslyn load warnings, fatal background errors |
| CLI exit codes | shell | see the table below |

| Exit code | Meaning |
|---|---|
| `0` | Success |
| `1` | User error (invalid arguments, missing files) |
| `2` | Runtime error (unexpected exception) |
| `3` | Cancelled (Ctrl+C) |
| `4` | Migration failed |
| `5` | MSBuild not found |
| `6` | Quality gate failed (`analyze --fail-on`; the document is still produced) |

The CLI and the MCP server write no log file of their own; their channel is stderr.

Environment variables for the MCP server process (invalid or non-positive values fall back to the built-in default):

| Variable | Effect |
|---|---|
| `AICB_MCP_TOOLS` | Tool curation for the process |
| `AICB_MCP_SESSION` | Comma-separated `key=value` list with the keys `ttlMinutes`, `maxSessions`, `sweepMinutes` (for example `maxSessions=4,ttlMinutes=120`) |
| `AICB_MCP_AUTO_REFRESH` | Auto-refresh mode. Built-in and newly created profiles seed `Reactive`; without a resolved configuration database/profile, or when the field is absent, the effective mode is `Off` |
| `AICB_MCP_DEBOUNCE_MS` | Debounce window of the file watcher |
| `AICB_MCP_STALENESS_WINDOW_MS` | Throttle window of the staleness check |
| `AICB_MCP_LOAD_WAIT_MS` | How long a tool call waits at the load gate (see "Two analyses of the same solution at the same time") |
| `AICB_MCP_ERROR_TEXT=off` | Do not write the free text of an error message into the usage record; only the exception type is kept |

### Which version am I running?

- Desktop application: `Settings > About`.
- CLI and MCP server: `aicb --version`; the MCP server additionally reports its version and build commit through `server_info`.

Note: if you installed both the installer and the .NET tool, two copies share one data folder. Install one of them per machine — see "License, installation and updates".

### If the application reports an unexpected error

A dialog titled `Unexpected error` with this text means that an error reached the outermost handler:

```
An unexpected error occurred.

The application is still running, but its state may be inconsistent. Save any open sessions and restart.

Details: <Type>: <message>
```

The `Details:` line names the exception type and message, including up to three nested levels. The application stays alive on purpose, so that you can save open sessions before you restart. At most three such dialogs appear per session; further occurrences of the same failure are written to `aicb.log` without a dialog, so that file is where to look if the interface keeps misbehaving quietly.

### What to include in a report

- `%APPDATA%\AIContextBuilder\aicb.log` together with the archives `aicb.log.1` to `aicb.log.3` (desktop application).
- The version you are running (see above).
- For an analysis problem: the name of the solution — not its content.
- For a dialog: a screenshot, including the `Details:` line if it has one.
- `%APPDATA%\AIContextBuilder\app-settings.json` if the problem concerns paths or a database.
- For an MCP problem: the stderr log of your MCP client.

## 11.6 Support

- Questions, bug reports and feature requests: **GitHub Issues** at `github.com/gregordadera/AICB/issues`.
- Security reports: please do **not** open a public issue. Send them to `aicb@dadera.de` or use **Report a vulnerability** on the `Security` tab of the repository. You will get an acknowledgement; there is no response-time deadline.

---

[&larr; 10 Data, storage and privacy](10-data-storage-and-privacy.md) &middot; [Contents](README.md) &middot; [12 Glossary &rarr;](12-glossary.md)
