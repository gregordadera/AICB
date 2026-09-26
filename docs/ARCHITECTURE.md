# AICB architecture, limits and evidence

This page answers the architecture questions that matter when a person or coding
agent decides whether to trust an AICB answer. It is deliberately question-first
so that the answers remain discoverable without reading all three reference
manuals.

## Is AICB only a cache around Roslyn queries?

No. Roslyn supplies the parsed syntax, compiler symbols, semantic models and
compilations. AICB walks those models, records its own facts and consolidates them
into an analyzed solution model. MCP tools then query or traverse that model; they
do not start an unrelated Roslyn search for every question.

This distinction does not make AICB a model of everything the program can do at
runtime. It is a static semantic model with explicitly documented extensions and
limits.

```text
Solution and project-shaping files
                ↓
        MSBuild workspace load
                ↓
 Syntax trees + Roslyn semantic models
                ↓
 Document facts: declarations, calls, types,
 DI registrations, tests, markup and metrics
                ↓
 Consolidated indexes and derived relationships
                ↓
 Tool-specific traversal / selection / rendering
```

The detailed analysis sequence is documented in
[How the analysis works](manual/general/04-how-the-analysis-works.md).

## What is kept in memory?

A live MCP session holds the analyzed solution graph and the Roslyn workspace that
produced it. The model contains declared types and units together with facts and
indexes used for callers, type fan-in, implementations, tests, DI, markup,
architecture, metrics and side effects.

The boundary is important:

| Stage | Examples | When it happens |
|---|---|---|
| Roslyn input | Syntax trees, symbols, semantic models and compilations | While loading and analyzing documents |
| Recorded facts | Declarations, calls, type references, construction sites, test evidence and statically readable registrations | During the document walk |
| Consolidated relationships | Caller and type fan-in, implemented-by lists, resolved XAML references and transitive effect classifications | Post-processing after the document walk |
| Question-specific result | Transitive impact closure, risk summary, filtered result lists and task context | When a tool is called |
| Rendered output | AI-Builder-MD in tag or YAML notation | When context is requested or exported |

In other words, AICB keeps reusable semantic facts and indexes warm. A particular
tool answer may still be calculated from them on demand. “In memory” does not mean
that every possible transitive path or context document is stored in advance.

Two live-only results are not reconstructed from a persisted snapshot: unresolved
XAML bindings and the project-completeness record. A recalled snapshot therefore
has a narrower contract than a freshly analyzed session.

The persistence surfaces have deliberately different contracts:

| Surface | Stores | Does not store |
|---|---|---|
| Live MCP session | Analyzed graph plus the Roslyn workspace in one server process | Cross-process state or unsaved editor buffers |
| Remembered codebase | A persisted model that `recall_codebase` can rehydrate without Roslyn | A live workspace, reliable line numbers, the layer profile or every live-only insight |
| Saved snapshot | A named analysis baseline for later comparisons | A mutable live session |
| `<Solution>.aicb.json` | Portable layer, exclusion, test, suppression and analysis-scope configuration | Analysis results, sessions, snapshots or credentials |

`remember_codebase` returns a live session and persists the model. A later process
can use `recall_codebase`; its response discloses payload, analyzer and file-set
drift even though the recalled graph remains available. `refresh_remembered`
performs a new live analysis, restores the live-only contract and persists the new
snapshot. This distinction prevents “persistent memory” from being mistaken for a
shared live Roslyn workspace.

## What does AICB add beyond Roslyn?

Roslyn is the semantic foundation. AICB adds product-level questions and
aggregation on top of it, including:

- transitive change impact and production/test separation;
- call, type, implementation and construction relationships presented at symbol
  level instead of as an unaggregated list of positions;
- test discovery and evidence tiers;
- Microsoft DI registration and constructor-injection relationships;
- selected XAML/AXAML bindings, resources and type references;
- side-effect and external-call classification;
- layers, cycles, quality insights, metrics and change-policy checks;
- goal-driven selection and token-budgeted AI-Builder-MD rendering;
- provenance and optional `<ai>` annotations for meaning the compiler cannot infer.

