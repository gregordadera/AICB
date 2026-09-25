[AICB – MCP Server](README.md) &middot; chapter 8 of 12

# 8 Tool reference: facts, dead code, metrics and patterns

This chapter covers three groups of tools that ask about the analyzed model itself rather than about one symbol's neighborhood:

- deterministic fact queries — side effects, external calls, concurrency risks, resource leaks, event subscriptions, attributes, return roles, code traits, resolved semantics and provenance;
- dead code, namespace cycles and metrics;
- structural patterns and documentation drift.

All nineteen tools are read-only: none of them changes a file, a database or the session, and none of them needs a running GUI. Unless a tool says otherwise, it reads facts that were stored during the analysis, so it also works on a session you recalled from the database. All of them can be dispatched through `batch` and `measure`, as long as the active tool set exposes them.

**Shared conventions**

- `sessionId` accepts either the session id returned by `analyze_solution` or the absolute path of a `.sln`, `.slnx` or `.slnf` file. With a path, the server analyzes the solution on first use.
- `scope` is `"solution"` by default. Any other value is a namespace prefix, matched case-insensitively at a segment boundary: `MyApp.Core` matches `MyApp.Core` and `MyApp.Core.Services`, but not the sibling namespace `MyApp.CoreX`. A prefix that is too deep or misspelled simply matches nothing, and the answer then says so.
- `includeTests` is `false` by default, so test-project units are excluded. Most responses report removals in their own field (`testMatchesFiltered`, `testMethodsFiltered` or `testTypesFiltered`). `detect_circular_dependencies` is the exception: it has no filtered-count field, so cycles that disappear with the test graph are not disclosed separately.
- Capped lists come as an envelope `{ items, count, totalFound, truncated }`: `count` is the length of the delivered list, `totalFound` the true total.
- A leading `note` qualifies an answer that would otherwise be misread — above all a zero. Read it before acting on the numbers.
- Where a `kinds` parameter exists (`find_by_attribute`, `find_dead_code`, `find_production_dead`), a value other than the documented ones is treated as the full superset — never as "nothing".
- The fact queries echo the filter you passed in the response; when you passed none, the field reads `(any)`.

**Availability.** Nine of the nineteen tools in this chapter belong to the default tool set. The other ten are marked "not part of the default tool set" and need the `Full Select` profile or an `AICB_MCP_TOOLS` override:

```bash
aicb mcp --mcp-profile mcp-profile/full
```

Alternatively, expose them with the `AICB_MCP_TOOLS` environment variable (`all`, or a comma-separated list of tool-class names) before starting the server.

## 8.1 Facts about side effects, external calls, attributes and semantics

Every tool in this group reads stored Roslyn facts, so it works on a recalled session as well as on a live one. `confidence_map` and `find_by_semantics` read the resolved semantic fields; the others read the method and type facts produced by the analysis.

### `find_by_side_effects`

Finds methods by their observable side-effect profile — what they touch in the outside world. Use it to answer "what goes to the database or the network?" and "is this method pure?".

**Availability:** part of the default tool set.

| Parameter | Type | Required | Default | Meaning |
|---|---|---|---|---|
| `sessionId` | string | yes | — | The session id or a solution path. |
| `effect` | string | no | — | Filter to exactly one effect token (case-insensitive). The vocabulary is closed: any other value is rejected with an error that names the token you sent and the eight valid ones. |
| `purity` | string | no | `any` | `any`, `pure` (no detected side effect — a good refactoring and test-isolation signal) or `impure`. Any other value is rejected. |
| `scope` | string | no | `solution` | `solution` or a namespace prefix. |
| `includeTests` | boolean | no | `false` | Include test-project methods. |

The eight effect tokens:

| Token | What it asserts |
|---|---|
| `io` | Filesystem and stream access. A `System.IO` type counts on contact, not on topic: path strings (`Path`), glob matching (`FileSystemName`) and the in-memory streams and readers (`MemoryStream`, `StringReader`, `StringWriter`) carry no effect, while `File`, `Directory`, `FileStream`, `FileInfo`, `StreamReader` and `StreamWriter` do. |
| `network` | HTTP, socket, mail and cloud-storage calls. A `System.Net` type counts on contact, not on topic: addresses, cookie and header containers, credential holders, the HTTP and mail message surfaces and all of `System.Net.Mime` carry no effect, while `Dns`, `Sockets`, `WebClient`, `SmtpClient`, `HttpClient`, `HttpContent` and similar clients do. |
| `database` | Database drivers and ORMs, for example ADO.NET and `System.Data`, EF Core, Dapper, `Microsoft.Data.Sqlite`, Npgsql, MongoDB and Cosmos. |
| `serialization` | (De)serializer calls, for example `System.Text.Json`, Newtonsoft.Json, `XmlSerializer`, data contracts, MessagePack, protobuf and YamlDotNet. |
| `logging` | Logger calls, for example `Microsoft.Extensions.Logging`, Serilog, NLog and log4net. |
| `cache` | Calls into an external cache API, for example `Microsoft.Extensions.Caching`, StackExchange.Redis, EasyCaching or FusionCache. A cache a type holds in memory is not an outside-world effect and is never classified here. |
| `messaging` | Message-bus and queue clients, for example MassTransit, RabbitMQ, Azure Service Bus/Event Grid/Queues, Kafka, NATS, MediatR and Amazon SQS/SNS. |
| `unknown` | An external call that no classification rule matched — an unanalyzable third-party member, reported so the gap is visible instead of reading as pure. |

**Response.** `scope`, `note`, `effect`, `purity`, `methodsScanned`, `matches`, `availableEffects` and `testMatchesFiltered`. Each hit carries the method's `name`, `declaringType`, `namespace` and its `effects` list.

**Notes.**

