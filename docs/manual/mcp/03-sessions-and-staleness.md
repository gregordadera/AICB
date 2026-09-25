[AICB – MCP Server](README.md) &middot; chapter 3 of 12

# 3 Sessions and staleness

A **session** is one analyzed solution that the MCP server holds in memory. Every tool that answers questions about code reads from that model; it is produced by a full analysis of the solution and stays in the server process for as long as the session lives. Because you keep editing while the server keeps answering, the model can fall behind the files on disk. The server therefore tracks how old each answer's model is, discloses it on the response, and can repair it - automatically or on request.

This chapter covers how sessions are created and identified, how they expire, how staleness is disclosed and repaired, how source staleness differs from reference incompleteness, and which timing constants you can tune.

## 3.1 Starting a session: the solution path as a session ID

Most tools that need a session declare a `sessionId` parameter, and that parameter accepts **two forms**. The two-session comparison tools name their sides instead: `semantic_diff` uses `sessionA`/`sessionB`, `diff_review` uses `sessionBefore`/`sessionAfter`, and `verify_claim` uses `baselineSessionId`/`changedSessionId`; each side accepts the same two forms.

| Form | Example | Behavior |
|---|---|---|
| A session ID | the string `analyze_solution` returned | Uses that cached session. |
| An absolute solution path | `C:\work\MyApp\MyApp.sln` | **Self-init**: the server analyzes the solution on first access and caches it. |

Self-init means `analyze_solution` is **optional**: you can pass the solution path to any session-bound tool directly, and the first call performs the analysis. The recognized extensions are `.sln`, `.slnx` and `.slnf` (a solution filter is opened like a solution). A session ID has no such extension, so the two forms can never be confused.

Concurrent tool calls that pass the **same** solution path are serialized: the solution is analyzed once, and the other callers wait for that one analysis instead of starting their own. A waiter is not left hanging indefinitely. If the wait exceeds the load-gate limit (default 45 seconds, see "Timing constants via environment variables"), the call is refused with an error that names which analysis is running and how long it has been running, states that the call never started because it was queued, and suggests waiting for the running analysis or using a smaller solution or a `.slnf` filter.

If a session reference does not resolve, the error names the cause it actually has. The three cases are distinguished:

| What you passed | Message |
|---|---|
| Something with no solution extension | `'…' is neither a known session_id nor an absolute .sln/.slnx/.slnf path.` - if you meant a session ID, it is unknown or expired; call `analyze_solution` first. |
| A solution extension, but no file at that path | `No solution file at '…'.` - the path must be **absolute**. The message states explicitly that this is **not** an expired session. |
| An existing solution file | This host cannot self-initialize from a path; call `analyze_solution` and pass the returned ID. |

## 3.2 The session cache

Sessions live in one cache per server process. Each session pins a warm workspace and the analyzed graph, so the cache is deliberately bounded:

| Setting | Default | Meaning |
|---|---|---|
| Time to live | **90 minutes** | Sliding from the last access: every tool call that uses the session resets the clock. |
| Maximum sessions | **8** | Hard memory bound. On overflow the least recently used session is evicted; the session just created is never the one evicted. |
| Sweep interval | **5 minutes** | A background sweep releases expired sessions even when no tool call touches them. |

Expiry or eviction releases the workspace behind the session. The next call with the same solution path (or a new `analyze_solution`) analyzes the solution again from scratch.

Within one server process, sessions are identified by their **solution path** (case-insensitive). If several cached sessions exist for the same path, a live one is preferred over a recalled one, and otherwise the most recently used one. A second server process has its own cache and analyzes again.

Two tools let you inspect the cache:

- `list_sessions` - all currently cached sessions that have not expired, each with its ID, solution path, project count and last access. It takes no arguments.
- `inspect_session` - the metadata of one session, addressed by its `sessionId` (solution path, project count, file-set hash, last access).

### Configuring the session cache

The cache parameters can be changed without rebuilding, in two stages that are applied at server start. The cascade is **built-in defaults < `aicb.mcp.json` < environment variable**.

The central server configuration file is `aicb.mcp.json` in `<ApplicationData>/AIContextBuilder/` - on Windows `%APPDATA%\AIContextBuilder\aicb.mcp.json`. It is read-only for the server: you edit it by hand, and the server reads it at start. The file is hand-written JSON, so property names are case-insensitive and comments and trailing commas are tolerated. A missing file means "no override". A broken file is reported as a warning and the server starts on the defaults - so a file you believe is in effect can silently not be.