A language server remains the better tool for unsaved editor buffers, navigable
source positions, fuzzy symbol lookup and third-party analyzer diagnostics. AICB
reads saved files and normally answers at symbol level. The measured comparison is
in [How AICB differs from a language server](manual/general/01-introduction.md#16-how-aicb-differs-from-a-language-server).

## How incremental refresh works

A session records a hash of the analyzed file set. When saved source changes are
detected, the incremental path replays changed document texts into the warm Roslyn
solution and reuses facts for documents the change could not have reached. The
response identifies this as `mode: "incremental"`.

An unavailable incremental path or `refresh_session(force: true)` causes a full
workspace reload. A build or restore can change resolved references without
changing source files; after either, use `force: true` when an earlier answer
reported unresolved projects.

A session has at most one refresh in flight. A concurrent caller joins that refresh
instead of starting a second analysis of the same session. The complete operational
contract is in
[Sessions and staleness](manual/mcp/03-sessions-and-staleness.md).

### How far does one edit invalidate reuse?

There are two conservative gates. The outer refresh planner permits its incremental
path only for an existing C# file whose text changed in place. A file addition or
removal, or a changed non-C# file tracked by the snapshot (including XAML and
project-shaping files), takes the full reload path because it can change project
membership, generated code or compilation structure.

The analyzer then decides which previous document results are safe to replay:

- Every changed document is analyzed again, including each target-framework or
  linked-file instance of the same path.
- If only method bodies moved and the declaration surface stayed the same, unchanged
  documents can be reused.
- If declarations moved—including a public API change—the analyzer also invalidates
  documents that name a changed identifier, reference a type declared in the changed
  document, or belong to a transitive derived-type chain rooted there.
- A changed global using, extern alias or assembly attribute disables document reuse
  for that run because it can change binding throughout a project without an
  ordinary reference edge.
- A changed layer profile, namespace-exclusion provider, target-framework scope,
  solution assembly set or project set also disables reuse.

“Public” is therefore not a special invalidation switch. What matters is whether the
declaration surface changed and which documents can bind differently as a result.
The closures deliberately prefer re-analyzing too much over serving a plausible
stale edge. This is document-granular reuse, not method-granular patching of an
already rendered answer.

The regression suite compares the complete normalized analysis dump from an
incrementally refreshed session with a separately opened full-reload session. Its
single-edit matrix covers method-body changes, added and deleted methods, changed
signatures, deleted and renamed types, changes in one half of a partial type, and
re-running source-generated members on the forked Roslyn snapshot. It also asserts
that the incremental path really ran, so an accidental full reload cannot make the
comparison pass vacuously. File additions or removals and changes to `.csproj`,
`.props`, `.targets`, solution, XAML and other project-shaping files deliberately
fall back to a full reload. A combined public matrix for simultaneous multi-file
edits and branch switches has not yet been published.

## Which data structures hold and deduplicate the graph?

The central run state uses separate indexes for separate fact families rather than
one universal graph object. Method, property, field, event, enum-member and type
fan-in; interface implementations; interface-method implementations; and resolved
markup fan-in each have their own keyed index.

Most fan-in indexes have the shape
`Dictionary<canonical symbol key, HashSet<consumer key>>`. The dictionary gives
direct lookup by symbol; the set makes insertion idempotent and avoids storing the
same edge twice when several analysis paths discover it. Method keys include the
containing type and parameter types, and explicit-interface implementations keep
the interface identity in the key, so overloads and two distinct explicit
implementations do not collapse onto one node.

Raw facts that require a later binding step—XAML bindings and type references,
Razor member/parameter references and top-level-statement type references—are kept
in lists during the document walk. Post-processing resolves them against the built
types and folds the result into the corresponding fan-in index. Transitive change
impact and similar answers traverse these reusable indexes when requested rather
than storing every possible path in advance.

Document analysis can run in parallel. Short index insertions share one mutation
lock, which avoids cross-index lock ordering and keeps a document's registrations
consistent. For incremental reuse, each document additionally records a
contribution log containing every index insertion it made. An unchanged document
can replay that log into the new run state; the `HashSet`-backed indexes make the
replay idempotent. Its cached record also carries the pristine analyzed file,
declaration fingerprint, identifier hashes, declared types, base chain and referenced
type hashes used by the invalidation rules above.

