[AICB – MCP Server](README.md) &middot; chapter 5 of 12

# 5 Calling tools: conventions, batch and aicb call

Every aicb tool is a request over MCP, but there is more than one way to send it. This chapter covers the four ways a tool can be reached, the two meta-tools `batch` and `measure` that fan out over many read-only queries at once, the one-shot CLI invoker `aicb call`, the parameter aliases the server tolerates, which tools write, and the conventions that hold across the whole catalogue.

## 5.1 The four call paths

A tool is reachable through up to four different doors. A tool that works through only one of them is a defect, so the doors are described here once for the whole catalogue.

| Path | What it is | What it reaches |
|---|---|---|
| 1 · `tools/call` | The normal MCP path a connected client uses. | Exactly the tools of the **active tool pool**. A name outside the pool is refused even though it is registered. |
| 2 · `batch` / `measure` | The read-only dispatch registry behind the two meta-tools. | The **48 dispatchable tools** (see below). |
| 3 · `aicb call <tool>` | A one-shot invocation from the command line, **without a running server**. | **All 82 tools**, reading and writing alike — this verb has no curation. |
| 4 · `tools/list` | The parameter surface your client is shown. | The same set as path 1: listing and callability are read from one and the same live source, so they cannot disagree. |

How many tools each path reaches, depending on how the server was started:

| Path | Shipped default | Under "Full Select" | With `AICB_MCP_TOOLS=all` |
|---|---|---|---|
| 1 · `tools/call` | **54** | 72 | 82 |
| 2 · `batch` / `measure` | **33** (48 registry entries minus the 15 outside the default pool) | 48 | 48 |
| 3 · `aicb call` | **82** — no curation at all | 82 | 82 |
| 4 · `tools/list` | **54** | 72 | 82 |

Two properties of this table are easy to misread:

- **Path 3 records no usage data.** Tool-call telemetry hangs on the `tools/call` pipeline, which `aicb call` does not use.
- **Path 2 records the parent call and a sub-query tally, but no row per sub-query.** The tally is described under "Counting sub-queries" below.

The refusal on path 1 reads:

```
Tool '<name>' is not in the active profile - call list_mcp_profiles to see the profiles and
their tools, then restart the server with 'aicb mcp --mcp-profile <id>' to run under a different one.
```

You cannot lock yourself out of the pool question: every profile includes the navigation core (the everyday tools plus `list_mcp_profiles`, `list_skills`, `docs`, `server_info` and `usage_report`), so `list_mcp_profiles` and `list_skills` are always callable and always tell you what the current pool contains. See "Profiles, pools and facets" for the profiles themselves and for `AICB_MCP_TOOLS`.

## 5.2 `batch`: many read-only queries in one round-trip

`batch` runs several **read-only** queries in one round-trip, sharing one analysis session. It is the right call when you already know you need several answers about the same subject — for example `find_usages` plus `get_type_hierarchy` plus `find_tests_for` for one symbol, `list_insights` followed by `get_insight`, or the markup fan-in trio next to a symbol query.

| Parameter | Type | Required | Default | Meaning |
|---|---|---|---|---|
| `sessionId` | string | yes | — | The session shared by all sub-queries. Accepts the session ID from `analyze_solution` or an absolute `.sln`/`.slnx`/`.slnf` path to self-initialize once. Do **not** repeat it inside the sub-queries. |
| `queries` | array | yes | — | An array of `{ tool, args }` objects. `tool` is a read-only tool name; `args` is that tool's own argument object **without** `sessionId`. `args` may be omitted when the tool takes no arguments. Maximum **16**. |

A query element is exactly `{"tool": "<name>", "args": { … }}`. The `args` object may also be passed as a JSON **string**, which is unwrapped for you.

Rules and limits:

- **Maximum 16 sub-queries.** Exceeding the limit fails the **whole** batch with an actionable message rather than silently truncating — a silent cap would read as "all of them ran". Split a larger set into several calls. An empty `queries` array is rejected as well.
- **Sub-queries run sequentially**, in the order you list them.
- **A wrong `sessionId` fails the call once, up front** — not once per sub-query. This is also the only self-initialization point: a `.sln` path you pass is analyzed exactly once for all sub-queries.
- **Each sub-query is isolated.** One that fails reports `ok: false` plus its error while the others still answer normally. A cancelled call aborts as a whole.
- **The active pool governs the proxy path too.** A read-only tool that your active profile does not expose is refused per entry, with its own message — exactly as a direct call would be.

