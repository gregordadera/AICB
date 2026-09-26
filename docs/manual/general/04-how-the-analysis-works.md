[AICB – General Documentation](README.md) &middot; chapter 4 of 12

# 4 How the analysis works

AICB does not answer from a text index. It opens your solution the way an IDE does, builds a semantic model of the code with the C# compiler platform (Roslyn), and derives every fact it reports — callers, side effects, layers, tests, metrics — from that model. The same analysis feeds all three surfaces: the desktop app, the `analyze` CLI verb and the MCP server.

This chapter describes what happens between opening a solution and the first answer: what the analysis takes in, how a solution is loaded, which semantic layers are computed on top of the model, and where the accuracy limits are.

## 4.1 What goes in

The analysis takes an absolute path to a solution file. Three formats are accepted:

| Format | What it is |
|---|---|
| `.sln` | Classic Visual Studio solution |
| `.slnx` | The XML-based solution format |
| `.slnf` | A solution filter — a `.sln` plus a subset of projects. Useful when a full solution is too large or too slow to analyze |

Two further inputs are read from the solution's own configuration, not from the call:

- **The per-solution configuration** (`.aicb.json`, next to the `.sln`). It can carry layer rules, namespace exclusions, a test profile and the multi-targeting scope (`analyzePreferredTfmOnly`). Headless CLI/MCP analysis uses its layer and exclusion axes as database-free fallbacks and reads the scope directly; the sidecar test profile is configuration/setup material rather than part of the headless analysis resolution chain. In the desktop app, layer, exclusion and test content must first be restored into the database through auto-initialization or `Initialize Now`, while the scope key is read directly. The file is plain JSON and git-tracked, so it travels with the repository.
- **`<ai …>` annotations** in the source. Authors can annotate a type with fields such as `layer`, `role`, `priority` or `responsibility`, and a member with `layer`, `role` or `priority`; `responsibility` is type-only. These values are treated as explicit author statements and outrank every heuristic. Sentinel values `none`, `null` and `empty` (any casing) suppress inference for a field and are never emitted as text; the old key `importance` remains a backward-compatible alias for `priority`.

The analysis is a **read-only** operation with respect to your source. It does not edit files, and it does not load or run your solution's third-party Roslyn analyzers or source generators. Where it reports source-generated members (for example `[ObservableProperty]` or `[RelayCommand]`), it re-derives their names from the attributes in the parsed syntax — it never executes the generator. The MCP server and the CLI have no outbound network capability at all.

> **Security note — opening a solution runs its MSBuild logic.** To resolve references and determine what to compile, AICB performs MSBuild's *design-time build*. That evaluates and runs the project's own MSBuild logic: its `.csproj`, `Directory.Build.props` / `.targets`, SDK and NuGet imports, and any custom targets or inline tasks. A deliberately malicious project could therefore run code at solution-open time. This is not specific to AICB — it is inherent to every MSBuild-based tool, including Visual Studio and `dotnet build`. **Treat pointing AICB at a solution as equivalent to building it: only analyze solutions you trust.**

## 4.2 Opening a solution

### MSBuild registration

Before the first project can be loaded, the MSBuild toolchain must be located and registered. This happens exactly once per process; a registration that another host (for example Visual Studio) has already made is honored rather than repeated.

AICB searches in this order:

1. The default MSBuild discovery of the locator.
2. The newest Visual Studio instance known to the locator (Windows).
3. `vswhere.exe` under `%ProgramFiles(x86)%\Microsoft Visual Studio\Installer` (Windows) — this catches Visual Studio versions the locator does not know yet.
4. The newest .NET SDK under `%ProgramFiles%\dotnet\sdk` that contains an `MSBuild.dll` (Windows).

On Linux and macOS only the default discovery applies; a .NET SDK must be installed. If nothing is found, the message states what was tried and suggests installing the .NET 8 SDK or the MSBuild tools workload. A `global.json` next to the solution can pin which SDK version is used when several are installed.

### The solution registry

Loaded solutions are kept in a reference-counted cache keyed by the absolute solution path (case-insensitive). Two properties matter in practice:

- **Concurrent access to the same solution coalesces into a single load.** If two tabs, two agents or a tool call and a GUI action open the same solution at the same time, only one load runs; the others wait for it. A warm hit on a *different* solution does not wait behind a slow load — the long operations run under a lock per solution path, while the short bookkeeping is separate.
- **A loaded solution stays warm while at least one session uses it.** When the last user releases it, the workspace is disposed and the memory is freed.

Waiting for a load in progress is observable. The desktop app and the CLI wait indefinitely by default. The MCP server bounds the wait to 45 seconds and then answers with a "load in progress" message that names the solution and the running operation, instead of blocking past the client's own timeout. The bound can be changed with the environment variable `AICB_MCP_LOAD_WAIT_MS` (milliseconds). If a load is stuck, the message recommends waiting for it to finish or analyzing a smaller solution or a filter (`.slnf`).

