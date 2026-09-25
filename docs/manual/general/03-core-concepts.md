[AICB – General Documentation](README.md) &middot; chapter 3 of 12

# 3 Core concepts

This chapter defines the vocabulary the rest of the manual uses. The same words appear in the graphical interface, on the command line and in the answers of the MCP server, so a term you read here is a term you can search for on screen or in a tool answer. Read this chapter first — every other chapter builds on it.

## 3.1 Solution

A **solution** is a Visual Studio solution: the `.sln` file plus all the projects it contains. It is the unit the tool analyzes — without a solution, nothing happens.

You meet the solution in several places:

- In the GUI, in the `Workspace` area (the sidebar entry of the same name). Its left list is headed `Solutions`; each entry is one solution the application knows about.
- In the `Solution Tree` of the Context Builder, which shows the loaded solution's projects and files.
- On the command line: `aicb analyze --solution <path-to-.sln>`, and `aicb call <tool> --sln <path-to-.sln>` for a single tool call.
- In the MCP server: a `sessionId` argument accepts the absolute path of a solution file (`.sln`, `.slnx` or `.slnf`) directly and analyzes it on first use.

Note: the application also stores an entry per solution that carries the profiles assigned to it, its sessions and its snapshots. "The solution" in this manual always means the analyzed project structure, not that stored entry.

## 3.2 Project

A **project** is a `.csproj` inside the solution. An analysis walks every project of the solution.

A project that targets several frameworks (multi-targeting) appears **once per target framework** in the analysis. Several tools present a deduplicated view instead and keep only the preferred (normally newest) target-framework instance. This view is not lossless: a symbol or fan-in edge that exists only in an older target-framework instance is not reported by those deduplicated tools.

You meet projects as the second level of the `Solution Tree`, in the `PROJECT` section of a context document, and in the `project` field of tool answers.

## 3.3 Namespace, type and member

**Namespace** — the C# namespace a type is declared in. It is part of a type's full name, and it is the axis by which you filter and scope: `Exclude Namespaces` in the settings, a namespace prefix as a tool `scope`, or a namespace pattern in a layer profile.

**Type** — a class, a struct, an interface, a record or an enum.

**Member** — a constituent of a type: a method, a property, a field, an event or a constructor.

The `Solution Tree` shows the physical side of this: the solution, its projects, their folders and their files. Under each C# file the analysis adds the file's types, and under each type its methods, so you can select at any level. The checkbox `Public methods only` hides non-public methods in the tree.

## 3.4 Unit

A **unit** is everything that has an executable body and can therefore be analyzed. That is more than a declared method:

- **Methods** — ordinary method declarations.
- **Accessor units** — every property, indexer or event accessor with a body (`get { … }`, `set => …`, `init`, `add`, `remove`), plus the getter of an expression-bodied property such as `public int Total => _a + _b;`. An auto-property accessor (`get;` / `set;`) has no body and produces no unit.
- **Constructor units** — one per constructor that executes something: a declared constructor is analyzed as a whole declaration, so calls inside `: base(...)` / `: this(...)` arguments are captured, together with the member initializers it runs. For a constructor that is declared elsewhere — the implicit parameterless constructor, a C# 12 primary constructor, a constructor in another partial file, or the implicit static constructor — only the initializers are analyzed. A struct's default constructor runs no initializer, and a record's copy constructor copies instead.
- **Top-level statements** and **Razor components** — analyzed by their own passes. Their calls and type references are recorded with a `... (top-level)` or `... (razor)` source label, so they appear as callers in fan-in answers.

The distinction is not cosmetic: a private method called only from a property setter would have no caller at all if setters were not units, and the dead-code and fan-in answers would be wrong on live code.

You meet units as the counters of tool answers (`methodsScanned` counts the units a scan looked at) and as addressable names: accessor units are named by their accessor (`get_Items`, `set_Items`), constructor units by `.ctor` (`.cctor` for the static constructor).

Note: a partial type is analyzed fragment by fragment. An initializer in one fragment and the constructor that runs it in another yield two units under the same key rather than one merged row.

## 3.5 Analysis

