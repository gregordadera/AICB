[AICB – Desktop Application](README.md) &middot; chapter 11 of 11

# 11 Troubleshooting the desktop app

This chapter is the reference for the desktop app's error behavior: what to check on a first start, where the app reports problems, where it stays silent, what its log file contains, and what to do about each problem you can actually hit. The CLI and the MCP server keep their own diagnostic channels and are covered in their own chapters.

## 11.1 First start checklist

### What the app needs

The desktop app is self-contained — no .NET *runtime* is required to start it. Analysis is different: opening a solution runs MSBuild to resolve references, exactly like `dotnet build` does, so the machine needs a **.NET SDK or a Visual Studio installation** with the `.NET desktop development` or `MSBuild Tools` workload. The app checks this before anything else and refuses to start without it (see "MSBuild not found" below). Only analyze solutions you trust, because loading one executes its build logic.

The desktop app comes in two forms:

| Form | What it is |
|---|---|
| `AIContextBuilder-Setup-<version>.exe` | Installer, needs administrator rights. It puts the `aicb` command on `PATH` unless you untick that option. Consoles, editors and agents that were already open see the new `PATH` only after a restart. |
| `AIContextBuilder-<version>-win-x64.zip` | Portable, no installation. `gui\aicb-ui.exe` starts the desktop app; `cli\aicb.exe` is the CLI and MCP server. |

Neither is code-signed yet, so Windows SmartScreen may show "Windows protected your PC" for the installer; *More info* → *Run anyway* continues. Every release lists SHA-256 checksums for its files.

### What happens when you start the app

The startup order is fixed, and each step assumes the previous one:

1. The splash window appears with `Starting up…` and the line `100 % local analysis - nothing is sent without your action.` It runs on its own thread, so it keeps animating while the rest of the startup blocks the main thread.
2. MSBuild is located (via the .NET SDK or Visual Studio). Without it: dialog `MSBuild not found`, then the app exits.
3. The service container is built and validated, then the database schema is migrated. On a fresh installation the database file is created here.
4. Unfinished runs from the previous session are looked for. Only if any exist do you get the `Unfinished runs from previous session` dialog.
5. The automatic backup runs if it is enabled and due. It is **off by default**, and it archives synchronously before any window exists — on a large data folder this visibly delays the start.
6. The shell is initialized, the theme is applied, the main window appears, and the splash closes.

A start can take several seconds, and longer when the database is large. That is normal, not a hang; the splash exists to make the wait visible.

### What you see on the Start page

After the start, **no tab is open and no sidebar entry is selected** — the Start page stays visible until you navigate yourself.

| Element | What it does |
|---|---|
| Entry text | `Turn your C# solution into a semantically compressed context for LLMs. Open a solution or load a previous session to get started.` |
| `New Solution` card | Opens the file dialog for a `.sln`, `.slnx` or `.slnf` file and loads it. |
| `Open Solution` card | Opens the same file dialog. Both cards behave identically today; the tooltips describe a difference that does not exist yet. |
| `Load Session` card | Opens the `Workspace` tab, where you pick a saved session. |
| `Recent Solutions` list | The solutions you opened most recently (up to 8), with an `Open` button and double-click. A warning icon marks an entry whose `.sln` no longer exists at the saved path. |
| `Recent Sessions` list | Your most recently saved sessions (up to 5). |
| `Refresh` button | Reloads both lists. |

On the very first start both lists are empty and show `No recent solutions yet.` and `No saved sessions yet.`; the footer says `Tip: Click an area in the left sidebar to open it as a tab.`

The left sidebar carries four groups with eight entries (group headers are not clickable):

| Group | Entries |
|---|---|
| `Quick Access` | `Start` |
| `Workspace` | `Context Builder`, `Workspace`, `Run Templates` |
| `Configuration` | `Templates`, `Settings` |
| `MCP` | `MCP Profiles`, `MCP Usage` |

### Opening your first solution

