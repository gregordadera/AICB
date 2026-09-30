# Changelog

Versions follow `Major.Minor.Series.Build`. The build number rises by one for every
change that lands, so gaps between published versions are normal - not every build is
released.

## 0.5.465.11 (2026-09-30) - The .NET tool is now `aicb-roslyn-mcp`, and every tool applies a solution's configuration in the same order

**Who is affected.** Users of the .NET tool: the NuGet package has a new name, and an existing
installation is switched once by hand (below). Anyone who commits a `.aicb.json` next to a solution
or configures solutions in the desktop app: `analyze_solution`, the memory tools,
`solution_config_status`, `check_solution_config_drift` and `aicb analyze` now apply and report one
and the same configuration. The Windows installer and the portable ZIP need nothing beyond the
usual update. No database change; saved snapshots stay valid. If your client caches tool
descriptions, reconnect it once - the description of `recall_codebase` changed.

### The .NET tool is now the NuGet package `aicb-roslyn-mcp`

- **The MCP server and CLI are published on nuget.org as
  [`aicb-roslyn-mcp`](https://www.nuget.org/packages/aicb-roslyn-mcp)** - up to 0.5.465.1 the package
  was called `AIContextBuilder`. The command stays `aicb`, and the MCP Registry entry
  `io.github.gregordadera/aicb-roslyn-mcp` names the new package.
- **Switching an existing installation:** `dotnet tool update` does not cross the rename. Run
  `dotnet tool uninstall -g AIContextBuilder`, then `dotnet tool install -g aicb-roslyn-mcp`. An MCP
  client configuration that starts the `aicb` command needs no change; one that starts the package
  itself with `dnx AIContextBuilder` needs the new name.
- The package `AIContextBuilder` stays on nuget.org with its versions, is marked deprecated with a
  pointer to the new name, and receives no further versions.
- The Windows installer removes an existing .NET tool under either name when you let it. Winget keeps
  the identifier `GregorDadera.AIContextBuilder`.
- The package carries the tag `aicb`, so a nuget.org search for the command name finds it.

### One order for a solution's configuration

- **`analyze_solution`, `solution_config_status`, `check_solution_config_drift` and `aicb analyze`
  resolve a solution's namespace exclusions, layer profile, test profile and analysis scope in one
  order:** an explicit parameter, then the configuration database (a choice made for this solution,
  then the app-wide default), then the `.aicb.json` committed next to the solution, then a built-in
  default.
- **A built-in default no longer overrides a committed `.aicb.json`.** Where the configuration
  database only falls back to the built-in exclusion list, or its app-wide default is the `Empty`
  layer preset or the default test profile, the `.aicb.json` now applies. Before, `analyze_solution`
  then analyzed with the built-in exclusion list while `solution_config_status` named the
  `.aicb.json` as the source. A choice made for one solution still wins over the `.aicb.json`, even
  when it names a built-in - that is how a single solution opts out of the committed profile.
- **`solution_config_status` and `check_solution_config_drift` report the configuration in force**,
  the one an analysis of the solution runs on, each with its `source`: `explicit`, `db`, `sidecar`,
  `none`, or the new `built-in` for the built-in exclusion list. `check_solution_config_drift`
  evaluates that configuration instead of whichever `.aicb.json` it found.
- **`aicb analyze` uses the test profile of a `.aicb.json`** for test-project detection in the
  quality gate and the snapshot's debt, and prints on stderr which layer or test profile it takes
  from the `.aicb.json`, as it already did for a configured one.

### The memory tools analyze like `analyze_solution`

- **`remember_codebase`, `recall_codebase` and `refresh_remembered` apply the same configuration as
  `analyze_solution`** - the configuration database first, then the `.aicb.json`, then a built-in
  default; an explicit `layerProfile` on `remember_codebase` still wins. Before, they read only the
  `.aicb.json`, and from it only the exclusions and the analysis scope: no layer profile unless one
  was passed, no test profile, never the configuration database. On the default `aicb mcp` server a
  remembered session could therefore show other dependencies than `analyze_solution` on the same
  solution, and a recalled session classified test projects by the built-in default whatever the
  repository pinned.

### Fixed

- **Asking `solution_config_status` or `check_solution_config_drift` about a solution no longer
  registers it in the configuration database.** The first such question created an entry for the
  solution whose defaults made the next `analyze_solution` state in `configInit.directive` that the
  user had opted the solution into automatic initialization, which nobody had.
  `apply_solution_config` still creates the entry, since it has a configuration to store.

## 0.5.465.1 (2026-09-29) - New repository name, starts without .NET 8, calls through interfaces are credited to their implementations

**Who is affected.** Everyone: the repository has a new address (every old link keeps working), and
the MCP Registry lists the server under a new name. Users of the .NET tool can now start it on a
machine without .NET 8. Everything else concerns the MCP server and the `aicb` CLI: `find_usages`,
`impact_of_change`, `find_tests_for`, `coverage_gaps` and the tools that repeat their numbers,
`analyze_solution` and the session tools, `export_markdown`, `refresh_session` and
`evaluate_change_set`. No database change; saved snapshots stay valid. If your client caches tool
descriptions, reconnect it once - several descriptions changed.

### New repository address and MCP Registry name

- **The repository moved to `github.com/gregordadera/aicb-roslyn-mcp`** (it was
  `github.com/gregordadera/AICB`). GitHub forwards every old link, clone URL and release download,
  so nothing you set up breaks; update bookmarks and git remotes when convenient. The nuget.org
  package `AIContextBuilder` and the `aicb` command keep their names.
- **The MCP Registry lists the server as `io.github.gregordadera/aicb-roslyn-mcp`.** The previous
  entry `io.github.gregordadera/aicb` keeps its published versions and is marked deprecated with a
  pointer to the new name. Clients that already run the server need no change: they start the
  `aicb` command, not the registry name.
- The desktop app's About page and the `docs` tool link to the new address.

### Listed as an MCP server on nuget.org

- **The NuGet package carries the MCP server package type** next to the .NET tool type, and it
  packs its `server.json` as `.mcp/server.json`. nuget.org lists packages of that type in its MCP
  server filter and builds a client configuration from that file. An existing installation needs
  no change.

### Starts where only a newer .NET is installed

- **The .NET tool now also starts on a machine that has no .NET 8 runtime but a newer one.** It then
  runs on the next newer .NET on the machine and needs that version's SDK, so just the .NET 10 SDK
  works. That is what the configuration nuget.org offers needs: it starts the tool with `dnx` from
  the .NET 10 SDK, and neither `dnx` nor a global install switches to a newer runtime on its own.
  Tested in an environment that holds only the .NET 10 runtime and SDK: the tool starts through
  `dnx` and as a global install, analyzes a `net8.0` and a `net10.0` solution, and answers as an MCP
  server. Where .NET 8 is installed, the tool keeps using it and nothing changes.
- **If the .NET it runs on has no SDK of its own** (for example a .NET 9 runtime next to the .NET 10
  SDK), the tool reports that MSBuild could not be registered. Install the .NET 8 SDK, or set the
  environment variable `DOTNET_ROLL_FORWARD=LatestMajor` so that it uses the newest .NET.
- The installer and the portable ZIP bring their own runtime and are not affected.

### A call through an interface is credited to the implementing method

- **`find_usages` and `impact_of_change` credit a call through an interface or abstract member to
  the method that implements it.** Such a call binds to the interface member, so a qualified method
  query (`Type.Method`) used to miss it, and a method called only through its interface looked
  unused. Those callers are now listed and counted, and `viaContract` says how many were credited,
  through which members and how many types implement each; `viaContractNote` says whether the credit
  is exact (one production implementation) or a union over several. A method in a test project is
  never credited.
- **`find_tests_for` adds the tiers `dispatch` and `dispatch-via`** for a test that calls an
  interface or abstract member the symbol implements, directly or through one method it calls. They
  rank behind the strong tiers and are counted in `dispatchTotal`, because the test may have run a
  sibling implementation or a test double instead.
- **`coverage_gaps` marks with `viaDispatch` a method that only such a test reaches.** Every other
  entry keeps the depth it had.
- **The tools that repeat these numbers carry the qualifier with them.** `review_context` and
  `diff_review` include `viaContract`, `viaContractNote` and `dispatchTotal`; `explain_symbol` says how
  many of the callers call the contract; `verify_claim` with `symbol_removed_unused` answers
  `indeterminate` for a removed method whose only callers called its interface; and
  `find_by_complexity_and_coverage` still counts a method that only a dispatch test reaches as
  untested (`reachedOnlyThroughDispatch`), so the complex-and-untested insight and its debt estimate
  do not shrink without a test being added.

### An answer too large to deliver is refused with its size

- **An answer over 16,000,000 bytes as JSON is refused on `tools/call` and on resource reads**, and the
  refusal names the size and the remedy: `outputPath` for `export_markdown`, a narrower query
  otherwise. Before, `export_markdown` on a large solution failed only after the work, with a bare
  `-32603: An error occurred.`, and a client that closes the connection on a message above 16 MiB lost
  every session the server held.
- **The limit is set with `AICB_MCP_MAX_RESPONSE_BYTES`** (thousands separators are accepted; the
  value is capped at what the JSON serializer can write). A refused tool call is counted as a failure
  in `usage_report`; a refused resource read is not recorded. `aicb call` prints the text directly
  and is not affected.

### `analyze_solution` says when a load was incomplete

- **The session answer carries `incompleteRun` when scanned projects could not bind their core
  framework types** (for example a missing targeting pack): how many, out of how many, the first ten
  names, and a note naming the repair - `refresh_session` with `force=true`, or `refresh_remembered`
  for a session restored with `recall_codebase`. It appears on `analyze_solution`, `refresh_session`,
  `inspect_session`, `list_sessions`, `recall_codebase` and `remember_codebase`, and only for an
  incomplete run, so a healthy answer is unchanged. Before, the first answer said nothing, and only a
  later refresh or `get_diagnostics` showed it. Its absence is no all-clear: `get_diagnostics` names
  the errors of a project that binds its framework but is still not restored.

### Fixed

- **A refresh keeps the namespace exclusions of the first analysis.** With a configuration database -
  the default `aicb mcp` server always has one - `analyze_solution` applied the active
  `Exclude Namespaces` list to the first analysis but not to later refreshes, whether an explicit
  `refresh_session` or the automatic one after an edit. Dependencies, metrics and insights of an
  unchanged solution could therefore change after a refresh. Sessions from `remember_codebase` and
  `refresh_remembered` had the same gap.
- **`evaluate_change_set` analyzes the proposed change with the session's namespace exclusions**, so a
  dependency the exclusions hide is no longer reported as introduced by the change.

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
