# Changelog

Versions follow `Major.Minor.Series.Build`. The build number rises by one for every
change that lands, so gaps between published versions are normal - not every build is
released.

## Unreleased

### New repository address and MCP Registry name

- **The repository moved to `github.com/gregordadera/aicb-roslyn-mcp`** (it was
  `github.com/gregordadera/AICB`). GitHub forwards every old link, clone URL and release download,
  so nothing you set up breaks; update bookmarks and git remotes when convenient. The nuget.org
  package `AIContextBuilder` and the `aicb` command keep their names.
- **The MCP Registry lists the server as `io.github.gregordadera/aicb-roslyn-mcp`.** The previous
  entry `io.github.gregordadera/aicb` keeps its published versions and is marked deprecated with a
  pointer to the new name. Clients that already run the server need no change: they start the
  `aicb` command, not the registry name.
- The desktop app's About page and the `docs` tool link to the new address. First included in
  build 0.5.464.71.

## 0.5.464.66 (2026-09-28) - SQLite closes CVE-2025-6965, `get_diagnostics` names what it could not compile, `prepare_task` stays within a budget

**Who is affected.** Everyone gets the SQLite security update and the editorial license version 0.6.
Everything else concerns the MCP server and the `aicb` CLI: `get_diagnostics`, `prepare_task`,
`find_tests_for`, `review_context`, `instantiation_sites`, `symbol_metrics`, `resolve_injection`,
`impact_of_change`, `find_dead_code` and `list_insights`. No database change; saved snapshots stay
valid. The local-function fix below takes effect when a solution is analyzed again. If your client
caches tool descriptions, reconnect it once - several descriptions changed.

### Security

- **The bundled SQLite library moves from 3.41.2 to 3.53.3**, which fixes CVE-2025-6965
  (GHSA-2m69-gcr7-jv3q, severity high). aicb uses SQLite only for its own local database and runs
  only its own SQL, so the practical exposure was low - but the vulnerable native library shipped in
  the NuGet tool package, the installer and the portable ZIP, where a vulnerability scanner reports
  it. Existing databases open unchanged; no re-analysis is needed. `THIRD-PARTY-NOTICES.txt` lists
  the updated `SQLitePCLRaw` 2.1.13 packages.

### Licensing

- **EULA version 0.6 is an editorial version with unchanged terms.** The German part now uses real
  umlauts instead of transliterations, and dashes became plain hyphens. Prices, thresholds and every
  right and obligation are the same as in version 0.5. The immutable reference is the tag `eula-v0.6`.

### `get_diagnostics` says what it could not compile

- **A failed design-time build is disclosed in `designTimeBuildFailures`.** When MSBuild fails while
  loading a project - a version task on a shallow clone is the typical case - the project is still
  compiled with what could be read, so its compiler options can be incomplete, and that moves the
  counts in both directions. The answer now lists each affected project file with the loader's own
  message and a note naming the remedy, whenever the scope reaches such a project or one of its
  dependents. A shared failure is quoted once, not once per project.
- **Generated code the analysis could not produce is disclosed in `generatedCodeGaps`.** A project can
  compile without code a source generator or the WPF markup compiler would have written: a generator
  from a project in the solution that was never built (`not-built`), an analyzer file nobody produces
  (`not-found`), a generator built for a newer compiler than the analysis host (`cannot-load` -
  building does not fix that one), a generator that failed to load for another reason (`load-failed`),
  or WPF code-behind whose markup half is missing. Each entry carries its evidence and affected
  dependents; `diagnosticsInAffectedProjects` gives the magnitude and `diagnosticsMarked` counts the
  items marked `missingGeneratedCode: true` because they sit exactly where the code is missing.
- **A file-scoped call names the incomplete project its marked items inherit from.** Under a file-path
  scope, an incomplete project is listed whenever a counted diagnostic in the scope sits downstream of
  it, so a `cascadeFromIncomplete` item always has its cause named. `suppressedDiagnosticsTotal` now
  appears whenever `incompleteRatio` does, and a scoped call reaches `inconclusive` only where the
  solution-wide call would too.

### `prepare_task` stays within a budget