```json
{
  "sessionCache": {
    "ttlMinutes": 90,
    "maxSessions": 8,
    "sweepMinutes": 5
  }
}
```

Only the fields you set override anything; unset or non-positive values keep their default.

The environment variable `AICB_MCP_SESSION` overrides the same three values for one server process. It takes a comma-separated `key=value` list:

```text
AICB_MCP_SESSION=maxSessions=4,ttlMinutes=120
```

| Key | Meaning | Unit |
|---|---|---|
| `ttlMinutes` | session time to live | minutes |
| `maxSessions` | maximum number of cached sessions | count |
| `sweepMinutes` | interval of the background sweep | minutes |

Keys you do not set keep their default; unrecognized keys and values that are not a positive integer are ignored.

## 3.3 Recalled sessions

The memory tools persist an analyzed model in an aicb database and bring it back later - even in another process, and without running Roslyn:

| Tool | What it does |
|---|---|
| `remember_codebase` | Analyzes a solution and persists the model as a snapshot. Returns a **live** session ID you can use immediately. Requires `solutionPath` and `dbPath`. |
| `list_remembered` | Lists the codebases remembered in a database (latest snapshot time, file-set hash, whether a usable model payload is present). Requires `dbPath`. |
| `recall_codebase` | Rehydrates the latest snapshot **without Roslyn** and returns a recalled session ID. Requires `solutionPath` and `dbPath`. |
| `refresh_remembered` | Re-analyzes a recalled session live, restores line numbers and full insights, and re-persists the snapshot. Requires `sessionId` and `dbPath`. |

A recalled session behaves differently from a live one, and the differences are visible in its metadata:

- It has **no live workspace**; its origin is reported as `Recalled` (a live session reports `Live`).
- `lineNumbersAvailable` is `false`, and insights that depend on line numbers are degraded.
- The persisted payload does not carry the layer profile; a live analysis (`refresh_remembered`, or a fresh `analyze_solution`) produces a fully live session.
- Time to live and eviction work exactly as for live sessions.
- Tools that need the live Roslyn workspace reject a recalled session with a message pointing to `refresh_remembered` (or `analyze_solution`). This includes `refresh_session` - a recalled session cannot be refreshed by it.
- Snapshots written by older versions may carry no file-set hash. The staleness check then reports "unreliable" rather than "current" and stays silent (see "The staleness disclosure").

`recall_codebase` also tells you whether the snapshot still matches the disk: it reports `stale: true` when the file set drifted, or the payload schema or the analyzer identity differs, and recommends `refresh_remembered` for a live re-analysis. The recalled model is served either way - that is the point of recalling.

## 3.4 How tools refer to a session

The tool surface uses five shapes:

| Shape | Tools | Notes |
|---|---|---|
| One session | the majority of tools | the parameter is named `sessionId` and accepts both forms above |
| Two sessions | `semantic_diff` (`sessionA`, `sessionB`), `diff_review` (`sessionBefore`, `sessionAfter`), `verify_claim` (`baselineSessionId`, `changedSessionId`) | each side accepts self-init |
| One session plus a stored snapshot | `compare_with_previous`, `diff_public_contract` | the session is the "after" side; the baseline is a snapshot saved earlier with `save_session` |
| No session | `server_info`, `list_skills`, `list_mcp_profiles`, `usage_report`, `docs`, `list_sessions`, `list_insight_producers` and the database-browsing tools | take no solution argument |
| A path instead of a session | `analyze_solution` and `remember_codebase` take `solutionPath`; `recall_codebase` takes `solutionPath` plus `dbPath`; `compare_public_api` takes two DLL paths | |

## 3.5 The staleness disclosure

Every response of a session-bound tool can carry a disclosure of how old the model behind it is. This matters because a "0 callers" answer out of a pre-edit graph looks exactly like a real zero, and a `find_usages` answer from a graph that is 40 minutes old is otherwise indistinguishable from a fresh one.

The check compares the **source files on disk** with the files the session was analyzed from and, for recalled state, also checks the persisted analyzer identity against the running analyzer. It has three states:

| State | Meaning |
|---|---|
| `Unknown` | No usable answer (for example an unreadable solution folder). Kept separate from "current" on purpose: "I do not know" must not be reported as "changed". |
| `Current` | The file set on disk matches the one the session was analyzed from. |
| `Stale` | Source files under the solution folder have moved since analysis, or the recalled session's analyzer identity differs from the running analyzer. |

Only `Stale` produces text, and the response is otherwise left byte for byte unchanged. An "everything is fine" note is deliberately never emitted: the check can only prove currency at the moment it last looked, not at the moment it answers.

