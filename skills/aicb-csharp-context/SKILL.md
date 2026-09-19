---
name: aicb-csharp-context
description: Navigate and safely change C#/.NET code with the aicb MCP server (Roslyn-backed) instead of text search. Use whenever a task touches a C# symbol — who calls this method, what breaks if I change this interface/enum/DTO, where is this interface implemented, what overrides what, which tests cover it, what gets injected where, dead code, dependency cycles, side effects, live compiler errors — or when packing codebase context for an LLM. Also states when plain grep is still the right tool.
compatibility: Requires the .NET 8 SDK and the `aicb` dotnet tool wired up as an MCP server. Analyzes C# solutions (.sln/.slnx) only.
metadata:
  project: AIContextBuilder
  version: "1.0"
---

# C# code navigation with aicb

`aicb` is a read-only MCP server that answers questions about a C# solution from
the Roslyn semantic model. Text search cannot answer those questions correctly:
grep matches substrings and therefore misses overloads, aliased usings, `partial`
types, interface dispatch and inherited members — while happily matching comments
and unrelated identifiers.

Tool names below are unprefixed. Your host may namespace them (for example
`mcp__aicb__find_usages`); use whatever form your tool list shows.

## Setup (once per machine)

The server is the `aicb` dotnet tool (requires the .NET 8 SDK), published on
nuget.org:

```sh
dotnet tool install -g AIContextBuilder
```

`dotnet tool update -g AIContextBuilder` updates it. Documentation and releases:
https://github.com/gregordadera/AICB

Then register the server with your agent, e.g. `.mcp.json` in the project root:

```json
{ "mcpServers": { "aicb": { "command": "aicb", "args": ["mcp"] } } }
```

## Step 0 — the session

Every tool accepts the **absolute `.sln` path directly as `session_id`**
(self-init). No separate analyze step is needed. The first call pays the Roslyn
load; every later call reuses the warm session, so keep passing the same value.

The server reads **live source, including uncommitted work**.

## Which tool answers which question

| Question | Tool |
|---|---|
| Who calls / uses X? | `find_usages` |
| What breaks if I change X? (transitive) | `impact_of_change` |
| Where is this interface implemented? | `find_implementations` |
| What overrides X / what is the base chain? | `find_overrides`, `get_type_hierarchy` |
| Which tests cover X? Where are the gaps? | `find_tests_for`, `coverage_gaps` |
| What is injected here? Where is it constructed? | `resolve_injection`, `instantiation_sites` |
| What does X look like? What does it do? | `symbol_signature`, `explain_symbol` |
| Where is the symbol named X? | `find_symbol` |
| Who uses SEVERAL symbols at once? (one round trip, up to 16) | `batch` with N `find_usages`/`find_symbol` sub-queries — the semantic form of a multi-name search; a tool takes exactly ONE symbol per call |
| Does the code compile right now? | `refresh_session`, then `get_diagnostics` (see "After you edit") |
| What findings would this change introduce? (in-memory, nothing written) | `evaluate_change_set` |
| Unused private methods · dependency cycles · side effects · external calls | `find_dead_code`, `detect_circular_dependencies`, `find_by_side_effects`, `calls_external` |
| Attributes · size/complexity metrics · code smells | `find_by_attribute`, `symbol_metrics`, `list_insights` |
| How is this solution laid out? | `architecture_overview` |
| Give me context for this task | `get_context`, `pack_for_task` (read) · `prepare_task` (edit-ready: bundles covering tests + naming siblings) · `export_markdown` |

About to **edit**, not just read? `prepare_task` bundles the covering tests and the
naming/file-convention siblings (`pack_for_task` does not) and renders through the
active facet template — prefer it before a change. `get_context` is the fastest
single-symbol retrieval; `export_markdown` is the whole-solution firehose, rarely
the right call.

Call `list_skills` for the full map of tool bundles — one cheap call instead of
reading many schemas. It also lists specialized tools beyond the table above
(structural twins, call-path tracing, API-surface diffs, XAML binding checks).
If a tool it names is not in your tool list, the active profile does not expose
it: start the server with `AICB_MCP_TOOLS=all` for the full surface.
`server_info` reports version and configuration.

## The pre-edit gate

Before **any** edit that changes a symbol other code names — a rename, a
signature, a default value, a visibility change, a deletion, or a shared enum,
interface, DTO or registration list — the **first** call is `impact_of_change`.

The trigger is how far the symbol *reaches*, not what kind of edit it is. A
rename is the case that slips: it looks like mechanical text work, and the
compiler does catch every renamed reference — so the gate feels unnecessary. But
a compiler checks names, not assumptions, and the consumers listed below are
exactly the ones it never sees.

It returns the transitive fan-in, including consumers the compiler will not flag:

- a count assertion in a test (`Should().HaveCount(7)`),
- a non-exhaustive `switch` *statement* that silently skips a new enum case,
- a parallel list somewhere else that must grow with yours.

`find_usages` shows only direct callers; the compiler shows only type errors.
Neither is the same question.

Treat the reported `risk` level as a measure of **fan-in size, not of your
change**. A purely additive change to a high-fan-in type is expected to read
"high" — that is not a stop sign. Check instead whether any consumer relies on
the specific value or on completeness. The risk level is calibrated on
**production** fan-in (`productionImpactCount`); test callers are excluded,
because updating them is mechanical.

## How far to trust an answer

The tools are not equally reliable, and the ranking runs **against** usage: the
ones called least are the ones that misled most. Measured 2026-09-02 over 975
corpus entries against 12 638 recorded calls, as misleading mentions per 100
calls (direct calls plus `batch` sub-queries).