An **analysis** reads the solution's source files with the C# compiler's semantic model (Roslyn) and produces the model this chapter describes: the tree of projects, files, types and members, together with the measured facts and the resolved semantic values.

An analysis runs when you open a solution in the GUI, when you call `aicb analyze`, and when an MCP tool initializes itself from a solution path or refreshes its session.

- Which projects count as test projects is configurable per solution (`Test Profile`); production-focused tools exclude them by default.
- A run that cannot resolve every project's references records that its resolution was incomplete, and the affected tools say so in their answers instead of presenting a short count as a measurement. If you analyze a freshly cloned repository, build it once (or restore its packages) and analyze again to get a complete graph.

## 3.6 The tree

An analysis produces a tree. Each level narrows the one above it:

```
Solution
└─ Project          (one instance per target framework)
   └─ File          (name, path, namespace)
      └─ Type       (class, struct, interface, record, enum)
         ├─ Method
         ├─ Property
         ├─ Field
         ├─ Event
         └─ Constructor
```

Parameters belong to methods and constructors.

The tree is the backbone of every answer: a scope narrows it (a project, a namespace prefix, a file), and the sections of a context document follow its levels.

## 3.7 Facts

A **fact** is a measured property of a symbol, derived deterministically from the source code. Facts are the hard evidence; the semantic values described in the next section are resolved on top of them.

| Fact | What it records |
|---|---|
| Cyclomatic complexity | McCabe complexity. `0` = not computed because no symbol could be resolved (or from an older snapshot), `1` = linear, higher = more paths. Abstract and extern members without bodies are measured as `1`. |
| Cognitive complexity | How hard the body is to understand (nesting, `else`/`catch`, runs of boolean operators). `0` = linear or without a body and is a valid score, not a sentinel. |
| Lines of code | The lines of the declaration that carry at least one token — signature, attributes and body. Blank lines and comment-only lines are not counted; a line with code and a trailing comment is; a token that spans several lines counts each of them. This is deliberately not the raw line span, because that number grows with every comment and the best-documented method would read as the longest one. `0` = not computed. |
| Side effects | The outside-world contact of the body; see below. |
| Called project methods | The solution methods the body invokes. |
| Used types | The types the body names. |
| Injected dependencies used | Which constructor-injected dependencies the body actually uses. |
| Created types | The types the body instantiates with `new` (including target-typed `new`). |
| External calls and reads | Which BCL and third-party members the body calls, and which external state it reads (for example `System.DateTime.UtcNow`). |
| Leaked disposables | Disposables created with `new` whose ownership is neither transferred nor disposed — a resource-leak smell. |

Every unit is registered under a stable, fully-qualified lookup key built from namespace, containing type, method name and parameter types. Edges are registered under that key, so overloads, namespaces and generic substitutions stay apart; answers that return callers or callees use these keys.

### Side effects

The vocabulary of side effects is closed and has eight values:

| Token | Meaning |
|---|---|
| `io` | Filesystem and stream access. A `System.IO` type is judged by contact, not by topic: `Path` and `MemoryStream` carry no effect, `File` and `FileStream` do. |
| `network` | HTTP, socket, mail and cloud-storage calls. Addresses and message surfaces (`IPAddress`, HTTP message types) carry no effect; `Dns`, `Sockets`, `HttpClient` and comparable clients do. |
| `database` | Database drivers and ORMs (for example ADO.NET, Entity Framework Core, Dapper, Npgsql, MongoDB, Cosmos). |
| `serialization` | (De)serializer calls (for example `System.Text.Json`, Newtonsoft.Json, `XmlSerializer`, MessagePack, protobuf, YamlDotNet). |
| `logging` | Logger calls (for example `Microsoft.Extensions.Logging`, Serilog, NLog, log4net). |
| `cache` | Calls into an external cache API (for example `Microsoft.Extensions.Caching`, StackExchange.Redis, FusionCache). A cache a type holds in memory is not an outside-world effect and is never classified here. |
| `messaging` | Message-bus and queue clients (for example MassTransit, RabbitMQ, Azure Service Bus, Kafka, NATS, MediatR, Amazon SQS/SNS). |
| `unknown` | An external call that no classification rule matched — an unanalyzable third-party member, reported so the gap is visible instead of reading as pure. |