- Effects are propagated transitively: a method that calls a project method which hits the database counts as `database`.
- With neither `effect` nor `purity`, only impure methods are listed — a bare "all methods" dump has no value.
- The scan set is every method plus every property, indexer and event accessor and every constructor with a body, each as a unit of its own under its metadata name (`get_X`, `set_X`, `.ctor`, `.cctor`). A field or property initializer counts toward the constructor the compiler runs it in. The `purity="pure"` list stays methods-only, because a bodied getter is pure by default and would drown it.
- On zero matches, `availableEffects` lists the tokens this scope actually records. An empty `availableEffects` means nothing was recorded in a scope that was scanned; the field is omitted when `methodsScanned` is `0`, and the note then says that nothing was scanned at all.
- `effect` together with `purity="pure"` is rejected: a pure method carries no effect, so the answer would be empty by construction.
- If the analysis run could not resolve some projects' references, a leading note warns that effects propagate along call edges, so methods can read as pure that are not. Cross-check with `get_diagnostics`.
- The list is capped at 200.

### `calls_external`

Finds the production methods that call an external (non-solution: BCL or third-party) method whose fully qualified key contains a pattern — the "who calls this external or risky API?" question that `find_usages` cannot answer, because it stays inside the solution. Typical uses: AOT and trimming readiness, security surface, external dependency footprint.

**Availability:** part of the default tool set.

| Parameter | Type | Required | Default | Meaning |
|---|---|---|---|---|
| `sessionId` | string | yes | — | The session id or a solution path. |
| `pattern` | string | yes | — | A case-insensitive substring of the external call key, for example `Process.Start`, `File.`, `Assembly.Load`, `System.Reflection` or `JsonSerializer`. `apiName` is accepted as an alias. A very broad pattern such as `System` is truncated at 200. |
| `scope` | string | no | `solution` | `solution` or a namespace prefix. |
| `includeTests` | boolean | no | `false` | Include test-project methods. |

**Response.** `scope`, `note`, `pattern`, `methodsScanned`, `matches` and `testMatchesFiltered`. Each hit reports the two kinds apart: `matchedCalls` for invocations and `matchedReads` for external property reads. An invocation executes, while a read only observes ambient state, and an AOT, testability or security verdict differs per kind.

**Notes.**

- Two stored facts back the tool: external method invocations (keys such as `System.IO.File.ReadAllText(string)`) and external property reads (such as `System.DateTime.UtcNow`). The `global::` prefix is stripped before matching and display.
- The scan set includes every property, indexer and event accessor and every constructor with a body as a unit of its own; a member initializer counts toward the constructor that runs it. An expression-bodied getter `=> DateTime.UtcNow` is therefore a read site under its own name.
- The pattern is open vocabulary: an empty result is not a misspelling and there is no suggestion field. Empty is a strong statement but not an absolute one — an external field read (`string.Empty` and other value carriers, deliberately excluded as audit-irrelevant) and a bare `new X()` are not recorded either.
- An empty answer that is only the test filter's doing says so instead of claiming nothing matched, and points you to `includeTests=true`. `testMatchesFiltered` tells you how many matching methods were dropped.
- A leading note appears on any answer, empty or not, when the analysis run failed to resolve some projects' references: an unresolved call records no external key at all, so the index is short by ordinary calls.
- The list is capped at 200.

### `find_by_concurrency_risk`

Finds methods with a concurrency or async-safety smell — a deterministic Roslyn anti-pattern that no other tool surfaces.

**Availability:** not part of the default tool set; use the `Full Select` profile or the `AICB_MCP_TOOLS` override.

| Parameter | Type | Required | Default | Meaning |
|---|---|---|---|---|
| `sessionId` | string | yes | — | The session id or a solution path. |
| `risk` | string | no | — | Filter to one token: `sync-over-async` (blocking on a task via `.Result`, `.Wait()` or `.GetAwaiter().GetResult()` — a deadlock risk), `async-void` (an `async void` method that is not an event handler — its exceptions cannot be caught and it cannot be awaited) or `fire-and-forget` (a task-returning call left as a bare statement, its result dropped — unobserved exceptions, lost work). Omit to list every method with any concurrency smell. |
| `scope` | string | no | `solution` | `solution` or a namespace prefix. |
| `includeTests` | boolean | no | `false` | Include test-project methods. |

**Response.** `scope`, `note`, `risk`, `methodsScanned`, `matches`, `availableRisks` and `testMatchesFiltered`. Each hit carries the method's `name`, `declaringType`, `namespace` and its `risks` list.

**Notes.**

- The detection is conservative and semantic: an own `Result` property on a non-task, an `async void` event handler, and an awaited, assigned or returned task are not flagged. Accessors and constructors with a body are scanned as units of their own, so a `sync-over-async` `.Result` inside a getter is found.
- The list is inherently small — most methods carry no smell. Omit `risk` to see all of them.
- Read `testMatchesFiltered` before concluding that a token is wrong: a filtered zero arrives next to an `availableRisks` list that does not contain the queried token, which reads like a misspelled token although the token was right and only its carriers were test code. A blocking `.Result` deadlocks a test run exactly as it does production code.
- On zero matches, `availableRisks` lists the tokens present in scope; an empty list means none was recorded in a scope that was scanned (the field is omitted when nothing matched the scope).
- The list is capped at 200.

### `find_by_resource_leak`

Finds methods that leak a disposable — an `IDisposable` or `IAsyncDisposable` created with `new` whose ownership is neither transferred nor released, such as an unclosed file, socket or database handle.

**Availability:** not part of the default tool set; use the `Full Select` profile or the `AICB_MCP_TOOLS` override.

| Parameter | Type | Required | Default | Meaning |
|---|---|---|---|---|
| `sessionId` | string | yes | — | The session id or a solution path. |
| `disposableType` | string | no | — | Filter to methods leaking this type (case-insensitive simple name, for example `FileStream` or `SqlConnection`). Omit to list methods leaking any disposable. |
| `scope` | string | no | `solution` | `solution` or a namespace prefix. |
| `includeTests` | boolean | no | `false` | Include test-project methods. |

**Response.** `scope`, `note`, `disposableType`, `methodsScanned`, `disposableCreationsChecked`, `disposableFactoryReturnsNotChecked`, `factoryReturnTypes`, `matches`, `availableDisposableTypes` and `testMatchesFiltered`. Each hit carries the method's `name`, `declaringType`, `namespace` and its `leakedTypes`.

**Notes.**