The response has the shape `{ results: [ {tool, ok, result | error} ], count, okCount }`:

| Field | Meaning |
|---|---|
| `tool` | The tool name of the sub-query. |
| `ok` | `true` for an answer, `false` for a failure or an omission. |
| `result` | The answer. A JSON-returning tool's answer is nested as a JSON object (not an escaped string); a Markdown-returning tool's answer (for example `get_context` or `explain_symbol`) arrives as a string. |
| `error` | The failure message when `ok` is `false`. |
| `note` | An optional disclosure, omitted when there is nothing to disclose (see "Silently dropped arguments"). |

**Response budget: 9,000 tokens.** The answers are walked in order; an answer that is larger than the whole budget, or that would push the running total past it, is replaced by `ok: false` with its measured size and a pointer to call that tool directly. Only the **answer** is trimmed — the work was already done, so a dropped result costs latency but never correctness. In practice this only affects the slice tools, whose renders can be tens of thousands of tokens. `measure` has no such budget, because it has nothing large to return.

**Identifying a sub-query in an error or omission.** Because several sub-queries may name the same tool, failure and omission messages carry an echo of the sub-query's identifying arguments (`symbol=OrderService`, the first three scalar arguments) — inside the message text, not as a field of its own.

### Why a sub-query was refused

`batch` and `measure` refuse tools for **four different kinds of reason**, and the refusal message names which one applies. Only the first is about writing.

| # | Reason | Example names in the message |
|---|---|---|
| 1 | It **mutates session state or writes** — the read-only boundary. | `analyze_solution`, `refresh_session`, `apply_solution_config`, `save_session`, `remember_codebase`, `export_markdown`, `install_agent_hooks` |
| 2 | It needs a **second state** — another session or a stored snapshot, which one shared session cannot express. | `semantic_diff`, `diff_review`, `verify_claim`, `compare_with_previous` |
| 3 | **Recursion** — the meta-tools themselves. | `batch`, `measure` |
| 4 | It is **read-only but a poor batch member**: a heavyweight walk, renderer or multi-file payload whose answer would routinely exceed the response budget and be dropped after the work was paid for. | `evaluate_change_set`, `init_solution_config`, `prepare_task`, `review_context` |

Note: the names in each bracket are **examples, not the whole group**. A tool's absence from those lists does not mean it writes anything — it only means the reason does not name it. The message itself says so. In particular, a number of non-dispatchable tools must be called directly (for example `docs`, `list_skills`, `server_info`, `list_mcp_profiles`, `usage_report`, `solution_config_status`, `check_solution_config_drift`). The last two are observational in purpose but can initialize a previously unknown solution row in the configuration database.

The final `Available:` line of the refusal names **every** dispatchable tool, regardless of your active profile. Since a sub-query outside the active profile is refused per item, take the tools you can actually dispatch from `list_skills` under `inPool`, not from that line.

A sub-query naming a tool the server does not register at all gets a different opening sentence — "is not a tool this server registers at all - check the spelling first" — so a typo and a real tool at the dispatch boundary are distinguishable. An empty tool name is reported as a malformed query object, not as a bad tool name.

### The 48 dispatchable tools

These are the tools `batch` and `measure` can dispatch (alphabetical, as the refusal message prints them):

```
architecture_overview · assert_absence · call_graph · calls_external · check_doc_drift ·
check_pattern_drift · confidence_map · coverage_gaps · describe_api_surface ·
detect_circular_dependencies · explain_symbol · find_binding_usages · find_by_attribute ·
find_by_code_traits · find_by_complexity_and_coverage · find_by_concurrency_risk ·
find_by_event_subscription · find_by_resource_leak · find_by_returns_semantic ·
find_by_semantics · find_by_side_effects · find_dead_code · find_god_objects ·
find_implementations · find_overrides · find_production_dead · find_resource_usages ·
find_structural_twins · find_symbol · find_tests_for · find_unresolved_bindings ·
find_usages · get_context · get_diagnostics · get_insight · get_type_hierarchy ·
impact_of_change · instantiation_sites · lifecycle_of · list_insight_producers ·
list_insights · pack_for_task · resolve_injection · solution_metrics · symbol_metrics ·
symbol_signature · trace_flow · type_dependency_path
```

