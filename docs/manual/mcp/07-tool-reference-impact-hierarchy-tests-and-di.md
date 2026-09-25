[AICB – MCP Server](README.md) &middot; chapter 7 of 12

# 7 Tool reference: impact, hierarchy, tests and DI

The tools in this chapter answer four groups of questions:

- **Impact and fan-in** – who uses a symbol, how far a change propagates, which call or dependency path connects two symbols, and who constructs a type.
- **Hierarchy and lifecycle** – who implements an interface, who overrides a method, how a type's inheritance tree looks, and how a type is created, injected, returned, referenced and persisted across the solution.
- **Tests and coverage** – which tests cover a symbol, which methods no test calls directly, which complex methods are untested, and whether a negative claim about a symbol holds.
- **Dependency injection** – which concrete type is registered for an interface, with which lifetime, and where.

## 7.1 Conventions used in this chapter

- **Session.** Every tool takes a `sessionId`. Most tools also accept the absolute path to a `.sln` file directly and analyze it on first use. A tool answer is computed from the analyzed session, so after you edit source files call `refresh_session` before asking again – otherwise the symbol graph keeps answering from the pre-edit state. See "Sessions and staleness".
- **Read-only.** All tools in this chapter only read the analyzed model. None of them changes source files, the session, or any database.
- **Recalled sessions.** All tools in this chapter work on a session restored from a saved snapshot, except `resolve_injection`, which needs a live analyzed session.
- **`note`.** Where a response carries a `note`, read it before the numbers. It leads the answer when the answer needs a qualification – an empty result that is not proof of absence, a run whose project references did not all resolve, or a zero that is not a measurement. Notes are omitted when there is nothing to say.
- **Caps.** Capped lists report the true total in `totalFound` and set `truncated` to `true`. Narrow the query or the `scope` to see the rest.
- **Availability.** Each tool below carries an availability line. "Core" tools are part of every tool set. "Default" tools are part of the default tool set. A tool marked "not in the default tool set" is still shipped, but you reach it only when the server runs with an MCP profile whose facet menu includes it (for example the Exploration, Debugging or Architecture facet), or when you add its name through the `AICB_MCP_TOOLS` environment variable.
- **Parameter aliases.** Some tools accept a familiar alternative spelling for their main argument, listed in the parameter tables as an alias. The canonical name is always advertised; the alias is only tolerated so a call that used the other name still binds.

## 7.2 Fan-in, impact and paths

### `find_usages`

**Purpose.** List who uses a symbol – the fan-in. This is the central "who calls X?" tool and the first call for almost every impact question.

**When to use it.** Before renaming, moving or deleting a symbol; when you need the concrete list of callers, readers, writers or subscribers; when you want to know whether a type is referenced at all.

**Availability.** Core tool set.

**Parameters**

| Parameter | Type | Required | Default | Meaning |
|---|---|---|---|---|
| `sessionId` | string | yes | – | Session id returned by `analyze_solution`, or an absolute `.sln` path for self-init. |
| `symbol` | string | yes | – | Exact (case-sensitive) name of a type, method, property, field, event or enum member – or the qualified `Type.Member` form to disambiguate a member. `Type.Type` asks for a type's constructor. |

**What a name resolves to**

| Query | `resolvedKind` | Answer |
|---|---|---|
| Type name | `type` | The types that reference it. |
| Method name | `method` | The methods that call it (the union across overloads). |
| Property or field name | `property` / `field` | The methods that read or write it. A CommunityToolkit `[ObservableProperty]` backing field additionally lists the consumers of its generated property – the two are one symbol pair to a caller. |
| Event name | `event` | The methods that raise, subscribe to or unsubscribe from it. The subscriber types are also available through `find_by_event_subscription`. |
| Enum member (bare `Partial` or qualified `BackupStatus.Partial`) | `enum_member` | The methods that reference it – a switch label, a comparison, an assignment. |
| `Type.Type` | `constructor` | The type's construction and injection sites. This analyzer records no per-constructor fan-in, so overloads are unioned and a listed site may have called a different overload than you meant; `instantiation_sites` reports the same facts with the two edge kinds kept apart. `impact_of_change` does not resolve this form. |

**Example**

```json
{ "sessionId": "<session>", "symbol": "OrderService.Cancel" }
```

**Response.** `symbol`, `resolvedKind`, an optional `note`, and `usedBy` – a capped envelope (`items`, `count`, `totalFound`, `truncated`, maximum 100). Depending on the answer, additional steering fields appear:

- `nearest` – the closest declared name, set when the query matched nothing (`resolvedKind: "not_found"`). A likely typo or case mismatch.
- `collision` – set when a bare name resolved to a member while a same-named type also exists.
- `namesakes` – set when the name resolved to a type that the solution declares several times. `usedBy` is then the union over all of them, and no entry says which one it uses.
- `textuallyInvisibleUsers`, `textualBindingKinds`, `textualBindingNote` – see below.

**Empty answers.** A real kind with an empty `usedBy` means the symbol exists but no intra-solution reference was recorded. That is not proof of dead code, and the `note` that leads the answer names the ways a real use can escape the index and a cross-check you can run:

- **Markup:** `{Binding}` root paths in both markup-extension and element syntax (low-confidence, tagged `(xaml)`, attributed to the resolved view-model), `Click="Handler"` event wires, `{x:Static}` members, attached-property read accessors, `{TemplateBinding}` members and markup type references. A view-model reached only through a `d:DesignInstance` design hint or the `FooView` → `FooViewModel` naming convention records its member edges but not its type edge, so a view-model rename can still read as low-risk.
- **C# `nameof`** of a method (a `nameof` of a type is recorded).
- **Activation by name at runtime:** reflection, a container resolving by convention.
- **Source-generated code:** generated documents are not walked, so a generator's output records no edge on what it calls.
- **Enum members only:** values that arrive as strings or numbers (`Enum.Parse`/`TryParse`, JSON or database deserialization, a XAML attribute literal, a command-line argument) and attribute arguments on a type, property or field.
- **Events only:** a subscription made through an interface lands on the interface's event, not the class's (the bare name unions both); a handler added by name (`WeakEventManager.AddHandler(src, nameof(E), …)`, reflection `AddEventHandler`) or wired in markup leaves no edge.

The cross-checks the note suggests: for a member, run the fan-in query on its declaring type (a type's fan-in is recorded where its member's is not); for a type, ask `instantiation_sites`, which reads different facts (construction and injection edges); for either, search the name in `.xaml`, `.csproj` or `.json`, or read the source.

**Textually invisible users.** When the answer has entries that bind to the symbol without naming it anywhere in their own source – a value consumed from a member that returns the type, or a call that omits an optional parameter of the type – the response reports the count in `textuallyInvisibleUsers` and splits it in `textualBindingKinds`:

| Kind | Meaning | Breaks when |
|---|---|---|
| Via return type | Consumes a value of the type from a member that returns it. | The type's contract changes (a member is renamed or removed); survives a type rename. |
| Via optional parameter | Calls a method that takes the type as an optional parameter and omits the argument. | Only when that method's signature changes; survives a rename and a contract change. |
| Unclassified | Binds by a mechanism this check does not recognize. | Inspect by hand. |

`textualBindingNote` states the same in one sentence. Only a count is reported, not a per-entry flag.

**Limits.** Matching is case-sensitive. The list is capped at 100. A member name resolves by simple name across all types unless you use the qualified `Type.Member` form.

**Run-wide qualification.** If the analysis run could not resolve every project's references, a `note` leads every answer of this family – including a populated one – because such a run is short by ordinary references, not only exotic ones. Rebuild and call `refresh_session`, then repeat the query.

### `impact_of_change`

**Purpose.** Estimate the blast radius of changing a symbol: the direct and the transitive fan-in (who depends on it, directly or through chains) plus a risk level. This is the call to make before you refactor or rename shared code.

**When to use it.** Before an edit that changes a symbol other code names – a rename included. The trigger is the symbol's reach, not the kind of edit.

**Availability.** Core tool set.

**Parameters**

| Parameter | Type | Required | Default | Meaning |
|---|---|---|---|---|
| `sessionId` | string | yes | – | Session id, or an absolute `.sln` path for self-init. |
| `symbol` | string | yes | – | The same strings `find_usages` accepts. A type takes its simple name only. |

**Response.** `symbol`, `resolvedKind`, an optional `note`, `directCount`, `transitiveCount`, `risk`, `productionImpactCount`, `directImpact` (capped envelope, maximum 20 entries), the textual-binding fields described under `find_usages`, and `nearest` on an unresolved name.

| Field | Meaning |
|---|---|
| `directCount` | Number of symbols that reference the target directly. Includes test-project callers. |
| `transitiveCount` | Number of symbols in the full transitive closure. Includes test-project callers. |
| `productionImpactCount` | The non-test part of the transitive closure. This is the number the risk label is computed from. |
| `risk` | `none`, `low`, `medium` or `high`. |

**How the risk level is calibrated.** The risk label is computed on the production fan-in only: test-project callers and implementers are excluded, because exercising a symbol from tests is its designed fan-in and updating those tests after the change is mechanical, not risk. The thresholds are `none` for 0, `low` below 5, `medium` up to and including 20, and `high` above 20. `productionImpactCount` discloses the number the label rests on.

For a property, field, event or enum member there is no transitive member chain, so `transitiveCount` equals `directCount`.

**Notes.**

- `risk: "none"` on a solution that has production projects does not by itself carry a note for a symbol used only by tests: `directCount` is then greater than 0 while the risk is `none`. That class is reported by `find_production_dead`, which is outside the default tool set.
- On an unresolved name the answer leads with a note stating that the numbers measure nothing and that `risk: "none"` is the absence of a measurement, not a safe verdict. A mistyped name and a genuinely dependency-free symbol produce the identical answer.
- A resolved symbol with `directCount` 0 carries the escapes note described under `find_usages`.
- If every project in the solution classifies as a test project **and** `productionImpactCount` is 0, a note says so; read `directCount`/`transitiveCount` instead. The count is not structurally forced to zero: unresolved keys and markup fan-in labels can still be classified as production impact.

**Example**

```json
{ "sessionId": "<session>", "symbol": "OrderService" }
```

### `call_graph`

**Purpose.** Build a depth-limited call graph rooted at a method name.

**When to use it.** To see the shape of a call neighborhood – what a method calls, or who calls it – without reading bodies. For a single path between two methods use `trace_flow`.

**Availability.** Core tool set.

**Parameters**