1. Click `New Solution` or `Open Solution`. The file dialog is titled `Open solution` and filters on `Solution files (*.sln;*.slnx;*.slnf)`.
2. The solution is analyzed in a new `Context Builder` tab. A load screen reports the phases with a progress bar: `Opening workspace`, `Building project tree`, `Analyzing code` with a `N / M files` counter, `Saving snapshot`, `Done`. The bar becomes determinate with the first progress report, `Opening workspace`, rather than waiting for a per-file report. A pinned-snapshot restore starts with `Restoring snapshot` and remains indeterminate.
3. When the load finishes, four things exist that did not before: a row for the solution in the workspace, an automatic snapshot of the analyzed state, an entry in the recent-solutions list, and the solution tree in the Context Builder.
4. On a **fresh installation** the first analysis also runs the insights producers once automatically, so the Insights tab is not empty on first contact. Later loads do not do this unless you switch on `Auto-trigger insights on solution load` in `Settings > General`.

A bundled sample solution is available too: `ColorMixer.SelectionLab.sln` lives under `{exe}\SampleSolutions\`. It is offered by the `Open sample Solution` button in the empty state of the Insights tab, which is only reachable once a solution is open. The Start page does not offer it.

### What is remembered, and what is not

| Remembered | Not remembered |
|---|---|
| Recently opened solutions (up to 8) and databases | Open tabs — the app always starts on the Start page |
| The last selected Settings sub-tab | Window size and position — the window always starts maximized, centered, at a fixed default size |
| Theme, font family, font size, UI zoom | Anything you did not save as a session |
| The active templates and profiles | |
| Saved sessions (they reappear in the `Recent Sessions` list) | |

The `On startup` choice in `Settings > General` (`Restore last tabs`, `Restore last session`, `Sessions overview`, `Empty session`) is stored but currently has **no effect**; restoring the previous session is a planned feature. Until then, saving a session is the only way to carry work across a restart. See "Workspace, sessions and snapshots" for saving and resuming sessions.

### Where your data lives

| What | Default location |
|---|---|
| Database | `%APPDATA%\AIContextBuilder\user-data\aicb.acb` |
| Settings file | `%APPDATA%\AIContextBuilder\app-settings.json` |
| Support log | `%APPDATA%\AIContextBuilder\aicb.log` (plus rotated copies) |
| Load timings | `%APPDATA%\AIContextBuilder\load-perf.log` |
| Automatic backups | `<BasePath>\backups\`, by default `%APPDATA%\AIContextBuilder\backups\` |

`Settings > Storage` shows the active database file (`Current file`), the settings file the app actually uses (`App settings file`) and the `Base path`. The default database and the base path can be changed there; the settings file itself always stays at `%APPDATA%\AIContextBuilder\app-settings.json`, even if you change the base path. Deleting `%APPDATA%\AIContextBuilder\` removes your data along with the app's settings.

## 11.2 Where errors appear

The desktop app reports problems through exactly three channels, plus the splash window:

1. **Modal dialogs** for anything that needs an answer or that you must see.
2. **Status lines** inside panels for the outcome of an action.
3. The **startup notice bar** for problems that happened before any window existed.

There are no toasts, no snackbars and no info bars. A problem that reaches none of these three channels leaves no visible trace at all — see "Silent failures" below.

### Modal dialogs

All message dialogs are themed windows of the application, not Windows message boxes. They come with four button sets: OK, OK-Cancel, Yes-No, and Yes-No-Cancel.

- `Esc` and the window's close button return the same answer as the dismiss button: Cancel where the dialog has one, otherwise No, otherwise OK.
- `Enter` answers the primary button — except in a **destructive** confirmation (for example discarding unsaved changes). There the `No` button holds the focus and answers `Enter`, so a reflexive key press cannot delete anything, and the dangerous button is styled as dangerous.

Typical startup dialogs and their titles:

| Title | Meaning |
|---|---|
| `MSBuild not found` | No usable MSBuild installation; the app exits. |
| `Database is newer than this build` | The database was written by a newer version; the app exits rather than write to it. |
| `Database migration failed` | The schema could not be updated; the app exits. |
| `Unfinished runs from previous session` | Runs from the last session never reached a final state. |
| `Crash recovery` | The recovery check itself failed; the app starts anyway. |
| `Unexpected error` | An unhandled error; the app stays open. |

### Status lines

Panels report the result of an action in a status line — usually at the bottom of the panel's action bar. These messages are **not modal and easy to miss**, and the next action can overwrite them. Read the status line right after the action that produced it.

| Message pattern | Where |
|---|---|
| `Save failed: <reason>` | Settings panels, run templates, session save |
| `Export failed: <reason>` | Settings panels, run templates |
| `Import failed: <reason>` | Run templates, master data |
| `Check failed: <reason>` | Code editor in the Details tab |
| `Send failed: <reason>` | Context Builder, under `MD Input` |
| `Snapshot history could not be read` | Workspace, snapshot list |
| `Statistics could not be read` | Workspace, overview cards |
| `Not analyzed yet` | Workspace, overview cards — a statement, not an error |
| `- runs` | A session row whose run count could not be read (a dash, not a zero) |
| `Auto-save could not save one of your open sessions. …` | Dialog (once per session), see "Auto-save and unnamed tabs" |

### The startup notice bar

The startup notice bar sits at the top of the content area, above the Welcome page or the tab strip. It appears only when something went wrong **before any window existed**, so it has exactly two producers:

- the automatic backup when the archive is incomplete, could not be written at all, or was written successfully but its completion timestamp could not be saved (a fully recorded clean backup, and a start on which none was due, stay silent);
- an unreadable application settings file.

Messages are prefixed with their source: `Automatic backup at startup - …` or `Application settings - …`. If both happen on one start, both lines appear.

The dismiss button hides the bar for the current session only. Nothing is saved: if the problem is still there, the next start reports it again.

### The splash window

The splash (`Starting up…`) is not an error channel. It exists so that a slow start does not look like a crash — which is exactly why a long-running splash is not a symptom by itself.

### Silent failures

Some failures produce no message at all; the app simply continues with a plausible-looking result. This is the deliberate trade-off behind the "the app stays usable" policy, and it is the hardest class to diagnose, because nothing looks broken. The rule of thumb: **if an area is unexpectedly empty or unexpectedly unchanged, refresh it explicitly (`Refresh`, `Analyze Solution`) and look into `aicb.log`.**

| Symptom | What actually happened |
|---|---|
| The Insights panel is empty and shows `No insights to show here - pick a category on the left, or relax the principle/severity filters.` | Reading the stored insights failed; the empty-state text sends you to the filters while the cause is a database read error. |
| The `Solutions` tab shows old data that looks current | The refresh of the tab failed and the previously loaded rows stayed on screen. |
| The model profile picker is empty although profiles exist | Reading the profiles failed. |
| The list of recent runs is empty | Reading the run history failed — indistinguishable from "no runs yet". |
| A dismissed insight comes back after the next refresh | The database write for the dismissal failed; the card is removed from the list anyway. |
| The counter-clockwise-arrow button in the Insights toolbar (tooltip beginning `Reset what you hid - ...`) seems to do nothing | The database write failed and the command returned. |
| Copying to the clipboard does nothing, in any panel | The clipboard was held by another process (for example an RDP session or a virus scanner). Copy retries three times with a 50 ms pause and then gives up without a message. Paste reads once, catches an error and silently returns no text; it is not retried. |
| A splitter position is forgotten after a restart | Saving the layout is best-effort and silently skipped on failure. |
| The prompt fields are unchanged after opening a session | The stored prompt payload could not be parsed; the current values were kept. |
| The unsaved-changes summary is missing the tree-selection line | It is not missing: the line reads `Tree selection: could not be read - it may hold unsaved overrides`. |
| The tab strip does not react to clicks | A run is active; see "The tab strip is locked while a run is active". |

## 11.3 The `Unexpected error` dialog

An unhandled error in a command, an event handler or a background callback is caught by the app's global exception handlers and reported in a dialog titled `Unexpected error`:

```
An unexpected error occurred.