Fifteen of them (`check_doc_drift`, `check_pattern_drift`, `confidence_map`, `find_by_code_traits`, `find_by_complexity_and_coverage`, `find_by_concurrency_risk`, `find_by_resource_leak`, `find_by_returns_semantic`, `find_god_objects`, `find_production_dead`, `find_structural_twins`, `lifecycle_of`, `list_insight_producers`, `trace_flow`, `type_dependency_path`) are outside the shipped default pool: they dispatch under "Full Select", `AICB_MCP_TOOLS=all`, or a profile that exposes them, and are refused per item otherwise. The other 34 registered tools are not dispatchable at all — call them directly.

### Counting sub-queries

A `batch` (and `measure`) parent call records **what it dispatched**, so a tool reached only through `batch` no longer reads as never called:

- One increment per dispatched sub-query, grouped by tool name, plus a separate error counter. The user-visible form is `subQueries: [{ tool, calls, errors }]`.
- A sub-query counts as **failed** when it threw **or** was refused by the active pool. A refusal is a statement about your **profile**, not about the tool, so this error count is not comparable with a normal tool row's error rate.
- An unrecognized tool name collapses into the single literal `(unknown)`, so a typo cannot grow the key space — and the count itself is a signal about guessed tool names.
- **Not counted:** duration, result size, error text, and no row per sub-query. Correlation back to the caller is positional and by tool name only.
- When nothing was dispatched the tally is `null`, which applies to every ordinary (non-fan-out) call. Rows recorded before the tally existed simply omit it.
- **`measure` sub-queries are excluded from the aggregation.** `measure` rows are written, but every reader filters them out: it runs the tool fully, yet the caller consumes the **size** of the answer rather than the answer.

The tally is reported by `usage_report` under `subQueries` (uncapped, sorted by call count), and in the GUI's **MCP Usage** panel as the `Batch` column. Its tooltip is the exact reading instruction: *"How often the tool was DISPATCHED as a sub-query inside a batch. Those calls record no row of their own, so before this column a tool used only through batch read as never called. Read it as attempts, not runs: a sub-query the active profile refused, or one that failed on its arguments, is counted here too. measure is excluded - it runs the tool fully, but the caller consumes the SIZE of the answer rather than the answer."* The neighbouring `Calls` column counts only direct calls.

## 5.3 `measure`: size an answer before you pull it

`measure` answers "how big **would** this answer be" — the exact token count, without returning the answer. Use it to decide before you pull: whether a call is worth making, which `budget` to pass to a slice tool (`get_context`, `explain_symbol`, `pack_for_task`), or whether to narrow `scope` first.

`measure` takes the **same parameters as `batch`** (`sessionId`, `queries`, maximum 16) and dispatches through the same read-only registry, so it accepts exactly the 48 tools above and refuses the same tools for the same four reasons.

The response is `{ measurements: [...], count, okCount, totalTokens }`. Per entry:

| Field | Meaning |
|---|---|
| `tool` | The measured tool name. |
| `ok` | Whether the query succeeded. |
| `tokens` | The real tokenizer count (`cl100k_base`) of the exact text the tool would return. |
| `chars` | The character count of that text. |
| `returned` / `totalFound` / `truncated` | Passed through when the measured tool answers with a capped envelope, so you also see whether you would be seeing everything. Several axes sum, and `truncated` is `true` if any axis truncated. |
| `budgetNote` | For the Markdown slice tools, which have no envelope: the renderer's budget disclosure, passed through verbatim. If it says types were dropped, the answer you are pricing is already cut and a larger `budget` is what buys it back. |
| `error` | The failure message when the query failed. |
| `note` | An optional disclosure, as in `batch`. |

`totalTokens` is the summed cost of all measured queries, so you can weigh several candidate calls without adding them up yourself.

Note: `measure` does **not** make a query cheaper to run. The server does the full work either way; only inspecting the answer becomes cheap — roughly 50 tokens instead of the answer. Measure to **decide**, then call once; do not measure every call by reflex.