The disclosure has two grammars, one per response shape:

- **JSON responses** get a `staleness` member spliced into the object. A response that is structured but not a JSON object (a top-level array) is left untouched.
- **Markdown responses** get a leading `<!-- staleness: … -->` comment, so the caveat is visible before the document rather than after it.

A plain stale disclosure looks like this:

```json
"staleness": {
  "stale": true,
  "checkedAtUtc": "2026-09-21T10:12:44.1234567Z",
  "hint": "Source files changed since this session was analyzed, so this answer comes from the pre-edit graph - call refresh_session for a current one."
}
```

After a successful automatic re-analysis (see "Auto-refresh: Off, Reactive, Proactive") the member says so instead, and the answer is current:

```json
"staleness": {
  "stale": false,
  "autoRefreshed": true,
  "mode": "full-reload",
  "hint": "Source files had changed, so this session was re-analyzed automatically (full reload) before this call was answered - this answer reflects the code as it is now."
}
```

If the automatic re-analysis failed, the member names the failure and the answer still comes from the old graph:

```json
"staleness": {
  "stale": true,
  "autoRefreshFailed": "IOException",
  "checkedAtUtc": "2026-09-21T10:12:44.1234567Z",
  "hint": "Source files changed since this session was analyzed and the automatic re-analysis FAILED (IOException), so this answer comes from the pre-edit graph - call refresh_session to retry it explicitly."
}
```

The fields are:

| Field | Meaning |
|---|---|
| `stale` | `true` when the answer comes from a graph behind the disk, `false` when the automatic path repaired it. |
| `autoRefreshed` | Present and `true` when the server re-analyzed before answering. |
| `mode` | Which path the re-analysis took: `incremental` (document texts replayed, no workspace reload) or `full-reload`. Only present with `autoRefreshed`. |
| `autoRefreshFailed` | The exception **type** that ended a failed automatic attempt (not a message). |
| `checkedAtUtc` | When the check last looked at the disk. Absent after a successful automatic re-analysis. |
| `hint` | The same sentence as the Markdown comment: what happened and what to do. |

Notes:

- The check is throttled (default 5 seconds, see "Timing constants via environment variables"). A `Stale` verdict is re-served without reading the disk again until a fresh reading supersedes it. `checkedAtUtc` therefore names the last look, not the moment of the change; the disclosure deliberately does not claim a "changed since" time, because a file-set fingerprint knows *that* something moved, never *when*.
- A disclosure is added to any call that carries an argument whose name contains `session` and that resolves to a cached session. This includes the two-session comparison tools; there, the message names which side is stale (`the session passed as sessionA, sessionB`).
- `refresh_session` is not exempt: the check runs **after** the tool, so a successful refresh classifies as current and produces no note - while a file written *during* the re-analysis is still disclosed.
- A result that is an error is not decorated; its age is irrelevant and a note would only crowd out the failure.
- A recalled session gets a different remedy in the same place: the note points to `refresh_remembered` instead of `refresh_session`, because `refresh_session` rejects a recalled session.
- `get_diagnostics` additionally leads its answer with `verdict: "stale"` and a `verdictReason` when it computed from a graph known to be behind the disk - placed before the counts so that `errorCount: 0` is not read as a clean bill.

**Never infer freshness from which tool you called.** Read the disclosure that the response carries.

## 3.6 Auto-refresh: Off, Reactive, Proactive

The auto-refresh mode decides **who pays for the re-analysis** when a session has drifted. Detection runs in all three modes; what differs is whether anything acts on it.

| Mode | Who pays | Behavior |
|---|---|---|
| `Off` | nobody | Drift is disclosed and left in place. Repair happens only when you call `refresh_session` yourself. |
| `Reactive` | the caller | Drift is noticed when a read tool is about to answer; the re-analysis runs first and the answer comes from the current graph. The caller waits for the re-analysis (seconds on a large solution). |
| `Proactive` | a background watcher | A file watcher starts the re-analysis once saving has gone quiet, so the next tool call usually finds a current graph and pays nothing. |

The mode is a property of the **active MCP profile** and is set in the profile editor in the GUI. The shipped rule is:

- **`Reactive` is what the normal creation paths produce.** Every built-in profile and a custom profile created with **Add New** carries `Reactive`. The GUI's **Duplicate** action does not copy this field; its clone therefore resolves to `Off` unless you set it.
- **`Off` is what an absent field means for custom/imported profiles and overridden or hidden built-ins.** A non-overridden, non-hidden built-in row is self-healed on the next load to the shipped value, which is `Reactive`; other old or imported profiles without the field resolve to `Off`.