The application is still running, but its state may be inconsistent. Save any open sessions and restart.

Details: <Type>: <message> -> <inner type>: <message> -> …
```

The `Details:` line unwraps up to three nested exceptions, because the outermost one is often a meaningless wrapper.

**Why the app keeps running.** Several Context Builder tabs can hold unsaved sessions in memory. Ending the process would discard them without asking. Staying alive gives you the one thing you cannot get afterwards — the chance to save. The price is a possibly inconsistent state, and the message says so instead of pretending the error was handled.

Two rules keep this dialog from taking over the app:

- **At most three dialogs per session.** A failing layout or render path throws on every frame; an unconditional dialog would lock you out of your own application. After the third dialog, further errors are written to the log only.
- **Each distinct error is shown once.** Errors are de-duplicated by type, message and top stack frame, so the same bug does not repeat while a different bug with the same message still gets through.

What to do: save your open sessions, restart the app, and include the `Details:` line in a support request. The suppressed repeats after the third dialog are still in `aicb.log`.

A failure inside a background task that nobody awaits does **not** produce a dialog: since .NET Core it no longer ends the process, and the app logs it as a diagnostic. If something behaves oddly after a long-running action, the log is the place to look.

## 11.4 The log file `aicb.log`

The desktop app writes its own warnings and errors to a rotating local file:

| Property | Value |
|---|---|
| Path | `%APPDATA%\AIContextBuilder\aicb.log` |
| Levels | `Warning`, `Error` and `Critical` only — the normal flow is not recorded |
| Format | ISO 8601 timestamp (UTC), level in brackets, logger category, message; the full exception follows on the next lines when one is attached |
| Rotation | at 1 MiB, keeping three archives: `aicb.log.1`, `aicb.log.2`, `aicb.log.3`; the oldest is dropped |
| Open handle | none — you can copy the file while the app is running |

Notes:

- The file is created with the first warning or error. On a healthy installation it may not exist at all.
- A second running instance may lose a single entry when it writes at the exact moment another process holds the file; the entry is dropped so that logging can never turn a recoverable error into a failed start.
- The log contains the unhandled errors of the `Unexpected error` dialog, including the repeats that were suppressed after the third dialog.
- A few deliberately non-critical startup steps — applying the theme, the font and the UI zoom — are caught **without** writing a log entry. If the app starts in the wrong theme, the log is silent about it; a restart is the first thing to try.
- Logging is best-effort: if the file cannot be written, the error is still shown to you, it is just not recorded.

### `load-perf.log`

A second, separate file records solution-load phase timings:

- Location: `%APPDATA%\AIContextBuilder\load-perf.log`
- One line per solution load, prefixed with a local timestamp, in the form `[PerfLoad] {context} total=…ms Phase1_LeaseAcquire=… Phase2_TreeBuild=… Phase3_Analyze=… Phase4_Snapshot=…`; only `total` carries the `ms` suffix
- Switch: `Settings > General` → `Record solution-load performance timings` (on by default)
- It contains **times, not errors**, and is not the file to send for a malfunction report.

### What to send with a support request

| Item | Where to find it |
|---|---|
| The log and its archives | `%APPDATA%\AIContextBuilder\aicb.log`, `.1`, `.2`, `.3` |
| A screenshot of the dialog | The `Details:` line carries the exception type and message |
| The app version | `Settings > About` |
| Settings and paths | `%APPDATA%\AIContextBuilder\app-settings.json` |
| Load timings (only if the start or a load is the problem) | `%APPDATA%\AIContextBuilder\load-perf.log` |
| For MCP problems | The stderr log of your MCP client — the only place the MCP server leaves diagnostic text |

Bugs and feature requests go to GitHub Issues; the `About` panel shows the Issues URL as plain, non-clickable text in its support card.

## 11.5 Problems and their solutions

### The app does not start

#### `MSBuild not found`

**Symptom.** A dialog titled `MSBuild not found` appears right after the splash. It ends with `The application will exit.`, and the app closes (exit code 1).

**Cause.** The app found no compatible MSBuild installation. It tries, in this order: the MSBuild locator's defaults, the installed Visual Studio instances, `vswhere.exe`, and the newest .NET SDK under `%ProgramFiles%\dotnet\sdk`. Without MSBuild no Roslyn solution can be loaded, so a window without a working feature would be the worse answer.

**What to do.** Install the .NET SDK or Visual Studio with the `.NET desktop development` or `MSBuild Tools` workload, then start the app again. The dialog names the probes it ran, including the PowerShell commands to reproduce them:

```
& "C:\Program Files (x86)\Microsoft Visual Studio\Installer\vswhere.exe" -latest -products * -requires Microsoft.Component.MSBuild -property installationPath
dotnet --list-sdks
```

#### `Database is newer than this build`

**Symptom.** A dialog titled `Database is newer than this build` shows the database schema version and the version this build knows; the app exits (exit code 2).

**Cause.** The database was written by a newer version of the application. An older build would silently save the outdated shape back, so it refuses to open the file at all.

**What to do.** Update the application, or point the database path at a different file in `Settings > Storage`. Note that the installer and an unpacked ZIP share the same `%APPDATA%` folder: a newer unpacked copy migrates the shared database, after which an older installed copy refuses to start.

#### `Database migration failed`

**Symptom.** A dialog titled `Database migration failed` shows the error; the app exits (exit code 2).

**Cause.** The schema migration threw — typically the database file is not reachable or not writable, is locked, or the disk is full.

**What to do.** Check the database path shown in `Settings > Storage` for reachability and write permission, fix the cause, and start again. If the settings file itself is unreadable, the app runs on defaults and may point at a different database — see "The settings file could not be read".

#### `Unfinished runs from previous session`

**Symptom.** A three-way dialog at startup lists runs that did not finish cleanly, up to five entries plus `... and N more`. Each line shows the run name, its type and its start time.

**Cause.** The previous session ended without the run reaching a final state (crash, hard kill, power loss). The app finds runs still marked as running and asks what to do with them.

**What to do.**

| Answer | Effect |
|---|---|
| `Yes` | Mark the runs as `Cancelled` and set their finish time to now. |
| `No` | Pause them for a later resume; no finish time is set. |
| `Cancel` / window close | Leave them unchanged — they stay visible and the question returns at the next start. |

If the recovery check itself fails, a warning dialog titled `Crash recovery` appears, the app starts anyway, and the runs stay in the running state.

#### The splash stays longer than expected

**Symptom.** `Starting up…` stays on screen for several seconds before the main window appears.

**Cause.** The shell builds all of its page view models in one synchronous call; a large database makes this slower. The splash runs on its own thread precisely so it keeps animating during that time.

**What to do.** Wait. If the splash never closes and no main window appears, see the next entry.

#### No window appears after an `Unexpected error` during startup

**Symptom.** An `Unexpected error` dialog appears while the app is starting. After you dismiss it, no main window opens, but the process keeps running.

**Cause.** An exception escaped the startup path. The global handler keeps the process alive and reports the error, but if it happened before the main window was created, there is no window to return to.

**What to do.** End the process (`aicb-ui.exe`) in Task Manager and start the app again. If it happens repeatedly, include the `Details:` line and `aicb.log` in a report.

#### Auto-backup delays the start — or repeats at every start

**Symptom.** The window appears only after a long pause, and the startup notice bar reports a failed backup. The same pause returns at every start.

**Cause.** Auto-backup is enabled and due. It archives synchronously on the UI thread before any window exists, so the whole archive run is startup time; on a large base path that is a noticeable delay. A **failed** run never advances the last-backup timestamp, so it is due again at the next start until the cause is fixed.

**What to do.** Read the reason in the notice (`BasePath does not exist: '…'`, `Could not create backup folder: …`, `Backup failed: …`), fix it, or switch auto-backup off in `Settings > Storage`. `Backup Now` runs a backup immediately and shows its result in the panel's status line. Note that an archive that is missing something (for example the database, because another process holds it open) is written with a `-partial` suffix and **does** advance the timestamp — so it does not repeat every start.

#### The settings file could not be read

**Symptom.** The startup notice bar shows `Application settings - Your settings file could not be read, so this session is running on DEFAULTS …`. Your sessions and solutions may look missing, and the theme may be the default one.

**Cause.** `%APPDATA%\AIContextBuilder\app-settings.json` is corrupt or could not be opened. The app continues with default settings — and the defaults include the database path, so it may open the default database instead of yours. The settings file is never moved by the `Base path` setting; it always lives at the default location.

**What to do.** The message names a preserved copy of the unreadable file, `app-settings.json.corrupt-<timestamp>`, next to the original. Repair that copy and restore your paths, or set the correct database path again in `Settings > Storage`. If no copy could be made, the message says so and warns that the next solution you open will overwrite the file — copy it elsewhere before you continue.

#### The app starts with the wrong theme or font size

**Symptom.** The theme or the font size differs from the configured value, although `Settings > General` shows the right setting.

**Cause.** Theme, font and UI zoom are applied during startup as best-effort steps; a failure is caught and **not** reported anywhere. The splash itself always follows the Windows app theme, so it can briefly differ from the app's own theme even on a healthy start.

**What to do.** Restart the app. If the setting is still not applied, re-select it in `Settings > General` (standard controls switch immediately; some custom panels apply fully only after a restart).

### Opening and loading solutions

#### A solution was moved or renamed

**Symptom.** Opening a solution from the recent lists fails with a dialog titled `Open solution` and the text `Solution file not found:` followed by the path.

**Cause.** The saved path no longer exists on this machine.

**What to do.** The app then opens the `Relocate solution` dialog: `Browse...` to the new location of the `.sln` file, or type the path, then `Relocate`. The stored path is updated and all sessions and snapshots of that solution are preserved. `Cancel` leaves the solution in the database with the old path.

#### Choosing a file in the `Open solution` dialog does nothing

**Symptom.** You pick a file, and neither a tab opens nor a message appears.

**Cause.** The chosen path does not exist at the moment it is checked (a typed path, or a network share that went away between selection and check). This path returns silently.

**What to do.** Check the file is really there and try again. The recent-solutions path does better: it reports `Solution file not found` and offers the relocate dialog.

#### Drag and drop does nothing

**Symptom.** Dropping a file onto the window has no effect.

**Cause.** The drop accepts exactly **one** file, and only with the extension `.sln`, `.slnx` or `.slnf`, and only if it exists on disk. Anything else — several files at once, another extension — is discarded without a message.

**What to do.** Drop a single solution file, or use the file dialog. If the drop fails while opening, a dialog titled `Open Solution` reports `Could not open solution:` with the reason.

#### Symbols are missing from the analysis

**Symptom.** After loading a solution, types or projects that exist in the code do not appear in the tree, or queries report fewer symbols than expected.

**Cause.** Roslyn load problems — an unsupported project type, a broken project file, a missing target framework — are reported as warnings to the log, not to the interface. The affected project quietly drops out of the analysis.

**What to do.** Look for `[Workspace]` lines in `aicb.log`. Fix the project so it loads (the same way it would have to load for `dotnet build`), then reload the solution.

### Working in the app

#### The tab strip is locked while a run is active

**Symptom.** Clicking another Context Builder tab does nothing; the whole tab strip is unresponsive.

**Cause.** Tab switching is disabled while any run is active, so a run state cannot be lost by switching away. The tooltip on the locked strip says `Tab switching locks while a run is active.`

**What to do.** Wait for the run to finish, or cancel it with the run's `Cancel` button; the tab strip unlocks afterwards.

#### No red border on an invalid input

**Symptom.** You enter something invalid, click `Save`, and nothing seems to happen.

**Cause.** The app has no field-level validation feedback: no field is outlined or marked. Numeric fields simply refuse non-numeric input as you type. Everything else is validated **when you save**, and the reason is written to the panel's status line, at the bottom of the action bar.

**What to do.** After clicking `Save`, read the status line. A rejected save leaves the value unsaved and shows a message such as `Save failed: Name is required.` The same applies to the Settings pages: the message appears in the action bar, not next to the field.

#### Copy does nothing

**Symptom.** `Copy to Clipboard` or `Ctrl+C` appears to succeed, but the clipboard is unchanged.

**Cause.** Another process holds the clipboard (RDP sessions and virus scanners are common causes). Copy retries three times with a 50 ms pause and then gives up silently. Paste is different: it reads once and silently returns no text if that read throws.

**What to do.** Try again a moment later, or close the process that holds the clipboard. There is no message, because the copy path has no return value to report.

#### A splitter position is not remembered

**Symptom.** You drag a splitter between panels, restart the app, and the position is back to the default.

**Cause.** Splitter positions are saved on every drag, but the write is best-effort: a failure (missing service, database not migrated, write error) is swallowed. The saved position also takes effect only the next time the view is loaded.

**What to do.** Nothing to repair — re-drag the splitter. If it never survives a restart, check `aicb.log` for write errors on the settings side.

#### Closing the app: `Could not check for unsaved changes`

**Symptom.** You close the window and get a dialog titled `Close Application` with the text `Could not check for unsaved changes, so the app was kept open to protect your work:` followed by the error and the advice `Save your sessions manually, then close again.` The app stays open.

**Cause.** The check for unsaved tabs threw. WPF would still close the window after such an error, which would discard every unsaved session — so the app cancels the close instead. Cancelling is the only safe answer to "we could not establish that closing is safe".

**What to do.** Save your sessions manually (see "Workspace, sessions and snapshots" in the desktop app manual), then close the app again.

#### The unsaved-changes summary mentions a tree selection that could not be read

**Symptom.** The `Unsaved tabs` dialog lists a line `Tree selection: could not be read - it may hold unsaved overrides`.

**Cause.** Collecting the tree selection failed while the summary was being built. The failure is reported as a named line instead of a missing entry, so the summary can never look complete while being short.

**What to do.** Treat the dialog as a warning that the tree selection may hold unsaved overrides; `Cancel` keeps the tab open so you can save it explicitly.

#### Auto-save and unnamed tabs

**Symptom.** Auto-save is enabled, but a tab with unsaved work was not saved.

**Cause.** Auto-save saves tabs that have a session ID. A brand-new tab without a session is skipped, but the LLM send path creates an `Untitled - <solution file> - <date and time>` session automatically; that session has an ID and is covered by later auto-saves even if you never renamed it.

**What to do.** If the tab has never been sent or saved, use `Save Session` to create its session record. If a send already created an `Untitled ...` session, no extra naming step is required for auto-save. If auto-save fails for a session, a dialog titled `Auto-save` reports it once per session, and the status says the changes remain unsaved.

#### The `On startup` setting has no effect

**Symptom.** You choose `Restore last tabs` (or another option) in `Settings > General`, but the app always starts on the Start page.

**Cause.** The setting is stored, but restoring the previous session has not been implemented yet. This is a planned feature.

**What to do.** Nothing yet — save your session before closing if you want to continue where you left off.

### Insights and panels that can look empty or stale

#### The Insights panel is empty and points at the filters

**Symptom.** The Insights tab shows `No insights to show here - pick a category on the left, or relax the principle/severity filters.`

**Cause.** Either there really is nothing to show, or reading the stored insights failed. The empty-state text is the same in both cases, and it names the filters while the cause may be a database read error.

**What to do.** Click `Analyze Solution` to re-evaluate, then check `aicb.log`. Insights run on demand by default; `Auto-trigger insights on solution load` in `Settings > General` switches them to automatic.

#### A dismissed insight comes back

**Symptom.** You dismiss a finding, it disappears, and after the next refresh it is listed again.

**Cause.** The database write for the dismissal failed. The card is removed from the list anyway, so the dismissal looks successful until the list is rebuilt.

**What to do.** Dismiss it again; if it keeps coming back, check `aicb.log` for write errors. Note that a finding the producers mark as persistent cannot be dismissed at all — its dismiss buttons are hidden.

#### The reset button in the Insights action bar seems to do nothing

**Symptom.** The restore button in the Insights toolbar has no visible effect.

**Cause.** The database write failed and the command returned without a message. A successful restore makes dismissed findings and intentionally accepted findings visible again, re-evaluates all sections immediately, and leaves suppressions declared in the committed `<Solution>.aicb.json` sidecar in force.

**What to do.** Trigger it again; if it still does nothing, check `aicb.log`.

#### The model profile picker or the recent runs list is empty

**Symptom.** The model profile dropdown in the Context Builder contains only its neutral default entry, or the recent runs list stays empty.

**Cause.** Reading the profiles or the run history failed; the failure is swallowed and the list stays empty. An empty recent-runs list is indistinguishable from "no runs yet".

**What to do.** Switch to another tab and back to reload, and check `aicb.log`. The send path is unaffected by the empty picker: it falls back to the standard model resolution.

#### The `Solutions` tab shows old data

**Symptom.** The solution list and its counts look unchanged although something was created or deleted in another tab.

**Cause.** The refresh of the tab failed; the previously loaded data stays on screen and looks current.

**What to do.** Use the tab's `Refresh` button, or reopen the tab. If the problem persists, check `aicb.log`. Note that the neighboring labels `Snapshot history could not be read` and `Statistics could not be read` are deliberate and different from `Not analyzed yet`: they say that the read failed, not that nothing was analyzed.

#### The `MCP Usage` panel misses the active-pool marking or stops updating

**Symptom.** In `MCP Usage`, the marking of tools that are in the active pool is missing, or the call log does not refresh.

**Cause.** Reading the active MCP profile or the call log failed; the panel logs the error and keeps its previous state. The panel deliberately reloads on every activation because the MCP server writes into the same database while the app runs.

**What to do.** Reopen the page; if it stays stale, check `aicb.log`.

#### Auto-compression and other settings quietly fall back to defaults

**Symptom.** Node compression does not follow your configured rules, snapshots are not reloaded before applying, or a preselection overview is rendered with compact defaults.

**Cause.** If the provider for the compression rules or the active pipeline profile fails, the app falls back to the built-in heuristic defaults and logs a warning. The overview renderer also falls back to Compact defaults when its configured detail preset cannot be loaded, but that particular fallback is silent and writes no warning.

**What to do.** For compression-rule or pipeline-profile failures, check `aicb.log` for the fallback warning, reopen the settings, and try again. A missing overview detail preset leaves no log entry, so inspect that configuration directly. The fallback keeps the feature working; it does not apply your configuration.

#### The prompt fields stay unchanged after opening a session

**Symptom.** You open a saved session, but the prompt fields still show the previous content.

**Cause.** The stored prompt payload could not be parsed. The fields are deliberately left untouched rather than cleared.

**What to do.** Re-enter the prompt, save the session again, and check `aicb.log`.

### Database, backup and paths

#### Switching the database fails: target is newer than the app

**Symptom.** In `Settings > Storage`, `Switch Database...` refuses with `Target DB schema version <n> is newer than this app's latest (<m>). Upgrade the app or pick a different DB.`