- Only the two unambiguous drops are reported: a bare `new X();` statement, whose result is immediately discarded, and `var x = new X();` where the local is never referenced again. Everything that transfers or keeps ownership is not flagged: a `using` statement or declaration, `return new X()`, a field or property assignment, a constructor or method argument (`new StreamReader(stream)`), a fluent `new X().Do()`, or a local that is used or disposed later.
- Constructors and accessors with a body are scanned as units of their own, so a constructor that drops a `new FileStream(...)` is found.
- `disposableCreationsChecked` is the denominator of the whole answer: the disposable creations (leaked or not) the two rules were applied to. A zero therefore reads as "0 leaks among N creations checked". **0 of 0** means nothing was looked at — either no creation in scope, or the run could not resolve the created types, because disposable-ness is a semantic verdict and an unresolved type counts in neither number. Check `get_diagnostics` for the scope.
- `disposableFactoryReturnsNotChecked` with `factoryReturnTypes` counts and names the disposables the same units obtained without `new` (a factory call or an awaited result; tasks are excluded). They are counted but not judged, because a factory does not always hand over ownership. A dropped `MSBuildWorkspace.Create()` or `Process.Start()` hides there; read those units by hand.
- On a zero with a `disposableType` filter, `availableDisposableTypes` lists the leaked types actually present in scope — read that empty filtered result as "no such leaked type in production", not as "no leaks", and use `testMatchesFiltered` to see whether the filter is the reason. On an unfiltered zero the list is empty by construction, because every leaked type would have matched; there the denominator carries the information.
- If the analysis run could not resolve some projects' references, a leading note says that both the leak list and the denominator are short by ordinary creations, and that a zero should be treated as unmeasured. A green `get_diagnostics.incompleteProjects` does not settle this: that check only asks whether core references bind, while facts degrade per assembly.
- The list is capped at 200.

### `find_by_event_subscription`

Finds the types that subscribe to a C# event — a `+=` whose left-hand side is an event — anywhere in the type: constructor, method, property accessor or lambda. Event handlers are most often wired in a constructor, and this whole-type walk captures that pattern, which a per-method view misses.

**Availability:** part of the default tool set.

| Parameter | Type | Required | Default | Meaning |
|---|---|---|---|---|
| `sessionId` | string | yes | — | The session id or a solution path. |
| `eventName` | string | no | — | Filter to types subscribing to this event. Matched by the event name (`Click`) or the qualified key `DeclaringType.EventName` (`Button.Click`), case-insensitively. Omit to list every type with any subscription. |
| `scope` | string | no | `solution` | `solution` or a namespace prefix. |
| `includeTests` | boolean | no | `false` | Include test-project types. |

**Response.** `scope`, `note`, `event`, `typesScanned`, `subscriptionSitesChecked`, `subscriptionSitesUnresolved`, `matches`, `availableEvents` and `testMatchesFiltered`. Each hit carries the subscribing type's `name`, `namespace` and the `events` it subscribes to.

**Notes.**

- Only a resolved event left-hand side counts. A `+=` on an `int`, a `string` or a delegate field (delegate combination, not an event) is skipped. This version captures subscriptions (`+=`) only.
- `subscriptionSitesChecked` is the number of `+=` sites the rule was applied to across the scanned units, and `subscriptionSitesUnresolved` how many of them had a left-hand side whose type did not resolve and were therefore not judged at all. The pair separates three different zeros: `0 of 0` (nothing to see), `0 of 7, 0 unresolved` (seven `+=` on non-events — a real absence) and `0 of 7, 7 unresolved` (an unmeasured scope). The unresolved-site case is flagged by the pair itself. A named event whose scope records no subscription at all also carries a did-you-mean note, and a scope with nothing scanned carries a separate "nothing scanned" note.
- The unresolved count is `0` on any solution whose types resolve, and it is not implied by `incompleteProjects`: that check only asks whether core references bind, so a project that resolves `System.Object` and fails on one framework or NuGet assembly loses every fact typed by it while still looking healthy. Use `get_diagnostics` to name the projects, then restore or rebuild, refresh the session and run again.
- Read `testMatchesFiltered` first when a named event comes back empty: a filtered zero arrives beside an `availableEvents` list that does not contain the queried name, which reads like a wrong name although the name was right and only its subscribers were tests.
- On zero matches, `availableEvents` lists the subscribed event keys present in scope. An empty list means no subscription was recorded in a scope that was scanned — read that as unmeasured, not as an absence, because recognition needs a resolved left-hand side.
- The list is capped at 200.

### `find_by_attribute`

Finds symbols that carry a given attribute — the cross-cutting query that a name search cannot do. Use it for `[Obsolete]`, `[ApiController]`, `[Authorize]`, test attributes and similar.

**Availability:** part of the default tool set.

| Parameter | Type | Required | Default | Meaning |
|---|---|---|---|---|
| `sessionId` | string | yes | — | The session id or a solution path. |
| `attribute` | string | yes | — | The attribute to find, for example `Obsolete`, `ApiController` or `Fact`. `attributeName` is accepted as an alias. |
| `kinds` | string | no | `all` | `all` (types + methods + properties + fields), `type`, `method`, `property` or `field`. |
| `scope` | string | no | `solution` | `solution` or a namespace prefix. |

**Response.** `scope`, `attribute`, `kinds`, `symbolsScanned` and `matches`. Each hit carries its `kind`, `name`, `declaringType`, `namespace` and the raw stored `attributes` list, so you see the ground truth.

**Notes.**

- The attribute name is matched format-independently: the last name segment, with an optional `Attribute` suffix stripped, case-insensitively. `Obsolete`, `ObsoleteAttribute` and `System.ObsoleteAttribute` all match the same symbols. This reconciles the two storage formats — types store the fully qualified attribute class, methods, properties and fields store the source syntax.
- The `method` axis includes constructors and accessors with a body (named `.ctor`, `get_X`, `set_X`), so a `[JsonConstructor]` or an `[Obsolete]` setter is found. Member scanning surfaces a member-level attribute such as a CommunityToolkit `[ObservableProperty]` on a backing field or a partial property, or a `[JsonProperty]`, which a type- and method-only scan misses.
- This tool has no test filter: it scans the whole scope, test projects included.
- An unrecognized `kinds` value behaves like `all`.
- The list is capped at 200.

### `find_by_returns_semantic`