Note: `measure` has exactly one steering deviation. For `export_markdown` — which cannot be dispatched and whose render can be tens of megabytes — the refusal does not say "call it directly" but gives the cheaper advice: give it an `outputPath`, which renders once, writes the file and returns the exact character count.

## 5.4 `aicb call`: one-shot invocation without a server

`aicb call <tool>` invokes one MCP tool from the command line without starting a stdio server. It is meant for validating any tool — including a brand-new or non-default-pool one — in a single process.

```
aicb call <tool> [--sln <path>] [--arg name=value]... [--db-path <path>]
```

| Option | Meaning |
|---|---|
| `<tool>` | The MCP tool name to invoke, for example `find_usages`, `find_production_dead`, `server_info`. |
| `--sln <path>` | Absolute `.sln` path, bound to the tool's `sessionId` or `solutionPath` argument. Self-initializes and analyzes it once. Omit it for a tool that needs no session, such as `server_info`. |
| `--arg name=value` | A tool argument. Repeat the option for each argument, for example `--arg symbol=OrderService --arg includeTests=true`. |
| `--db-path <path>` | Optional config DB, the same one the GUI uses. DB-defaulting tools and self-init then apply its per-solution configuration. Without it the tool runs DB-free. |

Examples:

```
aicb call server_info
aicb call find_usages --sln C:/repo/App.sln --arg symbol=OrderService
aicb call find_implementations --sln C:/repo/App.sln --arg symbol=IInsightsService
aicb call batch --sln C:/repo/App.sln --arg queries='[{"tool":"find_usages","args":{"symbol":"OrderService"}},{"tool":"get_type_hierarchy","args":{"typeName":"OrderService"}}]'
```

**How an argument is resolved.** In this order: an explicit `--arg name=value`; the accepted alias spelling of that tool (see below; the real name always wins); for `sessionId` and `solutionPath` only, the value of `--sln`; the parameter's default; otherwise an error of the form `missing required argument '<name>': pass --arg <name>=<value>` (plus `(or --sln <path>)` for a session parameter). A `--arg` token without `=` is a user error.

**How a value is converted.** `string`, `bool`, `int`, `long`, `double`, `enum` (case-insensitive) and `string[]` (a JSON array or a comma-separated list) are read directly. Any other type is deserialized from JSON with the same options as `tools/call`, which is how a complex argument such as `batch`'s `queries` can be passed as `--arg queries='[…]'`. Numbers are read with the invariant culture: write `0.6`, not `0,6`. A decimal comma is rejected with a hint naming the cause, because on a German, French or Spanish desktop `0,6` looks perfectly well formed.