**Cause.** The selected file was written by a newer version of the application.

**What to do.** Update the application, or pick another database file.

#### Switching the database fails: migration error

**Symptom.** The switch fails with `Migration failed: …` and, depending on the case, `JSON rolled back to previous path.` or `No previous path to roll back to - JSON points to the new (broken) target.` followed, in the worst case, by `Rollback itself failed: …`.

**Cause.** The pending migrations on the target file could not be applied. The app tries to restore the previous database path in the settings file.

**What to do.** Read the message: it tells you exactly which state the settings file is in. If the rollback succeeded, the previous database is active again; if not, set the path manually in `Settings > Storage`. Background work (runs, analyses) must be idle before a switch.

#### `Cannot … while N background task(s) are active`

**Symptom.** `Switch Database...`, `Create New DB...`, `Backup Now` or saving the base path is refused with `Cannot switch DB while 1 background task(s) are active.` (the action name varies).

**Cause.** A background task is still running — typically a run or an analysis in the Context Builder. The message names the count, not the location.

**What to do.** Finish or cancel the run in the Context Builder, then repeat the action.

#### A backup archive is named `-partial`

**Symptom.** A file such as `backup-20260921-101500-partial.zip` appears in the backup folder, and the notice or status line says `database NOT archived` or lists skipped locked files.