### The design-time build cache

The expensive part of opening a solution is the MSBuild design-time build. Its result is cached per solution, so a later process can skip MSBuild when the project shape has not changed.

| Setting | Value |
|---|---|
| Default location | `%LOCALAPPDATA%\AIContextBuilder\design-time-build-cache` |
| Relocate | Set `AICB_DESIGN_TIME_BUILD_CACHE` to a directory path |
| Disable | Set `AICB_DESIGN_TIME_BUILD_CACHE` to `0`, `off` or `false` |
| What invalidates it | Changes to project-shaping files: project files; any `*.props` / `*.targets` (including `Directory.Build.props`, `Directory.Build.targets` and `Directory.Packages.props`); `*.sln`, `*.slnx` and `*.slnf`; `global.json`; `nuget.config`; `packages.lock.json`; `.editorconfig` / `.globalconfig`; `*.csproj.user`; `obj/project.assets.json`; and the installed SDK versions. Source edits do **not** invalidate it — a rebuild is only about references and compilation structure, and the source is re-read anyway |
| Cleanup | A cache file that is neither written nor hit for 30 days is deleted the next time a store finds more than 32 cache files. A hit touches the file, so a solution you open regularly never ages out |

Each cache file is specific to one solution (a hash of the canonical path); two solutions never share one. If the cache is unusable for any reason, AICB silently falls back to running MSBuild — the cache is an optimization, never a requirement.

## 4.3 The analysis run

One analysis run has a single entry point and takes the following inputs:

| Input | Meaning | Default |
|---|---|---|
| Solution handle | The loaded workspace. Required | — |
| Layer profile | The namespace-to-layer mapping to use. When unset, only the built-in role heuristic applies | none |
| Excluded namespaces | The namespaces to keep out of the type-reference facts (parameters, return types, fields, properties, dependencies). Supplied from the solution configuration when one exists | none |
| `AnalyzePreferredTfmOnly` | Analyze only the preferred target-framework instance of a multi-targeted project (see "Multi-targeting") | `false` |

The run walks every C# project and, per document, builds a syntax tree and a semantic model. A document whose syntax tree or semantic model cannot be obtained is skipped. The analyzable type nodes are `class`, `struct`, `interface`, `record` and `enum`.

Beyond declared methods, the analysis treats accessors and constructors as additional **units** with a body:

- **Accessors** — every property, indexer and event accessor with a body (`get { … }`, `set => …`, `init`, `add`/`remove`) plus the getter of an expression-bodied property. An auto-property accessor (`get;`) has no body and produces no unit.
- **Constructors** — each constructor that executes something, including member initializers; a constructor declared elsewhere contributes its initializers to the constructor that runs them.

Top-level statements and Razor components are covered by dedicated analyzers that record their call and type references in the fan-in indexes. They are not units and therefore do not contribute to unit-based counts such as `methodsScanned`, coverage or dead-code totals.

While the run proceeds, progress is reported per document in roughly 1 % steps — at most about 100 updates per run, so the reporting itself stays cheap. A run can be cancelled; the cancellation is passed through the project loop, the document analysis and the Roslyn calls.

After the document phase, a single-threaded post-processing phase consolidates the run's indexes:

1. Resolve XAML `{Binding}` facts against the built types and fold them into the member fan-in.
2. Resolve Razor member references against the component types.
3. Resolve parameters a Razor component hands to child components.
4. Resolve XAML `{x:Type}` references into the type fan-in.
5. Resolve top-level-statement type references into the type fan-in.
6. Apply the state-driven indexes: caller lists, type fan-in, implemented-by lists and resolved semantics.
7. Propagate side effects transitively along the call graph (see "Side-effect classification").
8. Inherit each type's layer onto its methods.

Two results are computed only for a live analysis and are not re-derived from a stored snapshot: the **unresolved XAML bindings** and the **completeness record** described next.

## 4.4 Incomplete projects

A project is called **incomplete** (unresolved) when its compilation cannot bind its core references — concretely, when `System.Object` is an error type. Typical causes are an unrestored project (no `restore` has run) or a targeting pack the machine does not have.

An incomplete project is one of the most important states to understand, because it decides whether you can trust an answer. Such a project still yields syntax, so the analysis walks it and still produces facts — but the **semantic edges are missing**: an unresolved call site records no caller. Every fan-in answer that follows is short by an unknown number of ordinary references, and nothing about it looks wrong.

The run records its own completeness and reports one of three states:

| State | Condition | Meaning |
|---|---|---|
| All resolved | At least one project scanned, none unresolved | Everything bound |
| Incomplete | At least one project scanned, at least one unresolved | The alarm state |
| Indeterminate | No project scanned | Unknown — no statement is possible |