| Parameter | Type | Required | Default | Meaning |
|---|---|---|---|---|
| `sessionId` | string | yes | – | Session id, or an absolute `.sln` path for self-init. |
| `method` | string | yes | – | The root method's name. Alias: `symbol`. |
| `depth` | int | no | `2` | Maximum traversal depth. Values are clamped to 1–10. |
| `direction` | string | no | `"callees"` | `"callees"` follows project-internal calls outward; `"callers"` follows the inverse (who calls this). |

**Response.** `root`, `direction`, `maxDepth`, `edges` (pairs of caller and callee keys), `truncated`, and `rootedAt`. The edge list is cycle-safe and capped at 500 edges; `truncated` says whether the cap was hit.

**Notes.**

- The graph is rooted at the name, not at one symbol: every same-named declaration in the solution is a root and the graph is their union. A common name such as `ExecuteAsync` can pull in unrelated members. Check `rootedAt` – the declarations actually walked – when the result looks too large, and re-query a rarer name.
- An empty `rootedAt` means the name resolved to nothing; an empty edge list alone does not tell you that.
- Note: `direction` is not validated. Any value other than `callees` selects the `callers` direction.

**Example**

```json
{ "sessionId": "<session>", "method": "RunAsync", "depth": 3, "direction": "callers" }
```

### `instantiation_sites`

**Purpose.** Find who instantiates a type – its construction and dependency-injection sites. This is the narrow "who creates or obtains an instance of X?" answer that `find_usages` (every reference: field, parameter, generic argument and so on) cannot give.

**When to use it.** When a type's constructor changes and you need the call sites that must be updated; when you want to know whether a type is obtained through the container rather than constructed; when a fan-in query on the concrete type returned a surprisingly small list.

**Availability.** Default tool set.

**Parameters**

| Parameter | Type | Required | Default | Meaning |
|---|---|---|---|---|
| `sessionId` | string | yes | – | Session id, or an absolute `.sln` path for self-init. |
| `typeName` | string | yes | – | The type's simple name. Namespace and generic arguments are normalized away. Alias: `symbol`. |
| `scope` | string | no | `"solution"` | A namespace prefix that narrows which sites are scanned. |

**Response.** `typeName`, an optional `note`, `createdByCount`, `injectedIntoCount`, `sites` (a capped envelope, maximum 200 entries; created sites first, then injected), and `nearest` when the name matched no declaration. Each site carries `name`, `declaringType`, `namespace` and `kind`.

| Edge kind | Meaning |
|---|---|
| `created` | A method, constructor or accessor that runs `new X(...)`. This includes target-typed `new`, `record with`, and collection or `stackalloc` allocation. A field or property initializer `= new X()` is attributed to the constructor the compiler runs it in – the implicit one when none is declared – so such a site is named `.ctor`; with several non-chaining constructors, one initializer line yields one site per constructor. |
| `injected` | A type that receives X as a constructor-injected dependency; the container constructs X and hands it over. For these sites `declaringType` is null, because the consuming type is the site. |

**Notes.**

- Test-project sites are included, because a test that constructs X breaks when X's constructor changes.
- A concrete type registered in a dependency injection container reports `injectedIntoCount: 0` correctly: its consumers take the interface, so the injection edges sit on the interface's name. When the injected count is zero and the type implements interfaces, the note names them and points you to the query that carries the answer (`resolve_injection` confirms the registration).
- When both counts are zero, a note names the construction paths this fact cannot see: a container registration whose consumers take an interface, a generic service-locator call such as `GetRequiredService<T>()` or `GetService<T>()` (the type appears as a type argument, which is neither edge kind; a fan-in query on the type names the calling type), and `Activator.CreateInstance` or other reflection.
- The tool matches the name against facts without resolving it, so a misspelled type or one outside a narrowed scope yields the same 0/0. When `typeName` matches no declaration, the construction-boundary note remains and a `nearest` suggestion appears alongside it.

**Example**

```json
{ "sessionId": "<session>", "typeName": "OrderRepository", "scope": "MyApp.Infrastructure" }
```

### `trace_flow`

**Purpose.** Trace the shortest static call path between two methods.

**When to use it.** To understand how a flow connects two methods, or which chain of callers triggers a method, before editing.

**Availability.** Not in the default tool set; reachable through a profile whose facet menu includes it (for example Exploration, Debugging, Documentation, Architecture or Performance), or via `AICB_MCP_TOOLS`.

**Parameters**

| Parameter | Type | Required | Default | Meaning |
|---|---|---|---|---|
| `sessionId` | string | yes | – | Session id, or an absolute `.sln` path for self-init. |
| `from` | string | yes | – | The anchor method's name (the start of the trace). |
| `to` | string | yes | – | The target method's name to reach. |
| `maxDepth` | int | no | `12` | Maximum traversal depth. Values are clamped to 1–50. |
| `direction` | string | no | `"callees"` | `"callees"`: how does `from` end up calling `to`? `"callers"`: through which caller chain does `to` reach `from`? Only the exact value `callers` (case-insensitive) selects the reverse direction. |

**Response.** `from`, `to`, `direction`, `found`, `length`, `path` (an ordered `Type.Method` list from `from` to `to`), and a `note`. When no path exists within `maxDepth`, `found` is `false` and the note says so. In `callers` mode each step is called by the next. `length` counts the nodes on the path, not the hops, so a direct call reports `length: 2`.

**Notes.** Resolution is name-based. The tool follows only project-internal static call edges – not interface dispatch, events, dependency injection or reflection. It reads persisted call facts and works on recalled sessions.

**Example**