Effects include the transitive ones: a method that calls a project method which hits the database is a database method itself. The classification judges by **contact, not by topic** — `Path` and `MemoryStream` carry no `io` effect, `File` and `FileStream` do.

You meet the resolved side-effect classification in `find_by_side_effects` (which can also list only pure methods with `purity: pure` or only impure ones with `purity: impure`) and in the quality-profile option `Side-effect concentration (methods mixing 3+ effect categories)`. A context document does not render that resolved classification in `SEMANTICS`: an explicit `<ai>` annotation can appear as `SideEffects` in `AI_TAGS`, and a provenance line can state `verified-absent: sideEffects`.

## 3.8 Semantic axes and provenance

**Semantic axes** are derived values on a type or a method — what a symbol is for, where it belongs, how it behaves. Unlike facts they are not measured; they are *resolved*, and every resolved value carries its origin.

A type carries up to 16 axes, a method up to 8:

| Axis | Applies to |
|---|---|
| `Context`, `Domain`, `Role`, `Layer`, `Priority`, `Complexity`, `SideEffects`, `Stability` | types and methods |
| `Responsibility`, `Pattern`, `DependencyType`, `Determinism`, `DataAccess`, `Interaction`, `Validation`, `ErrorHandling` | types only |

Each axis is resolved through a fixed priority chain:

1. **Fact** — a deterministic value derived from the source. A fact is never overridden by an annotation.
2. **Explicit absence** — the developer declared the axis as none (see the `<ai>` annotation below). The value stays empty and is reported as verified absent.
3. **Explicit value** — a value the developer asserted in an `<ai>` annotation.
4. **Inference** — a heuristic guess, used only when none of the above applies.

**Provenance** is written into the output, so a reader can tell a measured value from an assertion and from a guess. In a full `<SEMANTICS>` block the last line is a `Source:` line:

| Form | Meaning |
|---|---|
| `Source: Resolved` | No per-field provenance was recorded; the marker stands alone. |
| `Source: Inferred`, `Source: Ai`, `Source: Fact` | Every emitted field has the same origin (short form). |
| `Source: Resolved (role=ai, layer=inferred)` | A mixed block: one `field=token` pair per field. |
| `Source: Resolved (role=inferred; verified-absent: context)` | Fields the developer declared absent are listed after `verified-absent:`. |

The tokens are `fact`, `ai`, `inferred` and `verified-absent`. In a compact `<SEMANTICS compact>` block the same information appears as an optional `src:` line, for example `src: role=ai, layer=inferred`; a compact block without a `src:` line is fully inferred.

The context document states the rule for reading these values itself: treat `inferred` values as hints, not ground truth, and do not rely on them where correctness matters.

The same vocabulary is available to queries: `confidence_map` returns the provenance of each semantic field, `coverage_gaps` lists axes that are verified absent, and `assert_absence` checks such a declaration.

## 3.9 The `<ai>` annotation

A developer can override the heuristic for a type or a method by writing an `<ai>` block into its XML documentation comment (`///`). The analysis reads it and uses it as the explicit channel of the resolution above.

Two syntaxes are accepted and may be mixed freely: colon-separated (`role: Repository`) and XML-attribute (`role="Repository"`). Several attributes may share one line.

```csharp
/// <ai
///   role="dto"
///   responsibility="Carries the inputs of a single code-analysis run from the application layer to CodeAnalyzer."
///   layer="Application"
///   stability="Evolving"
/// />
```

Three shapes are recognized: the element form `<ai> … </ai>`, a self-closing block whose attributes run over several lines and end with `/>`, and a single-line `<ai role="..." />`. Inside an element block, a line that merely ends in `/>` is ordinary content.