Finds methods by their inferred return role — what kind of operation the method is, derived deterministically from its signature. Useful for naming, decomposition and test-pattern reasoning: "list all the predicates", "which methods are factories?".

**Availability:** not part of the default tool set; use the `Full Select` profile or the `AICB_MCP_TOOLS` override.

| Parameter | Type | Required | Default | Meaning |
|---|---|---|---|---|
| `sessionId` | string | yes | — | The session id or a solution path. |
| `returnsSemantic` | string | yes | — | The role to match: `command`, `query`, `predicate`, `factory`, `mapper`, `validator`, `initializer`, `handler` or `builder`. Exact match, case-insensitive. |
| `scope` | string | no | `solution` | `solution` or a namespace prefix. |
| `includeTests` | boolean | no | `false` | Include test-project methods. |

**Response.** `scope`, `note`, `returnsSemantic`, `methodsScanned`, `matches`, `availableReturnsSemantics` and `testMatchesFiltered`. Each hit carries the method's `name`, `declaringType`, `namespace` and its role.

**Notes.**

- The role is computed from the method name and return type by an ordered rule set — the first matching convention wins. A method that matches no convention carries no role and is not listed.
- This is a deterministic Roslyn fact, distinct from `find_by_semantics`, which queries the resolved role that may be asserted or heuristically guessed.
- The test filter is the reason this tool exists in its current form: `Validate*` and `Assert*` test methods would otherwise own the role list. `testMatchesFiltered` shows how many were removed.
- On zero matches, `availableReturnsSemantics` lists the roles actually present in scope, so read an empty result as "unknown role", not as "no such methods in production"; `testMatchesFiltered` tells the two apart. An empty `availableReturnsSemantics` means none was recorded in a scope that was scanned.
- The list is capped at 200.

### `find_by_code_traits`

Finds methods by a deterministic code trait — what a method's body does, computed by Roslyn and stored. Use it for hot-path and allocation reviews, AOT and trimming audits, and error-path reviews.

**Availability:** not part of the default tool set; use the `Full Select` profile or the `AICB_MCP_TOOLS` override.

| Parameter | Type | Required | Default | Meaning |
|---|---|---|---|---|
| `sessionId` | string | yes | — | The session id or a solution path. |
| `trait` | string | yes | — | One of `linq`, `linq-in-loop`, `reflection`, `throws`. Case-insensitive; any other value is rejected. |
| `scope` | string | no | `solution` | `solution` or a namespace prefix. |
| `includeTests` | boolean | no | `false` | Include test-project methods. |

What each trait means:

| Trait | Meaning |
|---|---|
| `linq` | Uses LINQ operators — relevant for hot-path and allocation review. |
| `linq-in-loop` | A real `System.Linq` operator evaluated inside a loop body — a per-iteration allocation and complexity smell. This is a strict subset of `linq`. |
| `reflection` | An external call or read whose receiver type is reflection infrastructure: `System.Reflection.*`, `Type.*`, `Activator`, `AppDomain`, `object.GetType()` or expression trees. Matched on the receiver, never on a bare member name, so a WPF `DependencyObject.GetValue`/`SetValue` accessor or a `typeof(...)` in an attribute or dependency-property registration does not count. |
| `throws` | Contains a `throw` statement — relevant for error-path review. |

**Response.** `scope`, `note`, `trait`, `methodsScanned`, `matches` and `testMatchesFiltered`. Each hit carries the method's `name`, `declaringType` and `namespace`.

**Notes.**

- Two traits are deliberately not offered: `isAsync` is already visible in the signature, and I/O is covered by `find_by_side_effects` with the `io` token.
- This axis has no suggestion list, so `testMatchesFiltered` is the only thing that separates "no such methods in the scanned set" from "no such methods". Check it before concluding anything.
- `reflection` and `linq-in-loop` exist only where a call target resolved. In a project with unresolved references they are false for every method there. Such a run leads the answer with a note naming the unresolved projects — cross-check with `get_diagnostics.incompleteProjects`.
- Accessors and constructors with a body are scanned as units of their own (`get_X`, `set_X`, `.ctor`).
- The list is capped at 200.

### `find_by_semantics`

Finds symbols whose resolved semantics match the given criteria. All provided filters must match (logical AND). Use it to find, for example, all domain services, all view models, or everything whose responsibility mentions a keyword.

**Availability:** part of the default tool set.

| Parameter | Type | Required | Default | Meaning |
|---|---|---|---|---|
| `sessionId` | string | yes | — | The session id or a solution path. |
| `layer` | string | no | — | Match the resolved layer exactly (whole value, case-insensitive): `Domain`, `Application`, `Infrastructure`, `Presentation` or `Contracts`. |
| `role` | string | no | — | Match the resolved role exactly. Inferred type roles: `Service`, `Helper`, `Model`, `Record`, `Interface`, `Enum`, `Builder`, `ViewModel`, `Converter`, `Controller`, `Middleware`, `Attribute`, `Exception`, `EntryPoint`, `ContractModel`, `Type`. There is no `Repository` role — repositories classify as `Service`. Methods carry a method-category role, for example `Query`, `Command`, `Mapping`, `Validation` or `Orchestration`. |
| `domain` | string | no | — | Free text, matched as a case-insensitive substring of the resolved domain (derived from naming and namespace). |
| `responsibility` | string | no | — | Free text, matched as a substring. Types only — methods have no such axis. |
| `minConfidence` | string | no | `any` | `any` (includes guessed values) or `asserted` (only `fact` and `ai`). Any other value is rejected. |

At least one filter is required.

**Response.** `criteria`, `note`, `minConfidence`, `matches`, `availableAxisValues` and `nearMisses`.

- `criteria` echoes the applied filters and their mode: `role=View` for an exact closed-vocabulary match, `domain~order` for a substring match.
- Each hit carries the symbol's `kind`, `name`, `declaringType`, `namespace` and, per matched axis, the matched value together with its provenance: `fact`, `ai` or `inferred`.
- `nearMisses` appears whenever a closed axis (`role`, `layer`) was queried and some present value contains the query without being it. Each entry names the value and how many symbols carry it. These values are counted apart and named in a leading note, never listed as matches.

**Notes.**