```json
{ "sessionId": "<session>", "from": "Main", "to": "SaveOrder", "maxDepth": 20 }
```

### `type_dependency_path`

**Purpose.** Trace the shortest type-dependency path between two types – the type-level counterpart to `trace_flow`. It answers the *why* of a transitive dependency, where `impact_of_change` gives only the set of impacted types.

**When to use it.** To find the chain that connects two types, for example why a domain type transitively reaches an infrastructure type – a layering smell.

**Availability.** Not in the default tool set; reachable through a profile whose facet menu includes it (for example Exploration, Debugging, Documentation, Architecture or Performance), or via `AICB_MCP_TOOLS`.

**Parameters**

| Parameter | Type | Required | Default | Meaning |
|---|---|---|---|---|
| `sessionId` | string | yes | – | Session id, or an absolute `.sln` path for self-init. |
| `from` | string | yes | – | The anchor type's simple name (the start of the trace). |
| `to` | string | yes | – | The target type's simple name to reach. |
| `maxDepth` | int | no | `12` | Maximum traversal depth. Values are clamped to 1–50. |
| `direction` | string | no | `"dependencies"` | `"dependencies"`: how does `from` end up depending on `to`? `"dependents"`: through which dependent chain does `to` reach `from`? Only the exact value `dependents` (case-insensitive) selects the reverse direction. |

**Response.** `from`, `to`, `direction`, `found`, `length`, `path` (an ordered type-name list from `from` to `to`) and a `note`. When no path exists within `maxDepth`, `found` is `false` and the note says so. In `dependents` mode each step is depended on by the next. `length` counts the nodes on the path, so a direct dependency reports `length: 2`.

**Notes.**

- A type A depends on B when A references B: as a base type or interface, field, property, parameter, return type, generic argument, or a type used in its body. These are the same forward type-dependency edges that `find_usages` inverts and `impact_of_change` closes over, so a `dependencies` path from A to B exists exactly when A appears in `impact_of_change(B)`.
- Resolution is name-based on simple type names; cross-namespace name collisions collapse. Only intra-solution types can be endpoints – external and framework types are not.

**Example**

```json
{ "sessionId": "<session>", "from": "OrderService", "to": "SqliteOrderRepository" }
```

## 7.3 Hierarchy, implementations and lifecycle

### `find_implementations`

**Purpose.** List the types that implement an interface.

**When to use it.** Before changing an interface, to see every implementer that must be updated; when you want to know whether an interface has one production implementation or many.

**Availability.** Core tool set.

**Parameters**

| Parameter | Type | Required | Default | Meaning |
|---|---|---|---|---|
| `sessionId` | string | yes | – | Session id, or an absolute `.sln` path for self-init. |
| `interfaceName` | string | yes | – | The interface's simple name. An arity suffix in metadata or declaration form – `IConsumer`1` or `IConsumer<T>`, or `IConsumer`0` for the non-generic namesake – filters to that arity; a bare name keeps the merged view over all arities. Aliases: `symbol`, `interface`. |
| `includeTests` | bool | no | `false` | Include test-project implementers. |

**Response.** An optional leading `note` (set when the analysis run could not resolve all project references), the item list in the shared capped envelope (`items`, `count`, `totalFound`, `truncated`, maximum 100), an optional `hint`, and `testImplementationsFiltered`.

Each item carries `name`, `isAbstract`, `kind` (`class`, `struct`, `record` or `interface`) and `isTestProject`, so an abstract base or a test fake is distinguishable from a concrete production implementer. A generic implementer additionally carries `declaration`, its arity-qualified form such as `PolicyWrap<TResult>`, so a generic and a non-generic pair sharing name and namespace stay distinguishable. An item whose only evidence is the interface's back-edge membership carries `via: "back-edge"`.

**Notes.**

- Test-project implementers are excluded by default. When that filter removed something, `testImplementationsFiltered` reports how many – a short list is never silently short. Set `includeTests: true` to see them.
- An empty result carries a `hint` in two cases: when the name is a class rather than an interface (the hint points to `get_type_hierarchy` and `find_overrides`), and when the name is not declared in the solution at all (the hint says so and carries a did-you-mean when one is close enough). An empty list is a statement about the name, not about implementers.

**Example**

```json
{ "sessionId": "<session>", "interfaceName": "ICodeAnalyzer", "includeTests": false }
```

### `find_overrides`

**Purpose.** List the override-to-base relationships for methods of a given name – the class-inheritance counterpart to `find_implementations`. It answers both "who overrides this virtual or abstract method?" (impact) and "what does this override?" (comprehension) in one call.

**When to use it.** Before changing a virtual or abstract method's signature, and when you want to see how a base behavior is specialized across the hierarchy.

**Availability.** Core tool set.

**Parameters**

| Parameter | Type | Required | Default | Meaning |
|---|---|---|---|---|
| `sessionId` | string | yes | – | Session id, or an absolute `.sln` path for self-init. |
| `methodName` | string | yes | – | The method's exact (case-sensitive) simple name, for example `ToString` or `Dispose`. Alias: `symbol`. |

**Response.** The shared capped envelope (`items`, `count`, `totalFound`, `truncated`, maximum 100). Each entry pairs an overriding method with the nearest ancestor that declares the virtual or abstract method it overrides, rendered as `Derived.M(params) overrides Base`. Container and base render in their declaration form, for example `Strategy<T>.M(...) overrides ResilienceStrategy<TResult>`. When the overridden base is a framework virtual outside the solution, the entry reads `... overrides (external base)`. An empty list means no overrides of that name were found.