- **The template render has a default ceiling.** When neither the MCP profile nor the template sets a
  budget - true for every built-in - the answer could run to hundreds of thousands of characters, and
  to millions for a plain-language goal. The default is now a hard ceiling sized to what an MCP client
  shows inline, and the manifest in front of the context counts toward it. On a goal naming one type,
  about 304 000 characters became about 15 000. A budget you configure keeps its tolerance.
- **A goal that names a declared symbol exactly seeds on the symbols it names.** Its other words still
  steer the trimming but no longer pull in unrelated members - an ordinary word such as "works" or
  "where", or a capitalized first word of the sentence, used to anchor on a like-named method.
- **The type the goal names stays in the answer** even when the budget is tight; if its source does
  not fit, it is shown as structure rather than dropped.
- **The frontmatter stays parseable.** The pruning and budget notes are now placed after the YAML
  frontmatter instead of in front of it.

### Tests and construction sites

- **`find_tests_for` counts a test that builds the queried type.** Two new `matchReason` values,
  `constructs` (the test creates the type: `new X(...)`, target-typed `new()`, a record `with`) and
  `constructs-via` (through one method it calls), apply to type and constructor queries (`Type.Type`)
  and rank after the `invokes` tiers. Building a type does not show that a particular member ran, so
  member queries are unchanged.
- **`review_context` caps its covering tests like `find_tests_for` does** - 50 per symbol, with
  `coveringTestsTotal` and `coveringTestsTruncated`. One symbol could previously return well over a
  hundred rows, and a large solution several thousand in one answer.
- **`instantiation_sites` separates test from production.** Every site carries `isTestProject`, and
  `createdByTests` and `injectedIntoTests` stand beside the totals they split, counted over all sites
  and not just the returned page. "Does anything but a test construct this type?" is now one call.
  The classification follows the session's configured test projects.

### Corrected answers

- **Calls from constructors and property accessors in test projects count as test calls.**
  `impact_of_change` no longer counts them as production impact, and `find_dead_code` reports a
  method that only such test code reaches as unused in production.
- **Local functions of the same name in different methods are no longer merged** in call graphs, so a
  caller of one no longer appears as a caller of the other.
- **`list_insights` drops two false alarms:** `nameof(Task<T>.Result)` is not a blocking wait on a task,
  and `Enumerable.Empty<T>()` inside a loop is not a per-iteration LINQ cost.
- **`resolve_injection` no longer matches a factory registration that returns an anonymous object**
  against an unrelated service. It reports no match, and its note points at the factory site.
- **`symbol_metrics` carries `metricMeaning`** on every answer: cyclomatic and cognitive complexity
  describe code shape, not runtime cost.

### Documentation

- The nuget.org package page now matches this repository's README, names the MCP server and lists its
  search terms. The `aicb-csharp-context` skill explains the new `constructs` reasons of
  `find_tests_for`; `aicb init --force` refreshes an installed copy.
- The general manual's licensing chapter names EULA version 0.6. The printable PDFs still describe
  product state 0.5.464.43.

## 0.5.464.56 (2026-09-26) - the license that ships is the license that is published, and six answers stop hiding what they left out

**Who is affected.** Everyone: the shipped license text moves from EULA v0.3 to v0.5. Beyond that, this
release is mostly about MCP answers and exported Markdown telling you what they omitted - `find_usages`,
`find_symbol`, `symbol_signature`, `architecture_overview`, `solution_config_status`,
`check_solution_config_drift` and `pack_for_task`. No database change, no re-analysis; saved snapshots stay
valid. If your client caches tool descriptions, reconnect it once.

### Licensing

- **The binding agreement shipped with the product is now EULA v0.5**, the same version published here.
  Installer, portable ZIP and the NuGet package carry it, with `LICENSE.txt` as its plain-language summary
  beside it. What v0.4 and v0.5 added over v0.3: commercial licenses **start at EUR 25 per licensed
  developer per month**, a commercial agreement can include defined response and security-fix targets,
  version maintenance, prioritized general product improvements and source-code review under NDA. The
  free thresholds are unchanged - 100 employees, EUR 10 million annual turnover, 21 developers - and so is
  everything about enforcement: no license server, no activation, no timer, no threshold data leaving the
  machine. The 90-day transition period remains contractual text only.