- The difference between exact and substring matching is the point of this tool: `role="View"` is one view, not every view model.
- On zero matches, `availableAxisValues` lists the values actually present in this solution for each queried axis — read an empty result as "unknown value", not as "no such symbols".
- Asserted values can differ from the inferred defaults and keep their own spelling, for example `viewmodel` next to the inferred `ViewModel`. The case-insensitive match folds `viewmodel` into `ViewModel`; hyphenated refinements stay apart and show up as near misses.
- The list is capped at 200.

### `confidence_map`

Reports the provenance of each semantic field of a symbol or a scope: is the value a deterministic Roslyn truth, a developer assertion, a heuristic guess, or explicitly declared absent? Use it to know what is known and what is guessed before you trust a symbol's role, layer or domain.

**Availability:** not part of the default tool set; use the `Full Select` profile or the `AICB_MCP_TOOLS` override.

| Parameter | Type | Required | Default | Meaning |
|---|---|---|---|---|
| `sessionId` | string | yes | — | The session id or a solution path. |
| `symbol` | string | no | — | An exact, case-sensitive type or method name for one symbol. Omit to map a whole scope. |
| `scope` | string | no | `solution` | When `symbol` is omitted: `solution` maps every symbol, or a namespace prefix narrows it. Ignored when `symbol` is given. |
| `summaryOnly` | boolean | no | `false` | Return only the solution-wide tally, without the per-symbol entries. Use it on a large solution where the full per-symbol map would exceed the token limit. |

**Response.** `note`, `scope`, `entries` and `tally`. The scope echoes `symbol` when you queried one symbol.

- Each entry carries the symbol's `kind`, `name`, `declaringType`, `namespace`, its `fields` (each field with its provenance token) and the per-token counts `factCount`, `aiCount`, `inferredCount` and `verifiedAbsentCount`.
- The four provenance tokens are: `fact` (deterministic Roslyn truth), `ai` (developer-asserted via an `<ai>` annotation), `inferred` (heuristic guess, low confidence) and `verified-absent` (the developer explicitly declared "none").
- `tally` aggregates over the scanned scope: the four token counts (summed over fields), `symbolsScanned` and `symbolsWithoutProvenance`.

**Notes.**

- The axes recorded per symbol include role, layer, context, domain and responsibility, among others; the map reports whatever is recorded.
- On a codebase with no `<ai>` annotations at all (fact, ai and verified-absent all zero — the normal state of a foreign codebase), a solution-scope answer leads with a note saying that every value is heuristically inferred, because the known-versus-guessed distinction does not exist there. A narrowed or per-symbol map is scope-filtered and cannot carry that codebase-wide claim.
- `summaryOnly=true` omits the per-symbol entries; the entries envelope still reports the true total and `truncated`.
- The entries are capped at 200.
- Works on a recalled session; provenance is stored.

## 8.2 Dead code, cycles and metrics

### `find_dead_code`

Lists dead-code suspects as a queryable list, where the quality insights only give a top-20 aggregate.

**Availability:** part of the default tool set.

| Parameter | Type | Required | Default | Meaning |
|---|---|---|---|---|
| `sessionId` | string | yes | — | The session id or a solution path. |
| `scope` | string | no | `solution` | `solution` or a namespace prefix. |
| `includeTests` | boolean | no | `false` | Include test-project methods and types. |
| `kinds` | string | no | `method` | `method` — private methods with no detected caller; `type` — types with no incoming reference in the reliable reverse type fan-in; `all` — both. |

**Response.** `scope`, `note`, `methodsScanned`, `deadMethods`, `typesScanned`, `deadTypes`, `methodsIneligible`, `typesIneligible`, `typesUnexamined`, `testMethodsFiltered`, `testTypesFiltered`, `methodsIneligibleNotPrivate`, `methodsIneligibleUnanalyzedCallers`, `typesIneligibleStructural`, `typesIneligibleTestScaffolding`, `typesIneligibleFrameworkActivated` and `typesIneligibleMarkupReferenced`. Each dead method carries `name`, `declaringType` and `namespace`; each dead type carries `name`, `kind`, `accessibility` and `namespace`. Each axis is capped at 200.

**Notes.**

- The method axis is deliberately limited to private methods: public and internal methods have framework escapes — reflection, dependency injection, event handlers, source-generated callers — that the call graph cannot see. A method whose caller list was not analyzed is skipped, not guessed. A markup-only caller counts as a real caller, so for example a Blazor `@onclick` handler is not reported.
- The type axis subtracts the structurally fan-in-invisible forms: interfaces, static and `*Extensions` classes, framework-, DI- and reflection-activated types, WPF/XAML types and MVC controllers.
- An answer that lists candidates leads with a note saying what the zero behind each candidate does not prove, and how to confirm one before deleting it.
- An empty answer is qualified only when the absence was structurally guaranteed. `methodsIneligible` counts scanned units the predicate could never judge and is split into `methodsIneligibleNotPrivate` (the deliberate policy) and `methodsIneligibleUnanalyzedCallers` (private methods with no analyzed caller list — the blind spot this axis exists to find). `typesIneligible` is split into four exemption families: `typesIneligibleStructural`, `typesIneligibleTestScaffolding`, `typesIneligibleFrameworkActivated` and `typesIneligibleMarkupReferenced`.
- If none of the scanned units was eligible — an abstractions namespace consists only of interfaces, for example — the note says that the scope could not have produced a candidate, so a bare "0 dead" is never read as an all-clear.
- When the default method axis ran alone and found nothing, the note reports how many types in the scope the type axis would have judged and did not; the field `typesUnexamined` carries that count. A zero over an eligible population that still skipped some private methods as unanalyzed is qualified the same way.
- `testMethodsFiltered` and `testTypesFiltered` report candidates the default test filter removed, so a zero that is the filter's does not read like a zero that is the code's.
- Works on a recalled session.

### `find_production_dead`

Finds production-dead symbols — public or internal types and methods that are used, but only by tests. This is the feature you built and tested but never wired into production. It is exactly what `find_dead_code` misses, because a symbol with test callers has a fan-in greater than zero.

**Availability:** not part of the default tool set; use the `Full Select` profile or the `AICB_MCP_TOOLS` override.