**Notes.** Two same-named types that differ only by namespace, or that declare identical type-parameter names, render identically and collapse into a single row – the list carries no namespace. Treat a row as the relationship, not as one attributed type.

**Example**

```json
{ "sessionId": "<session>", "methodName": "Dispose" }
```

### `get_type_hierarchy`

**Purpose.** Walk a type's inheritance hierarchy in both directions: the base-class chain upward and the transitively derived types downward, plus the type's implemented interfaces.

**When to use it.** To see where a type sits in the hierarchy, which types derive from a base, or which interfaces a type implements. For "who implements this interface", use `find_implementations` instead – interfaces never appear as a base class, so an interface's `derivedTypes` is empty.

**Availability.** Core tool set.

**Parameters**

| Parameter | Type | Required | Default | Meaning |
|---|---|---|---|---|
| `sessionId` | string | yes | – | Session id, or an absolute `.sln` path for self-init. |
| `typeName` | string | yes | – | The type's exact (case-sensitive) simple name. Add an arity suffix – `Repository<T>` or `Repository`1` – to address a generic type unambiguously when a generic and a non-generic type share the name. Alias: `symbol`. |

**Response.** `type`, `resolvedKind`, an optional `note` (the run-wide qualification), an optional `hint`, `mergedNamesakes`, `separatedNamesakes`, `baseChain`, `interfaces`, and `derivedTypes` (a capped envelope, maximum 100).

- `baseChain` lists the base-class chain upward, nearest base first. When the chain leaves the solution, the last entry names the external base, for example `ObservableObject (external)`.
- `interfaces` lists the type's implemented interfaces; for an interface query these are its base interfaces.
- `derivedTypes` lists transitively derived types; each entry reads `Derived : DirectBase`, so the subtree structure is preserved in the flat list.
- Every link is rendered arity-qualified, so a same-name generic and non-generic type are distinguishable.
- `resolvedKind: "not_found"` means no type of that name is in the solution.

**Notes.**

- The simple-name index merges namesakes – same simple name, different declared type, from a foreign namespace or a different declaring type. When the answered view merged such types, `mergedNamesakes` names them ahead of the lists they may affect. An arity suffix separates arities only; namesakes cannot be separated.
- `derivedTypes` lists a type only when its declared base really is the resolved type. A derivation from a same-named *other* type – typically a framework base shadowed by an in-solution namesake – is excluded and counted in `separatedNamesakes`, which names the resolved type and the foreign bases. Without it, an empty `derivedTypes` on a name the solution plainly uses as a base would read as "nothing derives from this".
- An interface query carries a `hint` stating that `derivedTypes` covers class inheritance only and pointing to `find_implementations`.

**Example**

```json
{ "sessionId": "<session>", "typeName": "GraphSectionRendererBase" }
```

### `lifecycle_of`

**Purpose.** Map the full lifecycle of a type T in one edge-partitioned slice – who creates, injects, returns, references and persists it – instead of calling `find_usages` and `instantiation_sites` separately and partitioning by hand.

**When to use it.** When you need the whole picture of how a type is produced and consumed; and for the recurring "persisted but dropped" bug class: if the write leg shows up in `created` or `persisted` but nothing reads T back, that asymmetry is the smell.

**Availability.** Not in the default tool set; reachable through a profile whose facet menu includes it (for example Exploration, Debugging, Documentation, Architecture or Performance), or via `AICB_MCP_TOOLS`.

**Parameters**

| Parameter | Type | Required | Default | Meaning |
|---|---|---|---|---|
| `sessionId` | string | yes | – | Session id, or an absolute `.sln` path for self-init. |
| `typeName` | string | yes | – | The type whose lifecycle to map. Simple name; namespace and generic arguments are normalized away. Alias: `symbol`. |
| `scope` | string | no | `"solution"` | A namespace prefix that narrows which sites are reported – not the target type. |

**Response.** `typeName`, `scope`, an optional leading `note`, `targetIsDeclared`, `typesScanned`, `methodsScanned`, and the five buckets `created`, `injected`, `returned`, `referenced` and `persisted`. Each bucket is a capped envelope with its true total (maximum 100 entries), and each entry carries `name`, `declaringType` and `namespace`.

| Bucket | Meaning |
|---|---|
| `created` | Methods that run `new T(...)`. |
| `injected` | Types that receive T as a constructor-injected dependency. |
| `returned` | Methods whose return type is or wraps T – `Task<T>`, `IReadOnlyList<T>` and other factory shapes included. |
| `referenced` | The full type fan-in, equivalent to `find_usages`. This is the read/use umbrella and deliberately overlaps the specific buckets. |
| `persisted` | Best-effort: methods with a database or serialization side effect that reference T – the persist and round-trip edge. |

**Notes.**

- The answer states what it looked at: `scope` echoes the applied filter, `typesScanned` is the population behind `injected` and `referenced`, and `methodsScanned` is the population behind `created`, `returned` and `persisted`. Because `scope` narrows the sites of every bucket, it is a second route to five zeros that has nothing to do with the type.
- `targetIsDeclared` says whether a type of that simple name is declared in the solution at all. `false` means an external type or a misspelling, and any edges shown are then this solution's use of an outside type rather than that type's lifecycle.
- A `note` leads the buckets whenever a zero needs qualifying.
- Like `find_usages` and `instantiation_sites`, this is a discovery and impact tool, so test-project sites are included.
- It reads persisted facts and works on recalled sessions.

