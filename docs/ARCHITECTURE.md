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

## What is measured publicly, and what is not?

The documentation separates observations from intended benefits.

| Claim | Public status |
|---|---|
| AICB returns semantic, aggregated answers that differ structurally from text search | Explained with concrete compiler-semantic and markup cases in the general manual |
| AICB versus the Roslyn language server on a selected symbol sample | Method and measured examples are published in the introduction; it is explicitly a structural comparison, not a general agent-quality benchmark |
| Token-budget and context-selection behavior | Selection rules, floors, precedence and omission disclosures are documented |
| Standardized performance on a very large public solution | **Not yet published** |
| Agent success, time, tool calls and tokens with versus without AICB | **Not yet published** |
| Reproducible head-to-head comparison with CodeLens, DotLens or another named product | **Not yet published** |

Until those last three studies exist, AICB does not claim a measured universal
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
boundary.

## Where to continue

- [General reference manual](manual/general/README.md)
- [MCP server manual](manual/mcp/README.md)
- [Desktop app manual](manual/desktop-app/README.md)
- [Generated tool reference](TOOLS.md)
- [Security policy](../SECURITY.md)