| Parameter | Type | Required | Default | Meaning |
|---|---|---|---|---|
| `sessionId` | string | yes | — | The session id or a solution path. |
| `scope` | string | no | `solution` | `solution` or a namespace prefix. |
| `kinds` | string | no | `all` | `all` (methods + types), `method` or `type`. |

**Response.** `scope`, `note`, `methodsScanned`, `candidatesWithoutAnyCaller`, `deadMethods`, `typesScanned`, `deadTypes`, `methodsIneligible` and `typesIneligible`. Each method carries `name`, `declaringType`, `namespace` and `testCallerCount`; each type carries `name`, `kind`, `accessibility`, `namespace` and `testReferenceCount`. Each axis is capped at 200.

**Notes.**

- The predicate is: direct callers exist, and the production impact is zero — the same production fan-in that `impact_of_change` reports. The test callers prove that the symbol is real and reachable rather than reflection-only noise; the production zero flags it as unwired.
- Methods are judged over their dispatch family: the method itself plus the same-named members of its declaring type's ancestry (base chain and interfaces, transitively). A call bound to `IFoo.Bar` records its edge on `IFoo.Bar`, so an interface member's production callers are seen and a concrete implementation is not a false positive, while a same-named method on an unrelated type neither lends evidence nor suppresses it. Where an interface has several implementers, the count can include tests that ran against a different one.
- Dispatch and framework escapes are exempt: virtual, override and abstract members; well-known interface members such as `Dispose` or `Equals`; `On*` event handlers; `[RelayCommand]` and serialization-callback attributes; and whole XAML, test-scaffolding and framework-host types. Types use the same exemption taxonomy as `find_dead_code`.
- Test-project symbols are the callers that matter here, never candidates themselves: a test method is not production-dead.
- `candidatesWithoutAnyCaller` counts public or internal methods dropped because they have no caller anywhere in their dispatch family. Nothing proves them real, so they are not production-dead — but `find_dead_code` will not show them either, because its method axis is private-only. This number is the only sign that this class exists.
- The tool errs toward under-reporting: a symbol reached only via reflection, dependency injection or a source generator that static analysis cannot see is exempt. What a flag establishes with high confidence is the test usage; the production zero beside it is recorded, not proven, and the answer's own note says so. An empty result is not proof either.
- An empty answer is qualified only when it was structurally guaranteed: a scope that matched nothing says so instead of posing as clean, and a scope where no scanned unit was eligible reports "not judged here" with the ineligible counts.
- Works on a recalled session.

### `find_god_objects`

Finds "god object" candidate classes — a class with too many members, a Single Responsibility Principle smell and a prime refactoring target. It is the queryable, scoped, member-count-ranked twin of the `quality-large-classes` quality finding, and it returns the per-class member breakdown so the split is actionable.

**Availability:** not part of the default tool set; use the `Full Select` profile or the `AICB_MCP_TOOLS` override.

| Parameter | Type | Required | Default | Meaning |
|---|---|---|---|---|
| `sessionId` | string | yes | — | The session id or a solution path. |
| `minMembers` | integer | no | `25` | The member-count floor: only classes with at least this many members are listed. Values below 1 are raised to 1. Raise it, for example to 40, for only the worst offenders; lower it to explore. |
| `scope` | string | no | `solution` | `solution` or a namespace prefix. |
| `includeTests` | boolean | no | `false` | Include test-project types. |

**Response.** `scope`, `minMembers`, `classesScanned`, `matches` and `testMatchesFiltered`. Each match carries `name`, `namespace`, the total `members` and the breakdown `methods`, `properties` and `fields`. Ranked by member count descending, capped at 200.

**Notes.**

- Only classes are considered; records, structs and interfaces are excluded, as in the quality finding.
- The member count is the class's declared methods plus properties plus fields. Constructors, operators and source-generated properties are deliberately not counted.
- The floor is inclusive: a class with exactly `minMembers` members is listed.
- On a ranked answer, a non-zero `testMatchesFiltered` is a warning about the top of the list, not only about its length: the filter can remove the largest class of all while the remaining list still looks complete.
- Works on a recalled session.

### `symbol_metrics`

Queries per-method complexity directly, or ranks the complexity hotspots. Both metrics are always returned: McCabe cyclomatic complexity (the number of independent paths) and SonarSource-style cognitive complexity (how hard the method is to understand: a nesting penalty, `else` and `catch` counted, boolean-operator runs collapsed).

**Availability:** part of the default tool set.