**Example**

```json
{ "sessionId": "<session>", "typeName": "OrderDto", "scope": "MyApp.Application" }
```

## 7.4 Tests and coverage

### `find_tests_for`

**Purpose.** Find the test cases that likely cover a symbol.

**When to use it.** Before changing a symbol, to see which tests pin it; when you want to know whether a method is exercised at all.

**Availability.** Core tool set.

**Parameters**

| Parameter | Type | Required | Default | Meaning |
|---|---|---|---|---|
| `sessionId` | string | yes | – | Session id, or an absolute `.sln` path for self-init. |
| `symbol` | string | yes | – | A type name, or a member name either bare or in the qualified `Type.Member` form – the same strings `find_usages` and `impact_of_change` resolve. |

**Which methods count as tests.** Only a method that itself carries a test attribute counts – an actual runnable test, not a fixture builder or helper that merely lives in a test project. The default attribute set is `Fact`, `Theory`, `Test`, `TestMethod` and `TestCase`, matched as a case-insensitive substring so that variants such as `WindowsFact` are recognized. The set is configurable through the solution's test profile.

**Response.** The shared capped envelope (`items`, `count`, `totalFound`, `truncated`, maximum 50), plus `invokesTotal` and an optional `note`. Each item carries `testType`, `testMethod`, `project` and `matchReason`.

**Match tiers.** `matchReason` names three tiers, ordered by how direct the evidence is:

| Tier | Meaning |
|---|---|
| `invokes` | The test calls the target itself. |
| `invokes-via` | The test reaches the target through one method it calls – still strong, but second-hand. |
| `name` | The weak guess: the test's own name or its test class's name mentions the symbol at an identifier-segment boundary. A mid-word substring is not a mention. |

The strong tier is limited to exactly two hops: the test itself and one method it calls, whether that is its own helper or a production entry point. A deeper chain (helper calling helper) or a table-driven sweep is not counted. `invokesTotal` counts both strong tiers over the whole result, not only the returned page. Direct hits sort ahead of helper hops, which sort ahead of name guesses, so the cap can only drop the least load-bearing end.

**Notes.** A `note` names four cases where the bare numbers mislead:

- A qualified query whose type segment names no declared type. Matching is case-sensitive, so the strong tier silently collected nothing and every hit is weak name noise.
- A query that names nothing declared at all. A full page of hits then describes the spelling, not this solution's coverage.
- An empty answer on a symbol that does resolve. The note names the two-hop limit and the declaring type's own count, because a bare 0 otherwise reads as "nothing pins this".
- A query that resolves to a declared property, field, event or enum member. Those declarations have no invocation edge in this query, so any returned hits are name matches.

**Example**

```json
{ "sessionId": "<session>", "symbol": "OrderService.Cancel" }
```

### `coverage_gaps`

**Purpose.** Surface negative knowledge for a scope: methods that no test invokes directly, and semantic axes that are explicitly declared absent.

**When to use it.** Before claiming that code is covered; when you want a list of untested methods; when you want to know which semantic annotations are deliberately blank.

**Availability.** Default tool set.

**Parameters**

| Parameter | Type | Required | Default | Meaning |
|---|---|---|---|---|
| `sessionId` | string | yes | – | Session id, or an absolute `.sln` path for self-init. |
| `scope` | string | no | `"solution"` | `"solution"` or a namespace prefix to narrow which symbols are checked. |

**Response.** `scope`, an optional `note`, `symbolsScanned`, `uncovered` (a capped envelope, maximum 200), `verifiedAbsent` (a capped envelope, maximum 200), `transitivelyReached`, `judgedUnits`, `testProjectsExcluded` and `testFixtureTypesExcluded`.

| Field | Meaning |
|---|---|
| `uncovered` | Methods that no test invokes directly. Each item carries `kind`, `name`, `declaringType`, `namespace` and, when applicable, `testReachDepth`. |
| `verifiedAbsent` | Semantic axes the developer explicitly declared as `none`. Each item carries `kind`, `name`, `declaringType`, `namespace` and `field`. |
| `symbolsScanned` | Every unit in scope, methods and types. |
| `judgedUnits` | The non-test, non-abstract methods the uncovered list is drawn from – the population behind the gap count. |
| `testProjectsExcluded` | The distinct test-classified projects whose units were excluded. |
| `testFixtureTypesExcluded` | The distinct types excluded through the attribute-inferred fixture axis: a type that declares a test-attributed method is a test fixture, so its attribute-less `SetUp`/helper scaffolding is test code even when the project's name matches no test rule. |

**The one-hop definition.** The uncovered list is a one-hop index, not a coverage measurement. A method that a test reaches through another method – a CLI verb behind its command builder, a handler behind a dispatcher – is listed as uncovered although it is thoroughly exercised. Therefore read the per-entry `testReachDepth`: the hops to the nearest directly tested method, where 1 means a directly tested method calls it. Entries without that field are the ones no test reaches at all – work those first. A shallow depth is close to "already exercised" (confirm with `find_tests_for`); a deep one is more likely incidental.

The entries are marked rather than filtered out, because a deep transitive path is not the same claim as a test, and silently hiding a genuinely untested method would be the worse error for a tool whose job is negative knowledge.

**Notes.**