## Do the GUI and MCP server share the same RAM graph?

No. They share the same analysis and rendering implementation, and by default they
share the local configuration database. They are still separate processes and do
not share one live in-memory analysis session.

An MCP session belongs to one `aicb mcp` process. A second server process has its
own session cache and analyzes the solution again unless it explicitly recalls a
persisted snapshot. The default MCP cache keeps up to eight sessions, expires an
idle session after 90 minutes and evicts the least recently used session on
overflow. These values are configurable per server process.

This process boundary also applies to agents: two agents connected to different
server processes do not mutate or race on one RAM graph. They can still read and
write the same on-disk source tree and use the same local configuration database,
so each process must refresh after relevant saved edits.

## How does AICB choose context for an agent?

The task-oriented tools start from explicit evidence rather than sending the whole
repository:

1. `pack_for_task` identifies symbols named in the natural-language goal and
   expands their semantic neighbourhood.
2. `prepare_task` adds covering tests and one or two likely siblings based on
   naming or file conventions, such as a validator or factory.
3. Exact seed symbols remain pinned. Under budget pressure, AICB reduces detail and
   removes lower-relevance surrounding material rather than cutting a code block in
   the middle.
4. The leading bundle manifest reports seeds, tests, siblings, caps and omissions.
5. `measure` can return the exact token cost of planned answers before their payloads
   are requested.

This is bounded task preparation, not an autonomous solution to arbitrary task
semantics. If a goal names `DiscountCalculator`, for example, the bundle can seed
that symbol and add known callers, callees, dependencies, tests and a conventionally
named sibling. It cannot guarantee discovery of an unmentioned runtime registration,
a relationship hidden in configuration, or the business meaning of “discount.” The
agent still chooses the goal, interprets the evidence and calls specialized tools
for DI, markup, runtime uncertainty or other axes when the manifest and hints require
them.

Likewise, AICB detects **structural** budget pressure: the manifest reports omitted
types, tests and siblings, result caps, truncation and cases where a seed had to fall
back to a smaller structural rendering. It cannot prove that a budget is semantically
large enough for the agent to complete the task correctly. That needs task-level
evaluation, which is a separate benchmark question.

