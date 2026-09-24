# Changelog

Versions follow `Major.Minor.Series.Build`. The build number rises by one for every
change that lands, so gaps between published versions are normal — not every build is
released.

## 0.5.464.40 — `resolve_injection` stops giving confident wrong answers

Four builds (`.37` to `.40`) that all repair the same tool. Every one of them replaces an answer
that looked definite with one that is either correct or openly says it does not know — which is
the point: a `false` that means "nobody does this" is far more expensive than a "cannot tell".

**Who is affected.** The MCP server and the `aicb` CLI. **The desktop app is unchanged** — it does
not use this analyzer. Saved snapshots stay valid; there is no database change and no re-analysis.

- **`consumedAsCollection` is answered for every query, not only for a conflicting one.** The field
  says whether anything consumes a service as a set (`IEnumerable<T>` in a constructor,
  `GetServices<T>()`). It used to be computed only where it could also downgrade a registration
  conflict, and read `false` everywhere else — so a service registered once, or registered several
  times through factories, always answered `false` no matter how many consumers took the whole set.
  Measured on this project's own code, two services answered `false` while a constructor took each
  of them as `IEnumerable<T>`.
- **A factory registration that *returns* its object is now resolved.** `AddSingleton(sp => Foo.Build())`
  and the block form `AddSingleton(sp => { ...; return Foo.Build(); })` used to leave the registration
  with no type name at all — and in this single-argument form the produced type *is* the service, so
  the whole registration answered to no name. `AddSingleton(sp => new Foo())` always worked; the
  difference was only that one returns instead of constructing. A block body is read only when all of
  its `return` statements agree, and a `return` inside a nested lambda or local function is correctly
  ignored.
- **A registration the scanner can see but cannot parse is now disclosed as such.** Before, such a
  site was invisible, and the answer explained the resulting zero with *"Autofac, Castle Windsor and
  Scrutor are out of scope"* — pointing away from the file that actually held the binding. The note
  now separates *"a Microsoft-DI registration was seen here but its type could not be read"* from
  *"no Microsoft-DI registration was found"*, and names the site.
- **Optional and nullable collection parameters count.** `IEnumerable<IFoo>? foos = null` — a consumer
  that tolerates an empty set — was not counted as consuming the collection, and neither was
  `IEnumerable<IFoo?>`.
- **Consumers declared in test projects no longer count by default.** This one changes an answer you
  may have relied on: collection consumption now obeys the same `includeTests` filter the registration
  list has always obeyed. Before, a test fixture taking `IEnumerable<T>` could mark a genuine
  production conflict between two registrations as deliberate, hiding it. Pass `includeTests=true` to
  get the old, solution-wide reading.

If your client caches tool descriptions, reconnect it once — the text of `resolve_injection` changed
along with its behaviour.

## 0.5.464.36 — internal wiring, nothing you can see

A plumbing release. No tool changes its answer, the CLI and the desktop app behave
exactly as in 0.5.464.35, and there is no reason to update in a hurry.

- **The MCP server now hands its insights service the queued-work store.** The server
  builds that service by hand instead of letting the container fill it, and the hand-written
  argument list had been leaving out one of the three optional stores. Nothing reported
  anything wrong, because no MCP tool reads the queued-work axis yet — the omission would
  only have surfaced the day one did, as an empty answer that reads like "nothing is
  queued" rather than "not connected". The desktop app was never affected: it builds the
  same service through the container, which had been filling the argument all along.
- **One consequence worth stating:** in a setup where the MCP server is pointed at a
  database, an insights run now performs one additional indexed read against it — the same
  read the desktop app already does — and currently discards the result. Analysis still
  runs entirely on your machine, and the MCP server still writes nothing.

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