The unresolved projects are named, not merely counted, so that "restore `MyApp.Infrastructure`" is an actionable next step.

> **Note:** "All resolved" does not mean "the project is restored". The check looks at `System.Object`, which a project gets from the base framework rather than from its own restore. A project without a `project.assets.json` typically loads, binds `System.Object` and counts as resolved, while every fact typed by its missing references is gone. What the flag really separates is a *wholly* unbuilt working tree from everything else.

The completeness record travels with the session and is stored with a remembered codebase; a missing value means "unknown", never "fine".

When a run is incomplete, tool answers say so. Answers about fan-in (for example `find_usages`, `impact_of_change`, `find_dead_code`, `instantiation_sites`) carry a leading note that their numbers are short by an unknown number of ordinary references. Answers about side effects are sharper still, because effects are derived by propagating along call edges: an unresolved call makes a method read as pure. The note in that case tells you to treat the result as a floor and never as a passed purity or architecture check. The same applies to external-call searches and to code-trait queries such as reflection usage.

Practical consequence: **restore and build the solution before you rely on effect, leak or external-call statements.** Fan-in statements survive an unbuilt tree partly; effect statements do not.

## 4.5 Multi-targeting

A project with several target frameworks (`<TargetFrameworks>net8.0;netstandard2.0</TargetFrameworks>`) is loaded by Roslyn **once per target framework**. The same source file is therefore analyzed as many times as there are frameworks. Whether that costs much is solution-specific: on some repositories the duplicates are the majority of all documents, on others they are negligible.

By default AICB analyzes all instances. You can opt into analyzing only the preferred instance:

```json
{
  "analyzePreferredTfmOnly": true
}
```

in the solution's `.aicb.json`. The preferred instance is the one with the newest target framework; a tie keeps the first in load order. The setting lives only in the sidecar — there is no equivalent database setting.

What the switch does and does not change:

- **The type and method inventory is unchanged.** The query surfaces deduplicate to one logical project instance per name anyway, keeping the newest target framework's instance.
- **Lost:** a fan-in edge whose only source is a non-preferred instance. This affects `find_usages`, `impact_of_change`, `call_graph`, the deprecated-API insight, PageRank and the trimming priorities.
- **Gained:** more complete transitive side-effect facts, because the narrower run avoids a last-write-wins effect in the shared method index.
- `find_dead_code` stays safe either way: it requires an analyzed caller list and abstains where the edge went missing, instead of calling a live method dead.
- The reported project count counts project *instances*, so a multi-targeted project contributes one entry per target framework.

## 4.6 How long it takes