For budgeted whole-document rendering, the active relevance score uses factors such
as log-damped fan-in, visibility, explicit priority, entry-point status, role, file
path and user hints. A personalized PageRank implementation exists but is **not
active** in released selection or search ranking. The exact current formula and
activation rules are documented in
[PageRank and the relevance score](manual/general/04-how-the-analysis-works.md#413-pagerank-and-the-relevance-score);
task-bundle behavior is documented with
[`pack_for_task` and `prepare_task`](manual/mcp/09-tool-reference-markup-export-review-and-insights.md#92-packing-and-exporting-context).

## What can static analysis miss?

### Runtime behavior

Reflection, runtime assembly scanning, generated or interpreted code, dynamic
configuration, serializers and consumers outside the analyzed solution can create
relationships that do not appear in the static graph. An empty caller list is not
proof that code is unused.

### Dependency injection

AICB reads statically recognizable Microsoft-DI-shaped registrations and
constructor injection. A registration whose type is produced at runtime is reported
as dynamic, unknown or factory-shaped rather than guessed. Other containers and
runtime scanning need separate verification.

### XAML and AXAML

AICB resolves bindings, resources and selected type references where their source
and type can be established safely. Templates, inherited data contexts, runtime
resource lookup and third-party markup can make that impossible. The analysis skips
an unknown scope conservatively instead of assigning it to a plausible type.

### Side effects

The eight effect tokens (`io`, `network`, `database`, `serialization`, `logging`,
`cache`, `messaging`, `unknown`) describe static contact with an outside-world API.
Known effects propagate upward through known call edges. This is not general
data-flow, taint, escape or runtime state analysis. Missing project references can
make effect results a lower bound rather than a proof of purity.

## How does an answer disclose uncertainty?

Before treating an empty or short result as proof, inspect the response metadata:

| Signal | Meaning | Typical action |
|---|---|---|
| `staleness` | Saved source has moved since the session was analyzed, or an automatic refresh ran or failed | Save files and call `refresh_session` if needed |
| `incompleteProjects` | One or more project compilations could not resolve core references, so semantic edges may be missing | Restore/build, then `refresh_session(force: true)` |
| `totalFound` and `truncated` | The tool found more items than it returned | Raise the relevant cap or narrow the query |
| Bundle manifest / leading comment | Tests, siblings, types or methods were omitted under the token budget | Increase the budget or request the omitted axis directly |
| Dynamic/unknown placeholders | A relationship exists syntactically but its target cannot be established statically | Verify runtime configuration or construction code |

## How does AICB scale on large solutions?

There is no published hard project-count ceiling. The resource cost depends on the
shape of the input rather than one number: loaded projects, C# documents,
target-framework instances, linked files, compilations and the density of the
resulting relationship indexes all contribute. Multiple warm MCP sessions also
hold separate graphs and Roslyn workspaces; the session cache therefore has a
configurable count and time-to-live rather than assuming memory is free.

The available scale controls act at different stages:

| Control | What it reduces | What it does not promise |
|---|---|---|
| `.slnf` | Projects loaded by MSBuild and analyzed by AICB | Coverage outside the filter |
| `analyzePreferredTfmOnly` | Duplicate project instances and document analysis for multi-targeted projects | Fan-in edges that exist only in a non-preferred target framework |
| Warm sessions and incremental refresh | Repeated load and analysis work after eligible saved-source edits | Incremental handling of added/removed files, project-shaping changes or every branch switch |
| Persisted recall | Startup analysis when a reduced recalled-session contract is sufficient | A live Roslyn workspace, line numbers or every live-only insight |
| `summaryOnly`, result caps, scope and token budgets | Response size and agent context cost | Lower solution-load or whole-analysis cost; some scopes are post-filters |

For architecture orientation, `summaryOnly: true` is recommended for extreme
solutions such as those with 200 or more projects; that is a response safeguard,
not a declared support limit. The desktop app can record per-phase load timings in
`load-perf.log`, while `usage_report` records local per-tool latency and result-size
distributions. These let a team measure its own solution rather than extrapolate
from an unrelated repository.

### Published benchmark (2026-09-26)

A standardized public benchmark that reports cold analysis time, warm-query time
and peak RAM on three public .NET solutions is published below. Measurement
procedure: each repository was analyzed at the stated revision after a restore
with its pinned SDK; a fresh MCP server process answered `solution_metrics` twice
on the restored solution. The first call is **cold** — it carries the full MSBuild
load and Roslyn analysis, with no warm AICB session, no persisted analysis and no
session cache. The second identical call in the same session is the **warm**
query. Peak RAM is the peak working set of the AICB process tree during the cold
phase, sampled once per second. NuGet and MSBuild machine caches were warm from
the restore; the very first analysis on a cold machine additionally pays one-time
MSBuild node startup (about 9 s on the test machine). `get_diagnostics` reported
`incompleteProjects: []` on all three solutions.

| Solution | Repository revision | C# LOC (git-tracked) | Cold | Warm | Peak RAM | Production types / methods |
| --- | --- | ---: | ---: | ---: | ---: | ---: |
| `Serilog.sln` | `serilog/serilog` `2ef6364` | ≈ 24,700 | 9.5 s | 188 ms | 1.21 GB | 129 / 657 |
| `src/MahApps.Metro.sln` | `MahApps/MahApps.Metro` `72099e3` | ≈ 54,700 | 30.1 s | 215 ms | 2.92 GB | 322 / 1,840 |
| `RavenDB.sln` | `ravendb/ravendb` `5415dde` | ≈ 1.76 M | 96.6 s | 1.86 s | 4.05 GB | 9,316 / 33,606 |

Machine: Windows 10 Pro, Intel Core i9-9900K (8 cores / 16 threads), 32 GB RAM.
AICB `0.5.464.52` (build `d7935ebb`), measured 2026-09-26.

Reading notes: the MahApps solution as published carries 755 compiler diagnostics
in its `net462` test project; they do not affect the production-scope analysis.
Serilog's restore required `-p:NuGetAudit=false` because a vulnerable transitive
test dependency would otherwise fail the restore as an error. Incremental refresh
time is not yet covered by this benchmark, and these numbers are measured data
points on one machine, not a universal performance promise.

## What long-term reliability and compatibility are promised?

The public release channel currently declares no LTS support window, response-time
SLA or immutable compatibility contract for every MCP response, database schema or
persisted analysis payload. The `0.5.x` line should therefore be treated as an
evolving product, with the changelog as the release-level record rather than an
unstated promise of wire- or storage-format stability.

The product does provide defensive compatibility behavior:

- `server_info` reports the product version, build commit, database schema and
  binary/configuration/analyzer drift.
- A persisted analysis records its payload schema and analyzer identity. If either
  is incompatible, AICB discards reuse and performs a full analysis instead of
  loading a plausible but unsafe model.
- Database migrations are forward migrations. The desktop application refuses to
  write a database produced by a newer schema rather than saving an older shape
  over it.
- The database and application data survive an update, and optional automatic
  backups can archive them. `<Solution>.aicb.json` remains the Git-trackable source
  for portable solution configuration.
- A safe rollback uses an older binary with a separate database or a backup made
  before migration; pointing it at a database already migrated by a newer version
  is not a supported downgrade path.

Free/public support is best effort through Issues and Discussions, without a
guaranteed response time. An individual commercial agreement can define support
coverage, response targets, version maintenance and the priority or delivery of
specific improvements. Those commitments apply only as written in that agreement.

## What is measured publicly, and what is not?

The documentation separates observations from intended benefits.

| Claim | Public status |
|---|---|
| AICB returns semantic, aggregated answers that differ structurally from text search | Explained with concrete compiler-semantic and markup cases in the general manual |
| AICB versus the Roslyn language server on a selected symbol sample | Method and measured examples are published in the introduction; it is explicitly a structural comparison, not a general agent-quality benchmark |
| Token-budget and context-selection behavior | Selection rules, floors, precedence and omission disclosures are documented |
| Incremental refresh versus a clean full reload | A regression matrix compares the complete normalized analysis for the listed single-edit shapes; a combined public multi-file/branch-switch matrix is not yet published |
| Standardized cold/warm performance and peak RAM on public solutions (≈ 25k, ≈ 55k and ≈ 1.8M lines of C#) | Published with revisions, machine, AICB version, procedure and caveats; see [How does AICB scale on large solutions?](#how-does-aicb-scale-on-large-solutions) |
| Agent success, time, tool calls and tokens with versus without AICB | **Not yet published** |
| Reproducible head-to-head comparison with CodeLens, DotLens or another named product | **Not yet published** |
| Per-tool false-positive and false-negative rates over a representative public corpus | **Not yet published**; conservative tool verdicts and profile curation are safeguards, not a substitute for that measurement |

Until those remaining studies exist, AICB does not claim a measured universal
speedup, lower token bill or higher agent success rate. A future benchmark should
publish the repository and revision, AICB and competitor versions, machine,
commands, raw outputs, task set and denominators—not only a summary score.

## What is disclosed about the product itself?

AICB is closed source; the public repository contains documentation, releases,
checksums, license terms, third-party notices and the changelog. Exact production
line counts, development effort, AI-assistance share and a repository-wide coverage
percentage are not currently published. Those numbers are not used as quality
claims. Release behavior and supported surfaces are documented instead, and the
public [security policy](../SECURITY.md) explains the local-processing and network
boundary. No independent security audit or reproducible-build attestation is
currently published. SHA-256 release checksums verify that a download matches the
published artifact; they are not an external audit of the proprietary implementation.

## Where to continue

- [General reference manual](manual/general/README.md)
- [MCP server manual](manual/mcp/README.md)
- [Desktop app manual](manual/desktop-app/README.md)
- [Generated tool reference](TOOLS.md)
- [Security policy](../SECURITY.md)