- Where it can stand: on a method declaration, and on the declaration of a class, struct, interface, record or enum.
- Keys: the axis names listed above (`role`, `layer`, `domain`, `context`, `priority`, `complexity`, `sideEffects`, `stability`, and for types also `responsibility`, `pattern`, `dependencyType`, `determinism`, `dataAccess`, `interaction`, `validation`, `errorHandling`). Keys are matched case-insensitively; an unknown key is ignored.
- Sentinel values: `none`, `null` or `empty` (any capitalization) suppress the inference for that field. The value is never written out as text — the field stays empty and is reported as `verified-absent`.
- `importance` is accepted as a backward-compatible alias for `priority`. The legacy values `important`, `less important` and `nice to have` resolve to `high`, `medium` and `low`.

A second example, in colon syntax, with one axis deliberately switched off:

```csharp
/// <ai>
/// role: Repository
/// stability: Stable
/// sideEffects: none
/// </ai>
```

The result for such a type: `role` and `stability` appear as `ai` in the provenance, `sideEffects` is reported as `verified-absent` and is not inferred.

## 3.10 Edges

The analysis records the relationships between symbols as **edges**. These are the kinds you will meet:

| Edge | Direction | Where you meet it |
|---|---|---|
| calls | method → method | `call_graph`, `METHOD_GRAPH` |
| called by (fan-in) | method → callers | `find_usages`, `impact_of_change`, `METHOD_USED_BY_GRAPH` |
| depends on | type → type | `CLASS_DEPENDENCY_GRAPH`, the efferent-coupling metric (`Ce`) |
| implements | type → interface | `find_implementations`, `INTERFACE_RELATIONS` |
| inherits / overrides | type → base type | `get_type_hierarchy`, `find_overrides` |
| markup references type | view → type | `find_usages`, `find_dead_code` (`kinds: type`) |
| markup binds member | view → member | `find_binding_usages` |
| member access | unit → property, field, event or enum member | `find_usages` |
| markup calls member | view → method | `find_usages` (for example a Blazor event handler referenced only from markup) |
| top-level statements reference | `Program.cs` → type | `find_usages`, `find_dead_code` (`kinds: type`) |

"Markup" covers WPF `.xaml`, Avalonia `.axaml` and Blazor `.razor` files.

The type dependency list is the union of the injection dependencies and the usage dependencies of a type, deduplicated, sorted and with self-references removed.

Note: the type dependency list is built from short type names, so two types with the same simple name in different namespaces are not distinguished there; where a collision occurs, the first one in the stable solution order wins. The circular-dependency check works on fully-qualified names and is not affected.

## 3.11 Fan-in and impact

**Fan-in** is the set of places that name a symbol — the answer to "who calls this?" It is the opposite direction of the call graph.

**Impact** is the transitive closure of the fan-in: everything that would be affected indirectly by a change to the symbol, including consumers that a compiler does not check.

`find_usages` lists the direct mentions, one level. `impact_of_change` returns the closure together with a `risk` level. The risk is calibrated on the production fan-in; callers in test projects are excluded, because exercising a symbol from tests is its designed fan-in and updating those tests is mechanical.

Note: the `risk` level measures the fan-in, not the semantics of your concrete change. A `high` on a purely additive change is expected and is not a stop signal.

## 3.12 Dead code and cycles

**Dead code** is a symbol that nothing in the analyzed scope names. The scope is what matters: reflection, dependency injection resolved from strings and callers outside the solution are invisible to a static analysis, so a missing fan-in is a place to look, not a proof. The tools report their candidates with that caveat and name what they cannot see.

**Cycle** — a chain of types or namespaces that leads back to itself. The compiler forbids cycles between projects, but it allows cycles between namespaces; `detect_circular_dependencies` reports groups of namespaces that depend on each other and shows an example edge for each link so you can see why the cycle exists.

## 3.13 Layers

A **layer** is an architecture layer such as `Domain`, `Application` or `Infrastructure`. A **Layer Profile** is a named rule set that maps types to layers, and it also defines how strictly a violation is judged (`Advisory` or `Strict`).

You meet layers in the `Layer Profiles` page of the settings, in the `Layer Profile` picker per solution, in the `--layer-profile` option, in the `.aicb.json` sidecar file and in the `LAYER_MAP` section of a context document. The `Layer` semantic axis on a type or a method is the resolved layer of that symbol.

## 3.14 The context document