- A non-empty answer leads with a `note` carrying the split for that answer – how many of the listed methods are reached from a test through intermediate calls – and the same count is available as `transitivelyReached`. When no listed method is reached even indirectly, the note says so instead.
- Abstract and interface method declarations are excluded: they have no body and are not coverable units.
- A weak test-name match does not count as coverage here; it is too weak to prove anything.
- Runtime coverage from a coverage tool remains the only measurement that sees reflection, generated and framework-invoked paths.
- Absence of a detected test is not proof that zero tests exist.

**Example**

```json
{ "sessionId": "<session>", "scope": "MyApp.Application" }
```

### `find_by_complexity_and_coverage`

**Purpose.** The prioritized refactor and test list: the methods that are both complex and have no direct test call – the intersection of the complexity ranking and the uncovered list, in one call, ranked by complexity descending so the riskiest float to the top.

**When to use it.** When you want to pick the next refactoring or test target by risk rather than by browsing two separate lists.

**Availability.** Not in the default tool set; reachable through a profile whose facet menu includes it (for example Refactoring, Debugging, Review, Testing or Performance), or via `AICB_MCP_TOOLS`.

**Parameters**

| Parameter | Type | Required | Default | Meaning |
|---|---|---|---|---|
| `sessionId` | string | yes | – | Session id, or an absolute `.sln` path for self-init. |
| `minComplexity` | int | no | `0` | Complexity floor. Only methods with cyclomatic complexity greater than or equal to this value are considered; 0 means no floor. The list is ranked by complexity descending regardless. Raise it, for example to 10, to keep only genuinely complex untested methods. |
| `scope` | string | no | `"solution"` | `"solution"` or a namespace prefix to narrow scope. |

**Response.** `scope`, an optional leading `note`, `minComplexity`, `complexMethodCount`, `uncoveredMethodCount`, `methods` (a capped envelope, maximum 200, complexity descending) and `transitivelyReached`.

`complexMethodCount` and `uncoveredMethodCount` report the two input sizes – the complex methods at or above the floor, and the uncovered methods in scope. Each item carries `name`, `declaringType`, `namespace`, `cyclomaticComplexity`, `parameterCount` and, when applicable, `testReachDepth`.

**Notes.**

- The tool inherits the one-hop definition from `coverage_gaps`: a method a test reaches through another method is in this list too. Read the per-item `testReachDepth` and treat the items without it as the real candidates – the distinction matters more here than in `coverage_gaps`, because this output is a worklist people act on. A non-empty answer leads with a note carrying that split.
- There is no `includeTests` switch, deliberately: the complexity half excludes test-project methods, and a test method is by definition never untested.
- Overloads remain separate entries, each with its own complexity and parameter count; the shared `(namespace, declaring type, name)` key is only used to look up coverage.
- It composes two persisted-fact services and works on recalled sessions.

**Example**

```json
{ "sessionId": "<session>", "minComplexity": 10, "scope": "MyApp.Core" }
```

### `assert_absence`

**Purpose.** Check a negative claim against the analyzed model and return `confirmed`, `refuted` or `indeterminate` with the evidence.

**When to use it.** To validate statements such as "this service is untested" or "this axis is explicitly unset" before relying on them.

**Availability.** Default tool set.

**Parameters**

| Parameter | Type | Required | Default | Meaning |
|---|---|---|---|---|
| `sessionId` | string | yes | – | Session id, or an absolute `.sln` path for self-init. |
| `claim` | string | yes | – | One of the three claim forms below. |

| Claim | Meaning |
|---|---|
| `no_tests:<Symbol>` | The symbol has no detected covering test. |
| `absent:<Symbol>.<axis>` | The semantic axis is verified-absent – a developer explicitly declared `none`, not merely unknown. |
| `unknown:<Symbol>.<axis>` | The axis has no provenance entry at all. |

`<Symbol>` is a bare name or the qualified `Type.Member` form – the same strings that `find_usages`, `find_tests_for` and `impact_of_change` resolve. `axis` is one of the semantic axes, for example `role`, `layer`, `domain`, `context` or `responsibility`.

**Response.** `claim`, `claimType`, `symbol`, `axis`, `verdict`, `reason` and `evidence` (a list of strings).

**Verdicts.**

| Verdict | Meaning |
|---|---|
| `confirmed` | The model supports the claim. For `no_tests` this means no covering test was detected. For `absent` the axis really is verified-absent. For `unknown` the axis really has no provenance entry. |
| `refuted` | The model contradicts the claim. For `no_tests` this requires at least one strong covering test – one that invokes the symbol, directly or through one method it calls. For `absent` the axis has a provenance source other than verified-absent. |
| `indeterminate` | The model cannot decide. |

**Notes.**

- The tool is conservative in both directions: what the model cannot prove is `indeterminate`, never falsely confirmed – and never falsely refuted either.
- Tests that merely carry the symbol in their name yield `indeterminate` with the invokes/name-only split disclosed in the reason, not a refutation; a test named after a symbol is not proof that it exercises it.
- For a property, field, event or enum member, `no_tests` can only ever rest on name matches, because that member kind carries no invocation edge; the reason says so.
- A name that resolves to nothing is reported as such – a statement about the name, not about the code.
- An axis name that is not recorded anywhere in the solution returns `indeterminate` with the actually recorded axes as evidence. A typo or an invented axis is never silently `confirmed`.

**Example**

```json
{ "sessionId": "<session>", "claim": "no_tests:OrderService.Cancel" }
```