- The nuget.org package page now states the same terms as this repository.

### Answers that now disclose what they omitted

- **`architecture_overview` leads with a `<TRUNCATION>` block** when the document was cut: how many sections
  were capped, how many entries are shown out of how many, and one `SECTION: shown of total` row per cut
  section. Until now the per-section `+N more` lines each named one section and added up for nobody - on a
  large solution that meant 640 of 8706 entries were shown with no statement anywhere that the rest existed.
  The frontmatter of a truncated document stays where it belongs, so `type`, `title` and `description` are
  still parseable.
- **`find_usages` reports `selfReferences`** - how many of the listed users are declared on the queried
  symbol's own type - and adds a note when *all* of them are. That is the answer that reads as outside
  dependence while nothing outside actually depends on the symbol. Self-references are disclosed, never
  filtered out: a self-reference is a real reference.
- **`find_symbol` and `symbol_signature` say when generated C# was skipped.** Generated sources under `obj/`
  stay out of the analysis on purpose - the same file often exists once per target framework, so admitting
  them would multiply every generated type - but a zero-hit answer used to read as "no such type". A
  zero-hit answer on a solution that has such files now says so in `generatedSourcesNote`.
- **A broken `.aicb.json` no longer reads as "nothing configured".** `solution_config_status` and
  `check_solution_config_drift` carry `sidecarProblem` when the sidecar next to the `.sln` exists but cannot
  be used, and they keep an invalid file apart from a locked or unreadable one - a typo is yours to fix, a
  lock is transient. Until now a broken sidecar produced an answer byte-identical to having none, three axes
  reporting `source: "none"`, which is a positive claim that nothing is configured. A healthy answer is
  unchanged.

### Corrected and smaller answers

- **`returnKind` names the return type's family, not its arity.** A plain `Task` was reported as `object`
  while `Task<T>` was `task`, and non-generic `IEnumerable`, `IList`, `ICollection`, plus
  `IReadOnlyCollection` and `IAsyncEnumerable`, fell out of `collection`.
- **`find_usages` on a bare member name no longer mixes namesakes into the self-reference count.** Where a
  short name matches members on several types, the count is omitted rather than reported wrongly; a
  type-qualified query answers as before.
- **Exported Markdown carries a smaller `<COMPRESSION_LEGEND>`.** The legend now explains only the notations
  the finished document actually contains. On a single-symbol export it had grown to about a third of the
  whole document while explaining blocks that were not in it.
- **`pack_for_task` fills the budget it was given, also on slices that had to degrade.** A request whose
  content had to be reduced below the full-code form could settle well under target - measured at about 85 %
  of a 25 000-token budget, below the 92 % the tool aims for; the same request now lands at about 96 %.

### Documentation

- The public documentation gained a measured cold/warm scale benchmark on three public solutions (Serilog,
  MahApps.Metro and RavenDB, cold and warm load, peak memory), a clearer statement of what the static
  analysis does and does not cover, a safe agent workflow, and the licensing pages for the new EULA version.
- The three reference manuals still describe product state 0.5.464.43; their licensing chapter is current
  with EULA v0.5. The changes listed above are described here in the changelog.

## 0.5.464.44 (2026-09-25) - usage check skill and complete browser-readable manuals

**Who is affected.** Users who run `aicb init --skills=all`, and anyone reading the public
documentation. The analysis engine, MCP tool answers, desktop app and saved snapshots are unchanged.

- **A fourth optional Agent Skill ships:** `aicb-usage-check` calls `usage_report` at the end of a
  task and summarizes which AICB tools were actually used, which offered tools went untouched, and
  what the calls cost. It is deliberately opt-in alongside the review pair; the default
  `aicb init` still writes only `aicb-csharp-context`. Run `aicb init --skills=all` again in an
  existing project to install it there.
- **The three reference manuals are now readable as Markdown in the browser and by coding agents,**
  one chapter per file, with the printable PDFs beside them under stable names. The manuals describe
  product state 0.5.464.43; build .44 changes only the guard described next.