**Output and exit codes.** A string result is printed unchanged; anything else is serialized as JSON. The result goes to **stdout**, so it can be piped or inspected. Diagnostics and warnings go to **stderr** — including the progress of `analyze_solution`, which has no client to notify here and therefore reports on stderr. Exit codes: `0` success, `1` user error (unknown tool, missing or invalid argument, the tool's own actionable error), `2` unexpected failure, `3` cancelled.

An unknown tool answers `unknown tool 'X'. Available tools: …` and lists the whole assembly — which is correct here, because this verb has no curation.

Note: `aicb call` reaches **every** tool, including the writing ones, and nothing stops you from invoking `save_session` or `apply_solution_config` through it. Two practical limits apply:

- Tools that need a live solution require a successful MSBuild registration; tools that analyze a solution fail if that is unavailable, while session-less tools still run.
- Tools with a DB default need `--db-path`. Without it the telemetry sink is a null sink, so `usage_report` answers `available=false`. Missing optional paths produce `dbPath is required` in `save_session`, `compare_with_previous`, `diff_public_contract`, `apply_solution_config` and `solution_config_status`. The required `dbPath` argument of `remember_codebase`, `refresh_remembered`, `import_constellation`, `list_remembered` and `recall_codebase` is rejected earlier by the command binder as `missing required argument 'dbPath'`.

## 5.5 Parameter aliases

The server accepts a second spelling for some parameters. `tools/list` keeps advertising the **real** name only: an alias is a tolerance, not a contract change. `usage_report` counts how often an alias was applied per tool (`aliasApplied`), so the tolerance stays measurable.

| Tool | Real parameter | Also accepted |
|---|---|---|
| `find_implementations` | `interfaceName` | `symbol`, `interface` |
| `instantiation_sites` | `typeName` | `symbol` |
| `get_type_hierarchy` | `typeName` | `symbol` |
| `lifecycle_of` | `typeName` | `symbol` |
| `find_symbol` | `query` | `symbol`, `name` |
| `resolve_injection` | `interface` | `symbol`, `interfaceName` |
| `find_overrides` | `methodName` | `symbol` |
| `call_graph` | `method` | `symbol` |
| `find_by_attribute` | `attribute` | `attributeName` |
| `calls_external` | `pattern` | `apiName` |
| `export_markdown`, `prepare_task`, `pack_for_task` | `facet` | `slot` |

The real name always wins: if you pass both, the canonical argument binds and the alias is the one that is dropped. Aliases are accepted on all three binding paths — `tools/call`, a `batch`/`measure` sub-query, and `aicb call`.

Note: `analyze_solution(path)` is deliberately **not** aliased. It takes three path-shaped parameters (`solutionPath`, `layerProfile`, `dbPath`), so a bare `path` does not identify one, and a silently wrong bind would be worse than the honest failure it replaces.

## 5.6 Silently dropped arguments

The MCP SDK binds the arguments it recognizes and drops the rest without a word. aicb discloses this instead of refusing: a call that named an argument the tool does not declare succeeds, but the answer carries a notice naming the dropped arguments — up to eight of them, then `(+N more)` — and states that the answer was computed as if they had not been sent, followed by the tool's real parameter list. The notice is an HTML comment beginning `<!-- ignored-arguments:` so it is machine-readable.

In `batch` and `measure` this disclosure cannot ride on the call envelope, because the entry point only sees `{sessionId, queries}`. It therefore travels per result entry in the `note` field, and aliases are resolved first — a call that used an accepted alias is not reported as ignored.

## 5.7 Which tools write

Twelve of the 82 tools change something; **70 are read-only**. Of the twelve, two only change the in-memory session state, and ten can write to your file system or a database. No writing tool modifies source code that Roslyn reads.

| Write target | Tools | Notes |
|---|---|---|
| **Session state only** (in memory) | `analyze_solution`, `refresh_session` | Nothing on disk changes. |
| **File system, path named by the caller** | `export_markdown` | Writes the rendered Markdown only when `outputPath` is set; without it the render is returned instead. |
| **File system, inside the project directory** | `apply_solution_config`, `install_agent_hooks` | The only two tools that write into your repository: `apply_solution_config` writes the git-tracked `<SolutionName>.aicb.json` sidecar next to the `.sln` (commit it so the configuration travels with the repo); `install_agent_hooks` writes the guard script plus the harness wiring (`.claude/settings.json`, `.codex/hooks.json` or `opencode.json`) — and only inside the directory of the analyzed solution. |
| **aicb database** | `save_session`, `remember_codebase`, `refresh_remembered`, `import_constellation`, `apply_solution_config`, `solution_config_status`, `check_solution_config_drift`, `diff_review` (with `recordRegressions: true`) | The two status/drift tools ensure a solution record and can insert it when the solution is not known yet; otherwise they only read. See the `dbPath` note below. |

Every writing tool discloses its write in its own `tools/list` description. `diff_review` writes only on explicit opt-in and says so: *"Read-only unless you pass recordRegressions."*

Note: for `save_session`, `apply_solution_config` and `diff_review(recordRegressions: true)`, an omitted `dbPath` resolves to the server's **standard config DB — the same database the GUI uses**. The caller then writes into the application's live data without the call looking like it. Pass an explicit `dbPath` if that is not what you want. The memory tools are the opposite: `remember_codebase`, `refresh_remembered` and `import_constellation` require an explicit `dbPath` and never fall back to the standard config DB. When no DB is configured at all, `diff_review(recordRegressions: true)` writes nothing, still succeeds, and reports the reason in `regressionLog.skippedReason`.

## 5.8 Recurring conventions across the catalogue

So the individual tool reference does not have to repeat them, the cross-cutting rules are collected here.

### `sessionId` and self-initialization

Most tools are session-bound: their first parameter is `sessionId`, and it accepts either the session ID returned by `analyze_solution` (or by `recall_codebase`) **or** an absolute `.sln`/`.slnx`/`.slnf` path, which self-initializes the analysis once. In `batch` and `measure` the session is passed once at the top level and shared by all sub-queries. Session-less tools include `server_info`, `usage_report`, `list_skills`, `list_mcp_profiles` and `docs`. See "Sessions and staleness" for the session lifecycle.

### `scope`

Almost every fact query takes `scope`, default `"solution"`, or a **namespace prefix** such as `"MyApp.Core"` to narrow it. Two exceptions:

- `find_resource_usages` and `find_binding_usages` take a **path substring** of the markup files instead.
- `get_diagnostics` treats `scope` explicitly as a **post-filter, not a narrowing of the work**: all projects are compiled either way, so `scope` saves response tokens, not time.

### `includeTests`

The default is `false` almost everywhere — the tools report production code first. Most tools say when the filter actually removed something by returning a dedicated count:

| Field | Reported by |
|---|---|
| `testMatchesFiltered` | the `find_by_*` queries and `calls_external` |
| `testMethodsFiltered` | `find_dead_code`, `symbol_metrics` |
| `testTypesFiltered` | `find_dead_code` |
| `testImplementationsFiltered` | `find_implementations` |
| `testRegistrationsFiltered` | `resolve_injection` |

`detect_circular_dependencies` is the exception: it excludes test projects when `includeTests` is false but has no filtered-count field, so namespaces or cycles removed with the test graph are undisclosed. Another exception with a different meaning is `prepare_task(includeTests)`, whose default is `true` and which controls whether the **covering tests are bundled into the answer** — not which code is searched.

### The capped envelope

Many list answers come as `{ items, count, totalFound, truncated }`. `count` is the length of the list you received, `totalFound` the true total, and `truncated` says whether anything was cut. Typical caps:

| Cap | Where |
|---|---|
| 200 | most fact queries, semantics and markup queries, `describe_api_surface` |
| 100 | `find_symbol`, `find_usages`, `find_implementations`, `find_overrides`, `get_type_hierarchy` derived types, diff lists, `find_structural_twins`, dependency cycles |
| 50 | `symbol_signature`, `find_tests_for` |
| 20 | `impact_of_change` direct impact |
| 500 edges | `call_graph` |

### `nearest`

When a name resolves to nothing, many tools add a `nearest` suggestion — the closest declared name — instead of returning a bare empty list. That distinguishes "you misspelled it" from "this symbol really has no matches". It is present on `find_symbol`, `symbol_signature`, `find_usages`, `impact_of_change`, `symbol_metrics`, `instantiation_sites` and `resolve_injection`, and as a `hint` on `get_type_hierarchy` and `find_implementations`.

### `note`

A leading `note` field qualifies an answer that would otherwise be misread — above all the zero. The recurring pattern: a zero gets a denominator (how much was examined at all) and an explanation of which constructs the detector structurally cannot see.

### `incompleteProjects`

If the analysis run could not resolve a project's references, a `note` leads **every** answer of the fan-in family, non-empty ones included: such a run is short by ordinary edges. The cross-check is `get_diagnostics`, which reports the affected projects as `incompleteProjects` together with their suppressed-diagnostic counts and their dependent projects.

### Recall safety

Many tools state in their own description that they "work on recalled sessions" — they read persisted Roslyn facts and therefore answer on a session recalled from a database snapshot. The **live-only** tools are marked separately:

`get_diagnostics`, `check_doc_drift`, `init_solution_config`, `check_solution_config_drift`, `resolve_injection`, `evaluate_change_set`, `diff_review` (both sessions must be live), and `find_unresolved_bindings`, which runs against the live analysis and reports no findings on a recalled snapshot — and says so when the session looks recalled. `refresh_session` likewise rejects a recalled session; use `refresh_remembered` or `analyze_solution` to get a live one.

---

[&larr; 4 Profiles, pools and facets](04-profiles-pools-and-facets.md) &middot; [Contents](README.md) &middot; [6 Tool reference: orientation, sessions and symbols &rarr;](06-tool-reference-orientation-sessions-and-symbols.md)