There is no universal formula of the form "solution size → analysis duration"; the time depends on the number of projects and documents, on restore state and on disk speed. The published benchmark in the [architecture, limits and evidence guide](../../ARCHITECTURE.md#how-does-aicb-scale-on-large-solutions) reports measured cold analysis and warm-query times on three public solutions (≈ 25k, ≈ 55k and ≈ 1.8M lines of C#): about 10 s, 30 s and 97 s cold, warm answers in well under 2 s. Two practical statements hold:

- The analysis itself is usually a matter of minutes even for large solutions.
- Producing the **full Markdown export** of a very large solution is the expensive step, not the analysis: it builds the document single-threaded and can take considerably longer than the analysis it renders.

For everyday work on large solutions, prefer the bounded views — `architecture_overview` for orientation, `get_context`, `explain_symbol` or `prepare_task` for one symbol or one task — and reserve the whole-solution export for when you really need it.

After an edit, a refresh does not necessarily re-walk everything: where the previous run's facts can be reused for documents the edit could not have reached, they are. The refresh answer reports which path it took (`mode: incremental` or a full reload).

## 4.7 Side-effect classification

The analysis classifies every method by what it touches in the outside world. The vocabulary is closed and has exactly eight tokens:

| Token | What it asserts |
|---|---|
| `io` | Filesystem and stream access |
| `network` | HTTP, socket, mail and cloud-storage calls |
| `database` | Database drivers and ORMs (for example ADO.NET/`System.Data`, EF Core, Dapper, `Microsoft.Data.Sqlite`, Npgsql, MongoDB, Cosmos) |
| `serialization` | (De)serializer calls (for example `System.Text.Json`, Newtonsoft.Json, `XmlSerializer`, DataContract, MessagePack, protobuf, YamlDotNet) |
| `logging` | Logger calls (for example `Microsoft.Extensions.Logging`, Serilog, NLog, log4net) |
| `cache` | Calls into an **external** cache API (for example `Microsoft.Extensions.Caching`, StackExchange.Redis, EasyCaching, FusionCache) |
| `messaging` | Message-bus and queue clients (for example MassTransit, RabbitMQ, Azure Service Bus/Event Grid/Queues/Notification Hubs, Kafka, NATS, MediatR, Amazon SQS/SNS) |
| `unknown` | An external call no classification rule matched — reported so the gap is visible instead of reading as pure |

**The criterion is contact, not topic.** This distinction is the one readers most often assume the other way:

- A `System.IO` type is judged on whether it touches a disk or a handle. Types whose members only transform values in memory carry no effect: `Path` (path strings), `FileSystemName` (glob matching), `MemoryStream`, `StringReader`/`StringWriter`. Types that reach a disk or a handle do: `File`, `Directory`, `FileStream`, `FileInfo`, `StreamReader`/`StreamWriter`.
- A `System.Net` type is judged the same way. Addresses (`IPAddress`/`IPEndPoint`/`DnsEndPoint`), cookie and header containers, credential holders, the HTTP and mail *message* surfaces and all of `System.Net.Mime` carry no effect; `Dns`, `Sockets`, `WebClient`, `SmtpClient`, `HttpClient`, `HttpContent` and third-party clients (Flurl.Http, Azure Blob Storage, Amazon S3/SES) do.
- A cache a type holds **in memory** is not an outside-world effect and is never classified as `cache`. Find such types through their cache interface (`find_implementations`) or their name (`find_symbol`).

**Effects propagate.** A method that calls a method with `io` carries `io`. Propagation follows the call graph upward, including a call through an interface when exactly one implementation exists; a call with several possible implementations stays unresolved. Because of this, a single misclassified external call would fan out over the entire caller tree — which is why the classifier is conservative about the types listed above.

> **Note:** effect, leak and external-call results require a restored/built solution. In an unbuilt tree they can be empty or incomplete without looking wrong.

The tool `find_by_side_effects` exposes this layer. It accepts `effect=<token>` (validated against the eight tokens — anything else is rejected, not answered with zero), `purity=pure|impure|any`, `scope` and `includeTests` (default `false`). With no effect and no purity filter, only impure methods are listed. A known token with zero hits returns a note quoting what the token means, and a note also reports how many methods a filter removed, so a short list is never silently short.

## 4.8 Layer profiles and architecture analysis

AICB checks the Clean/Onion direction rule: dependencies should point inward. The check has its own vocabulary of five layer names, ordered from the inside out:

```
Contracts (0)  <  Domain (1)  <  Application (2)  <  Infrastructure (3)  <  Presentation (4)
```

`Contracts` is the innermost shared kernel (referenceable by everything, referencing nothing outward); `Presentation` is the outermost layer. **A violation exists when the source layer's rank is lower than the target layer's rank** — an inner layer depends on an outer one.

A type's layer is resolved in this order:

1. A real `<ai layer="…">` annotation.
2. The **namespace profile** configured for the solution — the `layerRules` in `.aicb.json` (or the profile stored in the configuration database), passed to the analysis.
3. The **project/assembly name**, by a generic Clean-Architecture convention. The assembly is the reliable layer signal; a type labeled this way counts as authoritative.
4. The **role heuristic** — the weakest fallback.

A profile may use its own layer names. Those names are ranked through the same convention, matched as whole dot-separated segments:

| Name in the profile | Ranks as |
|---|---|
| `Core`, `Domain`, `Entities` | Domain |
| `Persistence`, `Adapters`, `DataAccess` | Infrastructure |
| `Application`, `UseCases` | Application |
| `Contracts`, `Abstractions` | Contracts |
| `Composition`, `Probes`, `Web`, `Api`, `Ui`, `Cli`, `Console`, `Mcp`, `Host`, `Samples`, `Benchmarks`, … | Presentation |
| anything else, for example `CodeAnalysis` or `DomainModel` | no rank |

A layer name that is an outer-ring host word **dominates** an inner-layer word in the same name: a project named `MyApp.Core.Benchmarks` resolves to Presentation, not Domain. That is the safe direction — an outermost host's outbound edges are always legal.

The rank decides the direction only; the reported violation line prints the profile's own layer label, so you can see which label the name bought.

**Coverage is disclosed.** The layer check classifies every production type into one of three groups, and the insight reports them:

| Group | Meaning |
|---|---|
| Checked | The type's layer has a rank; its dependency edges were judged |
| Unranked | The type has a layer whose name has no position in the Clean/Onion order — reported separately, with the layer names and type counts |
| Unresolved | No layer could be assigned at all |

The skipped types are named (the first few inline), so a clean result over a mostly skipped solution cannot be read as "mostly clean". The insight also suggests how to fix it: rename the unranked layer to one of the five names or to a name built from their vocabulary, or add namespace-to-layer rules for the unassigned types.

Two **deliberate false negatives** keep the check quiet rather than noisy:

- **Generics:** dependency strings of generic types carry their type arguments (`IRepository<Order>`), while the index key is the bare identifier (`IRepository`) — such edges are not matched.
- **Intra-assembly:** an edge between two types of the *same* project is not a violation, provided neither side has an authoritative layer. Rank differences produced by the role heuristic inside one assembly are noise.

**Production focus:** types from test projects are skipped — a test referencing its Infrastructure target class is not a production layer violation.

> **Note:** a layer whose name sounds like an outer ring — `Api`, `Host`, `Adapters`, `Web` — is ranked as Presentation. That is correct when the name means the outer ring, and a false positive when `Api` is a library's public surface. The insight names the layer and the profile so you can see which rank the name bought.

Where you meet this layer:

- The **`quality-layer-violations` insight** in the insights list. Its severity follows the profile's layering policy: `Advisory` (the default) reports `Warning`, `Strict` reports `Critical`. The insight can be disabled in `Settings → Quality Profiles`.
- The **policy gate** (`evaluate_change_set`), which asks before an edit whether it would introduce a layer violation, with delta semantics against the current session.

To configure the layer axis, use the guided setup (`init_solution_config` then `apply_solution_config`), which writes the rules into the configuration database and into the git-tracked `.aicb.json` next to the `.sln`. A rule has a `pattern`, a `matchType` (`Contains`, `StartsWith`, `EndsWith`, `Exact`) and a `layer`. The sidecar's `layeringPolicy` key accepts `Advisory` or `Strict`. You can also edit the file by hand.

The same `.aicb.json` carries the **namespace exclusion list** (`exclusions`, same match types). Namespaces on that list are left out when the analysis builds type references — parameters, return types, fields, properties and dependency lists — so framework noise does not count toward coupling or dependency-based results.

## 4.9 Dead-code detection

`find_dead_code` answers "what is never used?" on two axes, selected with the `kinds` parameter: `method` (the default), `type` or `all`. An unrecognized token (for example the plural `types`) returns the superset of both axes rather than silently swallowing one.

**The method axis** reports a method only when both conditions hold:

1. It is **private**.
2. It has an **analyzed caller list**.

The two exclusions are counted separately and reported: `methodsIneligibleNotPrivate` (the deliberate policy — public and internal methods have framework escapes such as reflection, DI and event wiring that static analysis cannot see) and `methodsIneligibleUnanalyzedCallers` (private methods whose caller list was not analyzed — the blind spot). Merged into one number, you could not tell which arm emptied your scope. Test projects are excluded by default (`includeTests` opts in), and `testMethodsFiltered` reports what the filter removed.

**The type axis** reports types with no incoming reference in the reliable reverse type fan-in, minus the types that are structurally invisible to it. Four exemption families are applied and counted apart, so a zero over an eligible population is distinguishable from a scope that could not produce a candidate:

| Family | Examples |
|---|---|
| Structural | Interfaces; static classes, including `*Extensions` containers |
| Test scaffolding | Test and fixture types, test paths, runner-activated types |
| Framework/reflection-activated | Types a framework instantiates by DI, reflection or convention — entry points, MVC controllers, middleware, EF migrations, Blazor pages, types with a non-`System` base or interface, routing/tool attributes |
| Markup-referenced | Types referenced from XAML markup |

The counts are `typesIneligibleStructural`, `typesIneligibleTestScaffolding`, `typesIneligibleFrameworkActivated`, `typesIneligibleMarkupReferenced`; `testTypesFiltered` reports what the test filter removed. When the method axis runs alone and finds nothing, the answer also reports `typesUnexamined` — how many types the type axis would have judged — so a bare "0 dead" is not read as an all-clear.

> **Note:** caller lists are statically resolved. Reflection, DI containers, serializers and external assemblies stay invisible. Absence of callers is not proof of dead code. Confirm a candidate before deleting it — the answer's leading note names the checks to run.

Both axes are capped at 200 entries; `scope` narrows the query to a namespace prefix.

## 4.10 Circular namespace dependencies

`detect_circular_dependencies` finds namespaces that depend on each other in a cycle. The granularity is the **namespace**, not the type: type cycles are common in C# and mostly harmless, project cycles are forbidden by the compiler, and the namespace level is the meaningful, low-noise module cut.

- A namespace edge `N → M` exists as soon as any type in `N` references a type in `M` (with `M ≠ N`).
- A reported cycle is a strongly connected component of at least two namespaces.
- Resolution is exact, by fully qualified name — same-named types in different namespaces are never conflated. References inside generic type arguments are decomposed (`C.Box<B.Bar>` counts as a dependency on both `C` and `B`). A reference that does not resolve to a solution type is external (BCL/NuGet) and is skipped.
- Each cycle names the **assemblies** its namespaces are declared in. A cycle *inside* one assembly is pure namespace organization; a cycle that *spans* assemblies means a namespace is reused across DLL boundaries — the more interesting situation, since project-reference cycles cannot compile. Cycles that span assemblies are listed first, then the larger tangles.
- Each cycle lists witness edges — one concrete type-to-type reference per directed namespace pair — and reports how many distinct type references cross that boundary. Read the witnesses as examples: where the count is higher than one, fixing the shown reference leaves the namespace edge standing.

`scope` narrows the report to cycles touching a namespace prefix; the graph itself stays the whole solution, so the scanned-namespace count is unchanged. Test projects are excluded by default (`includeTests` opts in); multi-targeting collapses by itself, because namespaces and edges are sets. Up to 100 cycles are returned, with at most 50 witness edges per cycle.

## 4.11 Test detection and coverage gaps

**What counts as a test project.** A project is classified as a test project when either signal holds:

- An explicit `.csproj` marker: an `<IsTestProject>true</IsTestProject>` property or a `Microsoft.NET.Test.Sdk` package reference. This is name-independent and always wins.
- A project-name rule from the active test profile. The default profile matches any project name containing `Test`, `Tests`, `Spec` or `Specs` (case-insensitive).

A multi-targeted instance is matched on its logical name too, so a suffix such as `(net8.0)` does not break a rule.

**What counts as a test case.** Only a method that itself carries a test attribute. A fixture builder or helper in a test project is not a test case. The attribute names come from the active test profile:

| Profile | Test attributes |
|---|---|
| Default (framework-agnostic) | `Fact`, `Theory`, `Test`, `TestMethod`, `TestCase` |
| xUnit | `Fact`, `Theory` |
| NUnit | `Test`, `TestCase`, `TestCaseSource`, `TestFixture` |
| MSTest | `TestMethod`, `DataTestMethod`, `TestClass` |

Attribute names are matched as substrings, case-insensitive, so a custom `[WindowsFact]` matches via `Fact`.

**Match tiers.** `find_tests_for` reports each covering test with the strength of the evidence:

| Tier | Value | Meaning | Rank |
|---|---|---|---|
| Direct | `invokes` | The test calls the target itself — one hop, the strongest evidence | 0 |
| Via helper | `invokes-via` | The test reaches the target through one method it calls (its own helper or a production entry point) — two hops, still strong | 1 |
| Name | `name` | The test's or its class's name mentions the target — a guess, not evidence of a call | 2 |

"Strong" means `invokes` or `invokes-via`. `invokesTotal` counts both strong tiers. The result is ordered direct first, then helper hop, then name guess, and within a tier alphabetically — so the 50-entry cap can only ever drop the least load-bearing end.

Three query targets can all produce the same empty list, and the answer distinguishes them:

- **Not declared** — no declared type and no declared member carries the name. An empty answer then says nothing about coverage.
- **Type or method** — what the strong tier can index.
- **Member outside the index** — a property, field, event or enum member: resolvable for `find_usages` and `impact_of_change`, but without a call edge, so only the name tier can fire.

**Coverage gaps.** `coverage_gaps` lists production code without strong test coverage, per scope, capped at 200 entries. It is a **one-hop list, not a coverage measurement**: a method that a test reaches through another method is still listed. Each entry therefore carries `testReachDepth` — the number of hops to the nearest directly tested method. An entry *without* a depth is one no test reaches at all; those are the real gaps to work first.

The population is disclosed, so a gap count can be read against its denominator: `judgedUnits` (the non-test, non-abstract methods the list is drawn from) out of `symbolsScanned`, plus `testProjectsExcluded` and `testFixtureTypesExcluded`. Abstract declarations (interface methods without a default implementation, abstract class methods) are excluded — a test covers the implementation, not the declaration. A type that declares a test-attributed method is treated as a test fixture, so its attribute-less `SetUp`, lifecycle and helper members count as test code, not as uncovered production code; this also works for a fixture in a project whose name matches no test rule.

> **Note:** the absence of a detected test is not proof that no test exists. The list is built from statically resolved calls.

## 4.12 Dependency injection resolution

`resolve_injection` resolves Microsoft.Extensions.DependencyInjection registrations. It is a syntactic scanner with a best-effort semantic model, so it yields names even when the DI assembly itself does not resolve; a missing semantic model never aborts the scan.

A call is recognized as a registration when its method name matches:

```
^(Try)?Add\w*(Singleton|Scoped|Transient)$
```

The wildcard in the middle admits wrapper forms such as `AddKeyedSingleton` and project-local helpers such as `AddCachedSingleton`, while names like `AddTransientHttpErrorPolicy` stay out. Without this, a helper's call sites would not count as registrations at all.

For each registration the answer reports the concrete implementation, the lifetime (`Singleton`, `Scoped`, `Transient`), the location (`file:line`), the project and the declaring method. A registration whose service type cannot be read statically is disclosed with one of three placeholders:

| Placeholder | Meaning |
|---|---|
| `(dynamic)` | One side of the registration is computed at runtime — real, just not readable here |
| `(unknown)` | A call shape the scanner did not parse |
| `(factory)` | A factory lambda whose body does not name the type it produces |

At most five unreadable sites are named; beyond that the list is abbreviated. One data-driven shape **is** expanded: a `foreach` over a static table of `new(typeof(Service), typeof(Impl))` rows becomes one registration per row, even when the table lives in another project. Rows produced at runtime — reflection or assembly scans, method results, a deconstructed loop variable — are not expanded and are disclosed instead.

Further resolution details:

- `site` narrows to registrations whose file path contains a given substring.
- `includeTests` (default `false`) excludes registrations declared in test projects; `testRegistrationsFiltered` reports what was hidden.
- `ambiguous` is judged within one registration site: true only when that site registers more than one distinct, statically resolvable implementation and the service is not consumed as a collection. Across sites it is deliberately not called ambiguous — a solution with several hosts registers the same service once per host, and those containers never meet. `multiRegistration` and `registrationSites` tell you whether more than one registration matched at all.
- `consumedAsCollection` is true when the service is consumed as a collection — a `GetServices<T>()` call or an `IEnumerable<T>`-family (or `T[]`) constructor parameter, optional and nullable ones included. Multiple registrations are then a deliberate multi-binding, not a last-wins conflict. A consumer declared in a test project counts only under `includeTests`.
- An empty answer is distinguished in three ways: a name that resolves to nothing is reported as not found with a nearest-name suggestion; a real name with no registration gets a note stating what the scanner reads (Microsoft-DI-shaped `Add*`/`TryAdd*` calls only) and what it cannot see (Autofac, Castle Windsor and other non-Microsoft containers, keyed, open-generic and Scrutor registrations). If the solution references a foreign container assembly, the note names the projects and assemblies instead of the generic list.

**Instantiation sites.** `instantiation_sites` answers the narrower question "who creates an instance of this type?" with two edge kinds kept apart:

- **created** — a method, constructor or accessor that runs `new X(...)`. This includes target-typed `new`, `record with` expressions and collection/`stackalloc` allocations. A field or property initializer is attributed to the constructor that runs it (the implicit one when none is declared); with several non-chaining constructors, one initializer line yields one site per constructor.
- **injected** — a type that receives `X` as a constructor-injected dependency.

The answer reports `createdByCount` and `injectedIntoCount`, and it includes test-project sites, because a test that constructs a type breaks when the constructor changes. A concrete type registered in a DI container correctly reports zero injections: its consumers take the interface, so the edges sit on that interface name — the answer names the interfaces in that case. A type name that matches no declaration is reported differently, with a nearest-name suggestion rather than the zero-explanation note.

## 4.13 PageRank and the relevance score

AICB contains a personalized PageRank calculation over the method graph. Its edges come from the caller lists, inverted (caller → callee), and its parameters are fixed:

| Parameter | Value |
|---|---|
| Iterations | 30, with no convergence check and no early exit, so the result is deterministic; a non-converged result is returned as is |
| Damping | 0.85 |
| Hint boost | Methods recognized in the user prompt receive 10× more initial mass |

Duplicate method keys (overloads, multi-targeted instances) collapse to one node, so the total mass stays approximately 1.

> **Note:** PageRank is implemented but not active. No released feature turns it on: the scoring pipeline passes a PageRank value of 0, so the factor below is 1.0 in every real run, and there is no setting to enable it. PageRank is also not a ranking factor of the search tools.

What actually ranks methods today is the relevance score used when a token budget is applied to a rendered context. The score is multiplicative; the lower it is, the sooner the method is trimmed away. Its factors are:

| Factor | Value |
|---|---|
| Log-damped fan-in | `1 + log(1 + caller count)` |
| PageRank boost | `1 + 5 × pageRank` (currently always 1.0 — see above) |
| Visibility | `public` 2.0 · `internal` 1.0 · `protected` 0.7 · `protected internal` 0.85 · `private protected` 0.5 · `private` 0.3 |
| Priority (`priority` annotation) | `high`/`important` 3.0 · `low`/`nice-to-have` 0.2 · otherwise 1.0 |
| Entry point | 5.0 |
| Role | Controller 2.0 · Helper/Utility 0.6 · otherwise 1.0 |
| Path penalty | Test 0.1 · Generated 0.05 · Designer 0.05 · Migration 0.3 |
| User hint | Methods recognized in the user prompt get a multiplier of 10 |
| Dead private | `private` and no callers → 0.1 |
| Single-caller private | `private` and exactly one caller → 0.4 |

All multipliers except the two compound visibility values (`protected internal`, `private protected`) can be overridden by the active compression-rules profile; without a profile the values above apply. Scores are rounded to nine decimals, and a multi-stage tiebreaker (score, lines of code, method name, method key) keeps the ordering deterministic.

The token-budget machinery is active only when it is switched on — the built-in `Default` pipeline profile has token trimming off, and the `Aggressive Trimming` profile turns it on with a 20,000-token budget. Context exports that are not budgeted are not affected by the score.

## 4.14 Metrics

Metrics are computed per method, per type, per namespace and per solution.

**Per method**

| Metric | Meaning |
|---|---|
| Cyclomatic complexity | McCabe complexity — the number of independent paths. `0` means not computed |
| Lines of code | The lines of the declaration that carry a token (signature plus body; blank and comment-only lines excluded). Empty means not computed |
| Parameter count | Number of parameters |

**Per type**

| Metric | Meaning |
|---|---|
| Efferent coupling (Ce) | Number of distinct referenced types. Framework types are included unless removed by the namespace exclusion list |
| Afferent coupling (Ca) | Number of types that use this type |
| Member count | Methods + properties + fields, without constructors |
| Method count | Number of methods |

> **Note:** the stored afferent-coupling field is empty on live analyses. The live surfaces that show Ca — the quality-gate metric `ca-max`, the `QUALITY_HOTSPOTS` section and the `ca=""` tag attribute — compute the reverse fan-in from the dependency lists instead. The field remains valid for hand-built models and older snapshots.

**Per namespace** — Martin's package metrics, shown in the `QUALITY_HOTSPOTS` section of a context document:

| Metric | Meaning |
|---|---|
| Namespace / layer | The namespace and the architectural layer its types resolve to; `(mixed)` when its types disagree, `(global)` for types without a namespace |
| Type count | Logical types in the namespace (partial fragments and multi-targeted instances unified) |
| Abstract type count | Interfaces and abstract classes — extension points a consumer can depend on without depending on an implementation |
| Efferent coupling (Ce) | Distinct type names *outside* the namespace that types inside depend upon |
| Afferent coupling (Ca) | Distinct types *outside* that depend on something inside |
| Instability (i) | `Ce / (Ca + Ce)`, from 0 (only depended upon) to 1 (only depends on others); 0 when the namespace has no coupling |
| Abstractness (a) | `abstract types / all types`, from 0 to 1 |
| Distance from the main sequence (d) | `|a + i − 1|` — 0 means the namespace is as abstract as it is stable. High `d` means either unstable *and* concrete (hard to change, nothing to extend) or stable *and* abstract (an abstraction nobody uses) |
| Has coupling | Whether the namespace has any coupling at all. Namespaces without coupling are filtered out of the ranking, because they would otherwise crowd the top of the list |

The ranking orders by distance descending; ties are broken by total coupling and then by name. Ca is a lower bound for a library whose real callers live outside the analyzed solution, and Ce counts the types the analysis recorded in signatures and explicit generic arguments — a low instability means "no *recorded* outward coupling", not proof of a stable namespace. In a partial (budget-trimmed) export the main-sequence block is omitted entirely, because pruning would bias the numbers toward a false all-clear.

**Per solution** — the roll-up behind `solution_metrics` and the quality gate, computed over production code only (test projects excluded; the tool reports the excluded test-side counts as well):

| Metric | Meaning |
|---|---|
| Type count | Logical types — partial fragments merged, multi-targeted instances deduplicated |
| Method count | Declared methods (accessors, constructors and operators are not counted here) |
| Complexity max | Highest cyclomatic complexity over all methods (`0` = none computed) |
| Complexity avg | Average complexity over the methods whose complexity was computed |
| Methods over complexity threshold | Number of methods with complexity **strictly greater** than the configured threshold |
| Ce max | Highest efferent coupling over all logical types |
| Ca max | Highest afferent coupling, computed as reverse fan-in from the dependencies |

**Two complexity axes.** `symbol_metrics` reports both cyclomatic complexity and SonarSource-style **cognitive complexity** — how hard a method is to understand, with a nesting penalty, `else`/`catch` counted and boolean-operator runs collapsed. You choose the ranking axis with `rankByCognitive` (default: cyclomatic). The two axes can disagree about *which* methods appear, not merely about their order: a flat method with many independent paths can top the cyclomatic list while a genuinely tangled method is absent from it entirely, and the other way round. When the axes disagree about the set of methods, the answer carries a note naming the axis that produced the ranking and the strongest methods the other axis would have shown. A `minComplexity` floor is **inclusive**: a method sitting exactly on the floor is listed.

> **Note:** the strict and inclusive boundaries are both correct and intentionally different. `MethodsOverComplexityThreshold` in the solution roll-up counts strictly greater, while `symbol_metrics(minComplexity)` and the complex-untested insight list a method sitting exactly at the threshold. At the same number the inclusive lists are larger by exactly the boundary methods.

---

[&larr; 3 Core concepts](03-core-concepts.md) &middot; [Contents](README.md) &middot; [5 The context document (AI-Builder-MD) &rarr;](05-the-context-document-ai-builder-md.md)