- **The package page can no longer silently omit a shipped skill.** Every release now checks the
  install page, the CLI help and the package README against the list of skills that actually ship.
  This closes the gap that briefly left the nuget.org page describing only three skills.

## 0.5.464.41 (2026-09-24) - `resolve_injection` says how visible a service is in constructors

**Who is affected.** The MCP server and the `aicb` CLI. **The desktop app is unchanged.** Saved
snapshots stay valid; no database change, no re-analysis.

- **New field `constructorConsumerCount`**: how many distinct types take the queried service as a
  plain constructor parameter. It is on every answer, and a zero is a result rather than a missing
  field - until now a service half the solution injects and one nobody injects produced the same
  answer, because only *optional* constructor parameters were ever reported.
- **Read it as a description, not a verdict.** It counts constructor parameters and nothing else, so
  a service obtained through `GetService<T>`, built inside a factory lambda, or reached by reflection
  or XAML counts 0 while being thoroughly alive. The first live reading makes the point better than
  any warning: a service that almost everything takes as a factory delegate reports **2**. For "is
  this used at all", `find_usages` remains the tool.
- An optional parameter counts here too, and such a consumer still appears on `optionalDependencies`;
  collection consumption keeps its own field and is not counted twice. Consumers declared in test
  projects follow the existing `includeTests` filter.

If your client caches tool descriptions, reconnect it once - the text of `resolve_injection` changed
along with its answer.

## 0.5.464.40 (2026-09-24) - `resolve_injection` stops giving confident wrong answers

Four builds (`.37` to `.40`) that all repair the same tool. Every one of them replaces an answer
that looked definite with one that is either correct or openly says it does not know - which is
the point: a `false` that means "nobody does this" is far more expensive than a "cannot tell".

**Who is affected.** The MCP server and the `aicb` CLI. **The desktop app is unchanged** - it does
not use this analyzer. Saved snapshots stay valid; there is no database change and no re-analysis.

- **`consumedAsCollection` is answered for every query, not only for a conflicting one.** The field
  says whether anything consumes a service as a set (`IEnumerable<T>` in a constructor,
  `GetServices<T>()`). It used to be computed only where it could also downgrade a registration
  conflict, and read `false` everywhere else - so a service registered once, or registered several
  times through factories, always answered `false` no matter how many consumers took the whole set.
  Measured on a real solution, two services answered `false` while a constructor took each of them
  as `IEnumerable<T>`.
- **A factory registration that *returns* its object is now resolved.** `AddSingleton(sp => Foo.Build())`
  and the block form `AddSingleton(sp => { ...; return Foo.Build(); })` used to leave the registration
  with no type name at all - and in this single-argument form the produced type *is* the service, so
  the whole registration answered to no name. `AddSingleton(sp => new Foo())` always worked; the
  difference was only that one returns instead of constructing. A block body is read only when all of
  its `return` statements agree, and a `return` inside a nested lambda or local function is correctly
  ignored.
- **A registration the scanner can see but cannot parse is now disclosed as such.** Before, such a
  site was invisible, and the answer explained the resulting zero with *"Autofac, Castle Windsor and
  Scrutor are out of scope"* - pointing away from the file that actually held the binding. The note
  now separates *"a Microsoft-DI registration was seen here but its type could not be read"* from
  *"no Microsoft-DI registration was found"*, and names the site.
- **Optional and nullable collection parameters count.** `IEnumerable<IFoo>? foos = null` - a consumer
  that tolerates an empty set - was not counted as consuming the collection, and neither was
  `IEnumerable<IFoo?>`.
- **Consumers declared in test projects no longer count by default.** This one changes an answer you
  may have relied on: collection consumption now obeys the same `includeTests` filter the registration
  list has always obeyed. Before, a test fixture taking `IEnumerable<T>` could mark a genuine
  production conflict between two registrations as deliberate, hiding it. Pass `includeTests=true` to
  get the old, solution-wide reading.

If your client caches tool descriptions, reconnect it once - the text of `resolve_injection` changed
along with its behavior.