| Tool | per 100 calls | What to do about it |
|---|---|---|
| `find_production_dead` | **7.4** | Worst of the family. Prefer `find_dead_code` (0.27) and read a "dead" verdict as a hypothesis to disprove — never as licence to delete. |
| `find_structural_twins` | **6.2** | Reports similarity, not equivalence. Read both candidates before merging anything. |
| `find_by_resource_leak` | **5.1** | Low volume, weak precision. Cross-check the disposal path by hand. |
| `find_by_concurrency_risk` | **3.5** | The signal has changed direction three times across milestone analyses. Treat as a pointer, not a finding. |
| `instantiation_sites` | 2.3 | Blind to container and reflection construction. Pair with `resolve_injection`. |
| `find_by_side_effects` | 2.0 | Needs a **built and restored** solution. On an unbuilt tree it reports 0 effects — which reads exactly like a clean result. |
| `coverage_gaps` · `find_binding_usages` | 1.8 · 1.6 | Both answer a narrower question than their name suggests; read the disclosed denominators. |
| `find_tests_for` | 1.6 | Its strong tier walks **two** hops, so `invokes` can mean second-hand through a helper. |
| `find_usages` · `impact_of_change` · `find_dead_code` · `refresh_session` · `server_info` | **0.2 – 0.5** | The reliable core. This is where the forced switch earns its keep. |

Two things this table does not say. It is a **rank order, not an error rate**:
the numerator counts entries that named a tool as misleading, the denominator
counts calls, and those are different populations. And a tool absent from the
table was not *proven* clean — 39 of the 73 tools simply never drew a complaint,
most of them because they are barely called.

The practical rule: **the further down a tool sits in the call counts, the more
its answer is a lead rather than a fact.** A result from the reliable core can
carry a conclusion on its own; a result from the long tail needs a second source
before you act on it.

## Reading the results

**An empty result is not proof of absence.** If `find_usages` resolves a symbol
but returns no users, or `impact_of_change` reports `risk: none`, the symbol
exists and has no *statically detectable* fan-in. It may still be reached
through XAML data binding, a DI registration, reflection, or a source generator
— none of which static analysis sees. Empty means "verify elsewhere", never
"safe to delete". `resolvedKind: "not_found"` is the different answer: the name
resolved to nothing (the response then suggests the nearest declared name).

**Results are capped, totals are not.** `find_usages` returns at most 100 items
but reports `totalFound` and `truncated`; `impact_of_change` caps its item list
at 20 while `directCount` / `transitiveCount` stay true totals. Read the counts,
not the list length.

**`find_dead_code` is deliberately narrow**: private methods with zero callers,
test projects excluded by default. Public and internal members are omitted
precisely because of the framework escapes above.

## After you edit

1. `refresh_session` — re-analyze. **Everything below depends on this, including
   `get_diagnostics`.** Usually the incremental path: document texts replayed
   into the warm snapshot, no MSBuild reload.
2. `get_diagnostics` — compiler errors and warnings in seconds; a cheap gate
   before a real build. Compiler diagnostics only: third-party analyzers and
   source generators are not run.

**That order is not cosmetic.** `get_diagnostics` compiles the *session's*
document snapshot, not the files on disk — so without the refresh it describes
the code as it was *before* your edit. Measured: a freshly written `CS0029`
answers `errorCount: 0`, and the same call after `refresh_session` answers `1`.
Such an answer leads with `verdict: "stale"` and says so, but the caveat is
cheaper to avoid than to read.

For a structural change, call `save_session` before and `compare_with_previous`
after to see what actually moved.

## Symbol or text? (when grep is still right)

Ask this before every text search:

- **A PascalCase C# identifier** — type, method, interface, property, field — is
  a **symbol**. Use the table above, not grep.
- **A multi-name alternation (`A|B|C`) is text by construction**: no MCP tool
  accepts a multi-name pattern. If it was a usage question on several names, the
  semantic form is one `batch` call with N `find_usages` sub-queries; for finding
  test methods / assertion sites / model fields by name, grep stays the right tool.
- **Text stays text**: string literals, comments, log messages, config keys,
  version strings, SQL, regexes.
- **Non-C# files stay grep**: `.xaml`, `.json`, `.csproj`, `.md`, `.yml`. The
  fan-in graph covers C# edges only — markup and generated bindings are not in it.
- Reading a file you are about to edit is always fine.

`aicb` is **read-only**. It never writes; make changes with your normal edit
tools, and use your shell for build, test and git.

## First run on an unfamiliar solution

`solution_config_status` reports whether namespace exclusions, test detection and
layer mapping are set up. If a slot is uninitialized, run `init_solution_config`
and then `apply_solution_config` — this is persisted to the config DB and to a
git-tracked `<Solution>.aicb.json` next to the `.sln`, so the setup travels with
the repository.

## Limits worth knowing

- C# only, one solution per session.
- Opening a solution runs its MSBuild logic to resolve references, exactly like
  an IDE — analyze only solutions you trust.
- Results reflect the last analysis: after **your own** edits, `refresh_session`.
- The fan-in graph carries exactly **two** markup edge kinds: a `{Binding}` ROOT
  member (low-confidence, tagged `(xaml)`, against the resolved view-model) and a
  TYPE reference. Everything else in markup is invisible to it — a resource key,
  and the MEMBER half of any attribute (a `Click=` handler, an `{x:Static}`
  member) — so reach for `find_binding_usages` / `find_resource_usages` or a text
  search there. (Broken `{Binding}` members are a separate, opt-in check:
  `find_unresolved_bindings`.)