**Cause.** Something could not be packed into the archive. The most common case is the database: an open SQLite connection (the GUI itself, or a co-running MCP host) prevents the archiver from reading it. Files that are locked are skipped and named in the message (up to five, then `and N more`).

**What to do.** Close the other process that holds the file, or accept the partial archive — it still contains everything else. A partial run does advance the backup timestamp, so it does not repeat at every start.

#### Changing `Base path` does not move the settings file

**Symptom.** You change `Base path` in `Settings > Storage`, the app accepts it, and `app-settings.json` stays in `%APPDATA%\AIContextBuilder`.

**Cause.** This is by design: the settings file must be readable before the configured path is known, so it always lives at the default location. The base path is honored for the database, templates, node overrides and backups, and it takes effect after a restart.

**What to do.** Use `Settings > Storage` to see which file the app actually uses (`App settings file`). If you want your data somewhere else, change `Base path` and restart; the settings file itself stays where it is.

#### The GUI and the MCP server share one database

**Symptom.** The `MCP Usage` page changes on every visit, a backup is `-partial` while an MCP host is running, or a schema migration takes effect immediately in a running process.

**Cause.** The desktop app and the MCP server can point at the same database file, and both write to it while they run. This is the normal case and explains all three behaviors: the usage panel reloads on every activation, the archiver skips a file that is currently held open, and a migration applies to every running process at once.

**What to do.** Nothing to fix — but if you want the two fully independent, point them at different database files. Note that the MCP server tolerates a database written by a newer version and reports the drift, while the desktop app refuses to start on one.

---

[&larr; 10 Dialogs](10-dialogs.md) &middot; [Contents](README.md)