## 0.5.464.36 (2026-09-23) - internal wiring, nothing you can see

A plumbing release. No tool changes its answer, the CLI and the desktop app behave
exactly as in 0.5.464.35, and there is no reason to update in a hurry.

- **The MCP server's insights now see the queue of work items**, as the desktop app's
  already did. No MCP tool reads that queue yet, so no answer changes; the connection
  keeps a future tool from reporting "nothing is queued" when the queue was simply not
  connected. The desktop app was never affected.
- **One consequence worth stating:** in a setup where the MCP server is pointed at a
  database, an insights run now performs one additional indexed read against it - the same
  read the desktop app already does - and currently discards the result. Analysis still
  runs entirely on your machine, and the MCP server still writes nothing.

## 0.5.464.35 (2026-09-23) - two answers about C# code that were quietly wrong

Analysis-engine changes, so they reach the MCP server, the CLI and the desktop app alike.

- **`resolve_injection` discloses optional constructor dependencies.** A constructor
  parameter with a default (`IFoo? foo = null`) that nothing in the registration set fills
  used to fall between two answers - the tool listed what was registered, never whether it
  arrived. The answer now carries an `optionalDependencies` axis naming every such consumer,
  with a verdict of `yes`, `no` or `unknown` per construction. The verdict follows **who
  selects the constructor**: the container when the consumer is registered by type, the
  argument list when a factory lambda or a hand-built instance constructs it. Where the
  analyzer cannot see how the consumer is built - construction inside a helper method,
  `ActivatorUtilities`, several constructors to choose between, two types of the same short
  name - it answers `unknown` with a reason rather than a plausible guess. Answers for
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

## 0.5.464.33 (2026-09-21) - manuals linked from the package page

- Full manuals as PDF (General, MCP server, Desktop app) in
  [`docs/manual/`](https://github.com/gregordadera/AICB/tree/main/docs/manual), linked from the
  README and therefore from the nuget.org package page.
- No code change: the MCP server and CLI behave exactly like 0.5.464.32. Published on
  nuget.org only; the desktop app stays at 0.5.464.32.

## 0.5.464.32 (2026-09-21) - one installation per machine

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

## 0.5.464.31 (2026-09-20) - first public release

The first release published outside the author's own machine.

**MCP server and CLI** (`dotnet tool install -g AIContextBuilder` from nuget.org, Windows / Linux / macOS)

- A Roslyn-backed MCP server (`aicb mcp`, stdio) that answers the questions a coding
  agent has before it edits C#: callers and blast radius, implementations and
  overrides, covering tests, injected dependencies, side effects, dead code, dependency
  cycles, live compiler diagnostics - and packs task-sized context for a model.
- Serves both current MCP protocol revisions (`2026-07-28` and `2025-11-25`) from one
  binary.
- Self-init: every tool accepts the absolute `.sln` / `.slnx` / `.slnf` path as its
  session; no separate analyze step.
- A lean default tool pool across nine task facets; the full surface is one profile
  switch away (`--mcp-profile mcp-profile/full`).
- `aicb init` wires a project in one step: `.mcp.json`, the `aicb-csharp-context` agent
  skill, and - for Claude Code, Codex and OpenCode - the optional symbol guard.
- CLI verbs `init`, `analyze`, `export`, `import`, `list`, `mcp` and `call` (one tool,
  once, from a plain shell).

**Desktop app** (Windows, installer or portable ZIP from the release assets)

- Curate by hand what a model sees: pick types and methods, set a detail level per
  node, watch the token estimate, render the context document, and copy, save or send
  it to a model profile you configured (local models included).
- Workspace with solution tabs, snapshots, sessions, insights and the MCP usage view;
  light and dark theme.

**Privacy.** Analysis runs entirely on your machine. The CLI and the MCP server have
no network capability at all; the desktop app talks only to a model endpoint you
configured yourself, for example when you press *Send to API*. No telemetry, no update
check, no crash reporting.

**Known limits.** Analysis needs MSBuild (a .NET SDK or Visual Studio) on the machine.
The Windows downloads are not code-signed yet, so SmartScreen asks once. C# only;
third-party analyzers are not run.