## 7.5 Dependency injection

### `resolve_injection`

**Purpose.** Resolve a `Microsoft.Extensions.DependencyInjection` registration: given an interface, return the concrete implementation or implementations registered for it, the lifetime, and where the registration happens – `location` (the `Add*` call as file and line), `project` and `declaringMethod`.

**When to use it.** When you need to know which implementation is wired for an interface, which lifetime applies, or where a registration lives; when a fan-in or instantiation answer suggests a container registration.

**Availability.** Default tool set. Note: this tool needs a live analyzed session; a session restored from a saved snapshot cannot answer it.

**Parameters**

| Parameter | Type | Required | Default | Meaning |
|---|---|---|---|---|
| `sessionId` | string | yes | – | Session id, or an absolute `.sln` path for self-init. |
| `interface` | string | yes | – | The interface's simple or fully qualified name, for example `ICodeAnalyzer`. Aliases: `symbol`, `interfaceName`. |
| `site` | string | no | `null` | Narrow to registrations whose file path contains this substring. |
| `includeTests` | bool | no | `false` | Include registrations declared in test projects. |

**What is scanned.** `AddSingleton`, `AddScoped` and `AddTransient`, their `TryAdd*` variants, and project-local wrappers whose name ends in a lifetime, such as `AddCachedSingleton` – in generic, `typeof`, instance and factory-lambda form. Plus exactly one data-driven shape: a `foreach` over a static table of `new(typeof(Service), typeof(Impl))` rows is expanded into one registration per row, also when the table lives in another project. Such a registration carries the note `table row <file>:<line>`.

A call whose service type is a runtime value – reflection or assembly scans, a method result, a deconstructed loop variable – is not expanded, and neither is a factory lambda whose product cannot be named. Instead the response leads with a `note` naming those sites and which of the two kinds each one is. An empty list with such a note means "not statically visible", not "not registered".

A factory that *returns* its object is resolved: both `sp => Foo.Build()` and a block body whose `return` statements all agree on one type. Where they disagree, or where there is no `return` at all, the product stays unnamed and the site is disclosed rather than guessed at. A `return` inside a nested lambda or local function belongs to that function, not to the factory.

**Response.** `query`, `matchCount`, `ambiguous`, `multiRegistration`, `registrationSites`, `consumedAsCollection`, `testRegistrationsFiltered`, and `registrations`. Each registration carries `serviceType`, `implementationType`, `lifetime` (`Singleton`, `Scoped` or `Transient`), an optional `note`, `location` (file and line of the `Add*` call), `project`, `declaringMethod` (`Type.Method`; null for top-level statements) and `isTestProject` when the registration comes from a test project.

| Field | Meaning |
|---|---|
| `registrationSites` | How many distinct registration sites matched. |
| `multiRegistration` | Whether more than one registration matched at all. |
| `consumedAsCollection` | True when the service is consumed as a collection somewhere – a `GetServices<T>()` or `GetServices(typeof(T))` call, or an `IEnumerable<T>`-family or `T[]` constructor parameter, optional and nullable ones included. Several registrations are then a deliberate multi-binding. Consumers declared in test projects count only under `includeTests`, exactly as the registration list does. |
| `ambiguous` | Judged within one registration site – one declaring method, or the file outside any method: true only when that site registers more than one distinct, statically resolvable implementation and `consumedAsCollection` is false. Across sites it is deliberately not ambiguity: a solution with several hosts (GUI, CLI, MCP) registers the same service once per host, and those containers never meet. Use `registrationSites`, `multiRegistration` and the per-registration `declaringMethod` to judge the case this grain cannot see: two helper methods composed by the same host. |
| `testRegistrationsFiltered` | How many registrations the default test filter removed. Omitted when nothing was hidden. |

**The three empty answers are distinguishable.**

1. A name that resolves to nothing – no declaration and no registration – carries `resolvedKind: "not_found"` and a `nearest` suggestion: a typo.
2. On an unfiltered query (no `site`, and nothing removed by the test filter), a real name with no registration carries a `note` that states the reader's boundary: no `Microsoft.Extensions.DependencyInjection` (`Add*`/`TryAdd*`) registration was found, which is not proof that nothing registers it – Autofac, Castle Windsor and other non-Microsoft containers, and keyed, open-generic and Scrutor registrations, stay out of scope. When a scanned project references a foreign container assembly, the note names that sign instead, because its registrations are invisible here. With a `site` filter, an empty result can be blank.
3. Everything was filtered out by the test filter, reported as `testRegistrationsFiltered: N`.

**Notes.**

- Test-project registrations are excluded by default – a test's own container stub is not the production binding. Set `includeTests: true` to include them; each one is flagged `isTestProject`. The same filter reaches collection CONSUMPTION: a fixture taking `IEnumerable<T>` does not, on its own, mark a production conflict between two registrations as deliberate.
- A service consumed as a collection is not flagged as ambiguous even with several registrations; see `consumedAsCollection`.

**Example**

```json
{ "sessionId": "<session>", "interface": "ICodeAnalyzer", "site": "DependencyInjection" }
```

---

[&larr; 6 Tool reference: orientation, sessions and symbols](06-tool-reference-orientation-sessions-and-symbols.md) &middot; [Contents](README.md) &middot; [8 Tool reference: facts, dead code, metrics and patterns &rarr;](08-tool-reference-facts-dead-code-metrics-and-patterns.md)