| Parameter | Type | Required | Default | Meaning |
|---|---|---|---|---|
| `sessionId` | string | yes | — | The session id or a solution path. |
| `symbol` | string | no | — | An exact, case-sensitive method name, bare (every same-named method) or qualified as `Type.Member` (that type's member only). Omit to rank all methods by complexity. |
| `minComplexity` | integer | no | `0` | When ranking: include only methods whose ranking complexity is at least this value. `0` means no filter. |
| `scope` | string | no | `solution` | When ranking: `solution` or a namespace prefix. Ignored when `symbol` is given. |
| `includeTests` | boolean | no | `false` | When ranking: include test-project methods. Ignored in the by-name lookup. |
| `rankByCognitive` | boolean | no | `false` | When ranking: sort and filter by cognitive complexity instead of cyclomatic complexity. Both numbers are always present per method; this only changes the axis. Ignored in the by-name lookup. |

**Response.** `scope`, `mode` (`symbol` or `ranked`), `note`, `minComplexity`, `minComplexityBoundary`, `methodsScanned`, `methods`, `nearest` and `testMethodsFiltered`. Each method entry carries `name`, `declaringType`, `namespace`, `cyclomaticComplexity`, `cognitiveComplexity` and `parameterCount`. Capped at 200 — the top entries when ranking.

**Notes.**

- The complexity floor is inclusive: a method whose ranking complexity is exactly `minComplexity` is listed, and a filtered answer states that in `minComplexityBoundary`. `solution_metrics` counts methods over its threshold strictly, so at the same number its count is smaller by exactly these boundary methods.
- The by-name lookup is never filtered by tests or by the floor, and it also resolves a user-defined operator, an accessor or a constructor by its metadata name (`op_Equality`, `get_Items`, `.ctor` — the last unions every constructor in the solution). The ranked hotspot view stays methods-only.
- A by-name lookup that matches no method carries a `nearest` suggestion, the closest declared name. If the exact name resolves to a declared type rather than a method, the note says so and points to `find_symbol` or `symbol_signature`. An empty ranking never steers: nothing above the complexity floor is a measurement, not a typo.
- `testMethodsFiltered` counts the test-project methods the filter removed; it is counted over the removed population, which `methodsScanned` does not include, so it can exceed that number. When the strongest filtered method would have landed inside the shown ranks, a note names it and the rank it would hold — a count alone cannot tell you whether the missing entries sat at the bottom or at the top.
- When the two complexity axes would deliver different sets of methods, a leading note names the axis that ordered this list and the methods the other axis would have shown. The note stays silent when they agree.
- Works on a recalled session. A session recorded before cognitive complexity existed reports `0` for it.

### `solution_metrics`

Returns the solution-wide quality rollup in one call — the same numbers that the `--fail-on` quality gate evaluates.

**Availability:** part of the default tool set.

| Parameter | Type | Required | Default | Meaning |
|---|---|---|---|---|
| `sessionId` | string | yes | — | The session id or a solution path. |
| `failOn` | string | no | — | A gate expression in `--fail-on` syntax, for example `critical>0 OR debt>120min OR ce-max>50`. An invalid expression or an unknown metric is rejected with the list of valid tokens. |
| `dbPath` | string | no | — | Path to an AIContextBuilder database. When set, the complexity threshold and the producer switches come from that database's active quality profile. Omit to use the server's default configuration database. |

**Response.** `metrics`, `scope`, `testMethodCount`, `testTypeCount`, `severities`, `debtMinutes`, `debtRating`, `complexityThreshold`, `complexityThresholdBoundary`, `qualityProfile`, `layerProfile`, `knownGateMetrics`, `gate` and `degradedProducers`.

- `metrics` carries `typeCount` and `methodCount` (logical types — partial fragments merged, multi-targeted projects deduplicated), `complexityMax` and `complexityAvg`, `methodsOverComplexityThreshold`, `ceMax` and `caMax` (efferent and afferent coupling maxima).
- `severities` counts the quality findings by `critical`, `warning`, `info` and `ok`; `debtMinutes` and `debtRating` are the technical-debt estimate, the rating a coarse letter from `A` (very low) to `E` (high).
- `complexityThresholdBoundary` states the boundary with the concrete numbers: `methodsOverComplexityThreshold` counts methods strictly above the threshold, while `symbol_metrics(minComplexity=…)` and the complex-untested finding use an inclusive floor.
- `knownGateMetrics` lists the valid metric tokens: `critical`, `warning`, `info`, `ok`, `debt`, `complexity-max`, `ce-max`, `ca-max`, `methods` and `types`.
- `gate` echoes the expression, `passed` and the `violatedClauses` when you passed `failOn`. It is advisory; the blocking gate remains the CLI.
- `degradedProducers` appears only when a producer failed during the run, in which case the severity counts and the debt figure are incomplete.
- `qualityProfile` and `layerProfile` disclose which profiles produced the numbers.

**Notes.**

- The scope is production code only, matching the CLI gate: test projects are excluded from every number. The response says so itself with `scope: "production"`, and `testMethodCount` and `testTypeCount` carry the excluded test-side tallies in the same units — `methodCount` plus `testMethodCount` is the full solution's method-unit count.
- The rollup is deliberately not triage-filtered: insight suppressions apply to the reading surfaces (`list_insights` and `get_insight`), while this rollup and the CLI gate keep counting every finding. On a triaged solution these severity counts are therefore higher than what `list_insights` returns, and that gap is the suppression set.
- Works on a recalled session. The line-based debt and long-method producers degrade the same way as the CLI gate on a recalled snapshot; the metric rollup itself is stable.

### `detect_circular_dependencies`

Detects circular namespace dependencies — groups of namespaces that depend on each other in a cycle. This is a modularity smell that the C# compiler allows, unlike project-reference cycles, which it forbids. It complements layer-violation analysis with the orthogonal question of who is mutually entangled.

**Availability:** part of the default tool set.

| Parameter | Type | Required | Default | Meaning |
|---|---|---|---|---|
| `sessionId` | string | yes | — | The session id or a solution path. |
| `scope` | string | no | `solution` | `solution` reports every cycle; a namespace prefix narrows the report to cycles that touch it. The analyzed graph stays the whole solution, so `namespacesScanned` does not change. |
| `includeTests` | boolean | no | `false` | Include test projects. Off by default, because a test-to-production reference is one-way and not an architecture cycle. |

**Response.** `scope`, `namespacesScanned`, `cyclesFound` and `cycles`. Each cycle lists the participating `namespaces`, its `size`, the `projects` in which they are declared, `edgeCount` and the witness `edges`. Each witness carries `fromNamespace`, `toNamespace`, `fromType`, `toType` and `typeEdgeCount`, and the cycle carries `spansMultipleProjects`.

**Notes.**

- Each reported cycle is a strongly connected component of at least two namespaces, listing the participating namespaces plus witness type-to-type edges, one per directed namespace pair, that show why each link exists.
- Read the witnesses as examples, not as a work list: `edgeCount` counts directed namespace pairs, and each witness carries `typeEdgeCount` — how many distinct type-to-type references cross that one boundary. Where `typeEdgeCount` is 1, the example is the inventory; where it is higher, breaking the shown reference leaves the namespace edge standing and the next reference surfaces.
- A cycle inside one assembly is pure namespace organization and can be refactored freely. A cycle that spans assemblies means a namespace is reused across assembly boundaries — a different and often more telling situation, since project-reference cycles are compiler-forbidden.
- Namespace edges are derived from fully qualified facts, so a same-named type in two namespaces is never conflated, and external references are ignored. Only cycles inside the solution are reported.
- A clean, well-layered codebase returns zero cycles. That empty result is itself a useful signal.
- Cycles are capped at 100; assembly-spanning cycles come first, then the largest tangles. Each cycle's namespace list stays complete; only the witness edges are capped.
- Works on a recalled session.

## 8.3 Patterns and documentation drift

### `find_structural_twins`

Finds symbols with the same structure as a type or method — the siblings a text search cannot see. Use it before editing one member of a family to find the others you must keep consistent.

**Availability:** not part of the default tool set; use the `Full Select` profile or the `AICB_MCP_TOOLS` override.

| Parameter | Type | Required | Default | Meaning |
|---|---|---|---|---|
| `sessionId` | string | yes | — | The session id or a solution path. |
| `symbol` | string | yes | — | The exact, case-sensitive type or method name to find twins of. |
| `minSimilarity` | number | no | `0.8` | Minimum structural similarity, from 0 to 1. Higher is stricter; about 0.9 is near-identical, 0.6 widens the net, and 0.7 floods on a large codebase. Values outside 0 to 1 are clamped, and the answer says so. |

**Response.** `symbol`, `resolvedKind`, `minSimilarity`, `twins` and `note`. Each twin carries its `name`, a 0 to 1 `similarity` score, the `sharedDimensions` and `divergingDimensions`, its `namespace` and — on the method axis — the `declaringType` it is declared on. Capped at 100.

**Notes.**

- The comparison uses the declared shape, not what the bodies do: two methods with the same signature score high even when their implementations are unrelated.
- Both axes need a structural anchor. A type needs a base class or a non-ubiquitous interface; a method needs at least one modifier or a parameter of a non-ubiquitous type — `string`, the primitives, `object`, collection heads and `CancellationToken` are too common to mark a family. Without an anchor the signature collapses onto ubiquitous dimensions, where every base-less record or every parameterless `private void X()` would score 1.0. Such a seed returns no twins plus a note; that note means "structurally generic", not "no twins exist".
- Candidates above the threshold that share only the ubiquitous skeleton and carry no matching distinctive signal are suppressed as noise. The note reports how many out of how many — `totalFound` is the count after suppression, so do not subtract the two. Lowering `minSimilarity` will not turn suppressed candidates into twins.
- The seed is resolved by bare name, and there is no qualified `Type.Member` form. When the name has several declarations (partial fragments count once), the answer describes the first in enumeration order and the note says so, naming the other owners where they differ. Overloads on one type share an owner, so the note then states the count alone; use `symbol_signature` to see each declaration with its file.
- Test-project symbols are excluded from the candidates: structural twins are a production concern.
- If `minSimilarity` was outside 0 to 1, the note names the value you sent and the value that was used, and states that the whole answer describes the clamped threshold. A decimal comma is the usual cause on a non-English desktop.
- Works on a recalled session.

### `check_pattern_drift`

Given a set of symbols that should follow the same pattern — for example all your panel view models — computes the consensus shape and pinpoints which member deviates and in what dimension.

**Availability:** not part of the default tool set; use the `Full Select` profile or the `AICB_MCP_TOOLS` override.

| Parameter | Type | Required | Default | Meaning |
|---|---|---|---|---|
| `sessionId` | string | yes | — | The session id or a solution path. |
| `symbols` | array of strings | yes | — | The type or method names that should share a pattern. Two are the minimum, three or more give a real consensus. Unknown names are reported, never silently dropped. |

**Response.** `consensusKind`, `memberCount`, `conformingCount`, `consensusScalars`, `consensusSets`, `deviations` and `noConsensusScalars`.

- `consensusKind` is the majority kind (`type` or `method`), or `not_found` when none of the names resolved.
- `consensusScalars` and `consensusSets` are the published consensus shape: scalar dimensions with their shared value, set dimensions with their shared elements.
- `deviations` lists the members that differ from the consensus; each entry carries the `member`, its `resolvedKind` and the `deviations` as human-readable dimension lines. A member of the minority kind is flagged as a kind deviation, and an unresolved name is reported with `not_found`.
- `noConsensusScalars` lists scalar dimensions that were deliberately left out because no single value reached a majority, each with its observed distribution.

**Notes.**

- Consensus means majority: a dimension is published only when one value (scalar) or one element (set) is held by more than half of the members. A scalar on which the members merely disagree — three types in three different size buckets, say — is not published on a plurality or a tie. It is listed in `noConsensusScalars` instead, because reporting members against a shape none of them holds would manufacture the deviations this tool is asked to find.
- Read `noConsensusScalars` before `conformingCount`: "all conform" plus a dropped dimension means "they agree on the rest and share nothing there", not "they follow one pattern".
- A dimension that no member carries at all is passed over in silence rather than reported as a no-majority finding.
- Works on a recalled session.

### `check_doc_drift`

Finds documentation drift — XML documentation comments that no longer match a method's actual signature.

**Availability:** not part of the default tool set; use the `Full Select` profile or the `AICB_MCP_TOOLS` override.

| Parameter | Type | Required | Default | Meaning |
|---|---|---|---|---|
| `sessionId` | string | yes | — | The session id or a solution path. |
| `scope` | string | no | `solution` | `solution` or a namespace prefix. |

**Response.** `scope`, `methodsScanned`, `methodsWithDocTags` and `findings`. Each finding carries the method's `name`, `declaringType`, `namespace`, its check `kind` and a human-readable `detail`. Capped at 200.

**Notes.**

- Two reliable, low-false-positive checks are performed. `param-not-found`: a `<param name="x">` whose name is not an actual parameter — a renamed or removed parameter, or a typo in the documentation. `return-on-void`: a `<returns>` on a method that returns `void`.
- A `<returns>` on `Task`, `Task<T>`, `ValueTask` or any other value-returning method is correctly not flagged: documenting the returned task is a standard convention, not drift.
- `methodsWithDocTags` counts the methods that carry a `<param>` or `<returns>` tag at all — the drift-checkable ones, not the summary-documented ones. Methods without such tags are skipped; there is nothing to check.
- Live only: this tool reads documentation facts that are not stored with a session, so it needs a live analysis. A recalled session is rejected with a pointer to refresh it.

---

[&larr; 7 Tool reference: impact, hierarchy, tests and DI](07-tool-reference-impact-hierarchy-tests-and-di.md) &middot; [Contents](README.md) &middot; [9 Tool reference: markup, export, review and insights &rarr;](09-tool-reference-markup-export-review-and-insights.md)