The **context document** is the product of an export: a Markdown document written for a language model to read, in the **AI-Builder-MD** format. It contains the selected part of the analysis — projects, files, types and methods with their facts and semantic values — organized in named sections such as `SPEC`, `META`, `DOMAIN`, `LAYER_MAP`, `CLASS`, `INTERFACE`, `ENUM` or `QUALITY_FINDINGS`. A `<METHOD>` is a block inside a type section (and becomes an entry under `methods:` in YAML), not a top-level section. A `Source:` line inside a `<SEMANTICS>` block tells the reader where each semantic value came from, and `COMPRESSION_LEGEND` and `PATH_LEGEND` explain the notation of the document itself.

The same content can be written in two notations:

- `Tag` — the established tag markdown, with elements such as `<CLASS>…</CLASS>`.
- `Yaml` — the same information as idiomatic YAML, a lossless re-notation rather than a different selection of content.

`Yaml` is the default. You can change the notation per document: `Document Notation` in the export panel of the GUI, `--format tag|yaml` on the command line, or the `format` parameter of the MCP tool `export_markdown`. The slice tools `get_context`, `explain_symbol`, `pack_for_task` and `prepare_task` do not expose a notation switch. The file always keeps its `.md` name.

You produce a context document with the export in the GUI, with `aicb analyze --output`, with `aicb export`, and with the render tools of the MCP server — `export_markdown` for the whole solution, or a bounded slice such as `get_context`, `explain_symbol` or `pack_for_task` for one symbol's neighborhood.

## 3.15 Sessions and snapshots

### Sessions

A **session** is a named, saved working state of a solution: the selection in the `Solution Tree`, the per-node detail-level overrides, the prompt text and the frozen template. You open it later and continue where you left off. Sessions live in the `Sessions` sub-tab of the `Workspace` area; `Save Session` creates one.

Note: this is not the **MCP session** — the analysis result an MCP server keeps in its process, addressed by a `session_id`. It has no name and no database row, and it is gone when the process ends. Where both could be meant, this manual writes `MCP session`; see "Sessions and staleness".

### Snapshots

A **snapshot** is a frozen analysis result of a solution at a point in time. A run is tied to a snapshot, so a later re-analysis does not act back on completed runs. Snapshots live in the `Snapshots` sub-tab of the `Workspace` area:

- `Create Manual Snapshot` creates a named snapshot you keep.
- `Diff Two Snapshots` compares two snapshots.
- `Max snapshots per solution` limits how many automatic snapshots are kept. One automatic snapshot is written on every fresh analysis; older ones are deleted when the limit is exceeded. Snapshots you created yourself are never deleted and do not count towards the limit.

A snapshot stores the analysis as it was when it was written, including the facts of that moment.

Note: the `Snapshots` sub-tab of the `MCP Usage` page shows imported usage reports, not analysis snapshots. Imported reports sit beside the live data as named sets and are never merged into it.

## 3.16 Insights and severity

An **Insight** is a finding of the built-in code-quality analysis: a place where the tool found something worth mentioning, with a severity, a producer group and locations. You meet insights in the `Insights` tab — its header shows `Insights (N)` while findings are unseen — in the `list_insights` and `get_insight` tools, and in the `QUALITY_FINDINGS` section of a context document.

Note: `Findings` names something else. It is the region of the `Reasoning` panel that shows findings parsed from the language model's answer, not the results of the product's own analysis.

**Severity** has four levels: `Info`, `Ok`, `Warning` and `Critical`. The ordinal value is not a weight; for sorting and scoring the product uses `Critical` = 10, `Warning` = 3, `Info` = 0.5 and `Ok` = 0. On the wire the levels are lowercase tokens: `info`, `ok`, `warning`, `critical`.

**False positive** — a finding that is reported but is not real. The product carries its own taxonomy of them and does not claim that none occur: the analysis tools state their blind spots (see the fan-in, dead-code and markup notes above) rather than presenting every result as complete.

---

[&larr; 2 License, installation and updates](02-license-installation-and-updates.md) &middot; [Contents](README.md) &middot; [4 How the analysis works &rarr;](04-how-the-analysis-works.md)