A change to the mode takes effect at the next server start; reconnect or restart the server after editing the profile.

For one server process, the environment variable `AICB_MCP_AUTO_REFRESH` overrides the profile. The cascade is **built-in default < profile < environment variable**, resolved once at server start.

| Value | Mode |
|---|---|
| `off`, `0`, `false`, `no` | `Off` |
| `reactive` | `Reactive` |
| `proactive`, `1`, `on`, `true`, `yes` | `Proactive` |

Notes:

- An unrecognized value is **ignored**: the profile's value stands. A typo can therefore never switch a mode on - and never switch the shipped mode off.
- The truthy legacy spellings (`true`, `1`, `on`, `yes`) mean `Proactive`, not `Reactive`.
- The mode does not change which tools are exposed. Only `refresh_session` changes character: under `Reactive` and `Proactive` it is usually redundant, but calling it remains correct in every mode.
- There is no timeout cap on a refresh. A call may take as long as the re-analysis needs; the alternative - a cap on an estimated duration - would abort work that was about to succeed.

What the automatic path does and does not touch:

- It acts only on a session that has actually drifted **and** has a live workspace. A recalled session is skipped, because no refresh could succeed on it; the disclosure then names `refresh_remembered` as the route.
- Tools that perform their own analysis (such as `refresh_session`) are exempt, so a refresh still reports your edit as its own finding instead of being pre-empted.
- On the two-session comparison tools, the **worst** outcome is reported: if one side could not be refreshed, the note says so, even if the other side succeeded.
- The automatic path never forces. It fires on drift the check detected, so there is nothing to override; `force` is the manual escape hatch.
- **Fail-open, always.** Every failure path leaves the tool call intact and answers from the old graph, with a disclosure that says the automatic re-analysis failed and names the exception type. An automatic mode that made calls fail harder than the manual route would be worse than the drift it removes.
- After a successful automatic re-analysis the disclosure is emitted even though the answer is now current (`stale: false`), because a wait the caller did not ask for should not be silent.

## 3.7 The change watcher

The proactive mode adds a file watcher on the solution folder (including subdirectories). It observes C# saves and raises **one** signal once writing has stopped.

- **Quiet period (debounce): 15 seconds**, overridable with `AICB_MCP_DEBOUNCE_MS`. Every further save restarts the window, so a burst of edits produces one re-analysis rather than one per keystroke.
- **Only `.cs` files trigger it.** A change to a `.csproj` or `.xaml` file is not a proactive trigger; it is still caught at the next tool call.
- **The watcher is a trigger, never the source of truth.** File watchers can drop events under load (a checkout, a build, a stash). A dropped or overflowed event is treated as an ordinary signal - "something moved" - and the file-set comparison decides whether anything is actually stale. A missed event can therefore delay a refresh, never hide one.
- Watchers are armed **after** the tool call, for the sessions that call touched. Arming earlier would skip the call that creates a session.
- **Failure is silent and falls back to the reactive path.** If the watcher cannot be created (an unreachable folder, a platform watch limit), or an event is lost, the drift is still found at the next tool call and repaired there under `Reactive`/`Proactive`. The visible symptom is simply that the staleness disclosure appears again - a working watcher is the case where no disclosure appears at all.

## 3.8 One refresh at a time

A session has at most **one** refresh in flight. `refresh_session` and the automatic path share the same election: a call that arrives while a background refresh is already running **joins** it instead of starting a second re-analysis of the same session. The worst case for the caller is a partial wait, not a doubled one.

`refresh_session` takes:

| Parameter | Default | Meaning |
|---|---|---|
| `sessionId` | required | the session ID (or a solution path, via self-init) |
| `force` | `false` | Re-analyze even when no source file has changed. |

It returns `{ changed, reason, session, mode }`:

- `changed` - `false` when nothing was re-analyzed; the `reason` then says why (the file-set hash was unchanged, or every file that moved was touched without a content change).
- `mode` - `incremental` when document texts were replayed without a workspace reload, otherwise `full-reload`. It is **absent** when nothing was re-analyzed.
- `session` - the session metadata after the refresh.

Notes:

- Calling `refresh_session` after editing is cheap to do speculatively: an unchanged file set skips the expensive re-analysis. A file whose timestamp moved while its text is still the analyzed text (a save without an edit) does not count as a change either.
- The incremental path can stop engaging without any visible symptom - answers stay correct, calls just get slow again. The `mode` field is how you notice.
- `force: true` costs a full workspace reload. Use it after a restore or build that was meant to repair unresolved references: that state lives in build output, which the file-set check cannot see, so an ordinary call can legitimately answer "unchanged". After a restore or build, an analysis that reported unresolved references retries once by itself; `force` is the deterministic way to demand it.
- A recalled session is rejected: `refresh_session` has no live workspace to refresh. Use `refresh_remembered` (or `analyze_solution`).

## 3.9 Staleness or incompleteness?

Two failure pictures look similar but need different reactions. The staleness check compares **source files**; incompleteness is about **project references** that the analysis could not resolve.

| Picture | What is out of date | How it looks | What to do |
|---|---|---|---|
| **Source staleness** | the source files on disk differ from the files of the analysis | `not_found` on a type you just wrote (the file was never in the model); fan-in answers from a pre-edit graph | `refresh_session` - under `Reactive`/`Proactive` usually nothing, because the server repairs it first |
| **Reference incompleteness** | the model exists, but not all project references could be resolved | plausible-looking but **too short** fan-in answers; a leading incompleteness note on the affected tools; `incompleteProjects` in `get_diagnostics`; `verdict: "inconclusive"` when a strict majority of projects is incomplete | restore/build the solution, then `refresh_session(force: true)` |
| **Analyzer drift** | the server binary is old; the sources are untouched | nothing - the staleness check is correctly silent here | rebuild or reinstall the server; `server_info` reports the ANALYZER DRIFT line |

Because the staleness check compares source files, it is silent by design when the binary is the stale part: an older analyzer keeps answering with its old facts and trips no source check. That is why `server_info` exists alongside it - the two signals see disjoint things.

## 3.10 The `dbPath` parameter

Many database-bound tools take an optional `dbPath` (for example `save_session`, `apply_solution_config`, `analyze_solution`, `list_insights`, `diff_review`). The resolution is:

**explicit `dbPath` > the server's standard config DB > none.**

When you omit it, the server resolves the standard config DB - the same database the GUI uses - if it resolved one at start; otherwise there is no default. An explicitly passed path always wins.

This matters most for the tools that **write**:

- Without `dbPath`, a writing call targets the live database of the GUI. `save_session` writes a manual snapshot into it; `apply_solution_config` additionally writes a git-tracked `.aicb.json` sidecar next to the solution; `diff_review` writes a regression log only when you pass `recordRegressions: true`.
- Every tool states its own write behavior in its description. Pass an explicit `dbPath` whenever you mean a different database.

For `analyze_solution`, a resolved database also supplies the analysis settings: its active namespace-exclusion list, its test-detection profile and (unless you pass an explicit `layerProfile`) its layer-mapping profile. The layer and test profiles travel with the session. Namespace exclusions travel only on the DB-free sidecar path; exclusions supplied by a database are applied to the initial analysis but are not retained for a later full refresh, a known limitation.

## 3.11 Timing constants via environment variables

Three wall-clock constants of the session machinery can be set per server process with environment variables. All three are in **milliseconds**.

| Variable | Overrides | Built-in default |
|---|---|---|
| `AICB_MCP_DEBOUNCE_MS` | quiet period of the change watcher before it triggers a background re-analysis | `15000` (15 s) |
| `AICB_MCP_STALENESS_WINDOW_MS` | throttle window of the staleness check: how long a "current" answer is re-served before the disk is read again | `5000` (5 s) |
| `AICB_MCP_LOAD_WAIT_MS` | how long a caller waits behind a first-touch analysis of the same solution before it is told what is loading | `45000` (45 s) |

Notes:

- A value that is unparseable, negative or **zero** falls back to the built-in default. Zero is refused rather than honored because both consumers would read it as "no wait at all": a zero debounce would fire a full re-analysis on every keystroke, and a zero throttle would put the directory walk on every single tool call.
- There is deliberately **no upper bound**. A nonsensical value costs the operator who typed it.
- `AICB_MCP_LOAD_WAIT_MS` is chosen against the **client's** own deadline, not against any load time: a message that arrives after the client has already given up is worthless. Only the MCP server applies this bound; the GUI and the CLI wait without a limit.
- The three variables belong to the server process. They are read when the value is first needed, so they must be set in the environment that starts `aicb mcp`.

---

[&larr; 2 Setting up an agent: aicb init](02-setting-up-an-agent-aicb-init.md) &middot; [Contents](README.md) &middot; [4 Profiles, pools and facets &rarr;](04-profiles-pools-and-facets.md)
