[AICB – MCP Server](README.md) &middot; chapter 9 of 12

# 9 Tool reference: markup, export, review and insights

This chapter documents the tools for XAML/AXAML markup, for packing and exporting context, for reviewing changes, and for reading quality insights. All of them are called through an MCP client. Two of them can write: `export_markdown` writes a file when you pass `outputPath`, and `diff_review` writes to the triage log when you pass `recordRegressions: true`. Everything else only reads.

Several tools accept a `dbPath` for the configuration database. When you omit it, the server's default configuration database applies — the same database the desktop application uses — so the quality profile and layer profile you configured there take effect. For `diff_review` with `recordRegressions: true`, that default also determines where the write goes.

Most tools take a `sessionId`. A session is created by `analyze_solution`, or on first use when you pass the absolute path of a `.sln`, `.slnx` or `.slnf` file; see "Sessions and staleness".

The default MCP profile exposes a curated tool set. Where a tool below is not part of it, its availability line says so and names the two ways to expose it: start the server with the `Full Select` profile (`aicb mcp --mcp-profile mcp-profile/full`), or set the `AICB_MCP_TOOLS` environment variable. Where a tool can be used as a sub-query of `batch`, the availability line says that too.

## 9.1 Markup: XAML/AXAML bindings and resource keys

Markup connects views to view-models and to resources by string. Resource keys have no C# symbol edge, while a resolved view-model's root `{Binding}` member is represented in the symbol graph as a low-confidence `(xaml)` edge; the graph does not retain the markup site's binding form. `find_resource_usages` and `find_binding_usages` scan current files on disk and therefore do not need `refresh_session`. `find_unresolved_bindings` instead reads the live analysis result: refresh after markup or view-model edits, and expect no findings from a recalled snapshot.

### `find_unresolved_bindings`

**Purpose.** List silently broken bindings: a `{Binding X}` whose root member does not exist on its confidently resolved DataContext view-model — a typo, a removed or renamed member, or the wrong DataContext. The compiler does not catch this class of defect.

**When to use it.** After renaming or removing a view-model member, after moving a view to another view-model, and as a lint pass before a release.

| Parameter | Type | Required | Default | Meaning |
|---|---|---|---|---|
| `sessionId` | string | yes | — | The session id returned by `analyze_solution` (or the absolute path to a solution file). |

**Coverage.**

- WPF/WinUI `.xaml`: the view-model is resolved through `d:DesignInstance` or through a unique `FooView` → `FooViewModel` naming convention.
- Avalonia `.axaml`: `{Binding}` and `{CompiledBinding}`; the view-model is resolved only through `x:DataType` at scope level, so no naming convention applies.

**What is deliberately skipped.** A binding whose DataContext scope cannot be typed with certainty is never flagged: `ControlTemplate`/`Style`, a runtime DataContext, keyed resources, and a template without a `DataType`. WPF alone recovers an item template's type from the host's pinned `ItemsSource`; on Avalonia, a template without `x:DataType` — `TreeDataTemplate` included — is always skipped. Only view-models resolved with certainty and with a verifiable member surface are checked; source-generated members (`[ObservableProperty]`, `[RelayCommand]`) and inherited members count as resolved. The trade-off is a recall miss, never a false report.

**Response.**

| Field | Meaning |
|---|---|
| `count` | Number of unresolved bindings found. |
| `unresolvedBindings` | One entry per finding: `view`, `viewModel`, `member` (the absent root member), `line` (1-based line of the binding attribute; `0` means unknown). |
| `markupFilesScanned` | Markup files discovered by a live disk walk of the session's project directories. |
| `bindingSitesInMarkup` | Binding sites found by the same live walk — the markup population. |
| `sitesJudged`, `sitesSkipped` | The resolver's denominator. `0` when the walk found no binding site, otherwise `null` (see the note below). |
| `judgementNote` | Present when `sitesJudged`/`sitesSkipped` are `null`; explains why. |
| `note` | Present when the zero needs qualification: a session without a completeness fact (a recalled snapshot), an incomplete analysis run, or a solution with no markup at all. |

Note: `bindingSitesInMarkup` is the live scan total, not the denominator of `count` — it includes the scopes this tool conservatively skips. Because the analysis model stores only the unresolved findings and not the per-site eligibility decision, `sitesJudged` and `sitesSkipped` are `null` on every solution that has bindings, and `judgementNote` says so. Read the population counts as the measure of what was looked at, and a hit as high-confidence evidence that you verify at its `file:line`, not as proof.

Note: identical findings from multi-targeted analysis instances are deduplicated, so a site is reported once, not once per target framework.

Note: the verdict is computed live during analysis and is not persisted. A session recalled from a saved snapshot therefore reports none, and the `note` says so. Call `refresh_session` after markup or view-model edits and run the tool again.

Note: the same findings also appear in `list_insights` as the `design-unresolved-xaml-binding` insight, so a review of that insight sees them without calling this tool.

Availability: in the default tool set; usable as a sub-query of `batch`.

### `find_resource_usages`

**Purpose.** Resource-key fan-in across the solution's XAML/AXAML markup and its C# sources — the question the C# symbol graph cannot answer, because resources are wired by string key.

**When to use it.** Before deleting or renaming a resource key. Deleting a still-referenced key compiles cleanly and throws only at runtime, so a text search is the wrong instrument: this tool also finds the references that live in C# string literals.

| Parameter | Type | Required | Default | Meaning |
|---|---|---|---|---|
| `sessionId` | string | yes | — | The session id returned by `analyze_solution`. |
| `key` | string | no | `null` | The exact, case-sensitive resource key, e.g. `TextPrimaryBrush`. Omit it for the audit view. |
| `scope` | string | no | `"solution"` | `solution`, or a view-path substring (e.g. `AIContextBuilder.UI/`) to narrow which files are reported. |

**With a key.**

| Field | Meaning |
|---|---|
| `definitions` | Where the key is defined (`x:Key`), each with `view` and `line`. |
| `definitionCount` | Number of definitions in scope. |
| `references` | Every reference site with `view`, `line` and `kind`. |
| `referenceCount`, `staticReferenceCount`, `dynamicReferenceCount`, `codeReferenceCount` | Reference totals, split by channel. |
| `sameFileCollisions` | Duplicate definitions of the same key in one file (`key`, `view`, `lines`). |
| `referencesTruncated` | `true` when the reference list was capped at 200. |
| `scannedFileCount`, `scannedCodeFileCount` | Markup files and C# files read. |
| `note` | Present when there is something to qualify (see below). |

The `kind` of a reference tells you which channel it came through:

- `static` — `{StaticResource Key}`, resolved once at load time.
- `dynamic` — `{DynamicResource Key}`, re-resolved on every lookup, so it survives a theme swap. A brush that is swapped with the theme must be referenced dynamically.
- `code` — a C# string literal whose text equals the key, the `TryFindResource` channel, reported with its file and line.

Only same-file duplicates are reported as collisions: in a compiled resource dictionary a later duplicate silently shadows an earlier one, while a same-named key in a *different* file is usually a legitimate theme pair.

The `note` distinguishes four states: the key is not found anywhere in the markup (misspelled — keys are case-sensitive — or it lives in a theme or library assembly); the key is defined but has no references; the key is referenced but has no definition in scope (it may be defined in a theme or library assembly); or the scan read no markup at all.

**Without a key (audit view).**

| Field | Meaning |
|---|---|
| `totalDefinedKeys` | Number of distinct keys defined in scope. |
| `neverReferencedKeys` | Every key with zero references, grouped with its definition sites (`key`, `definedIn`): the deletion candidates. |
| `neverReferencedTotal`, `neverReferencedTruncated` | True total and cap flag (list capped at 200). |
| `sameFileCollisions` | All same-file duplicate definitions in scope. |
| `scannedFileCount`, `scannedCodeFileCount` | Markup files and C# files read. |
| `note` | The fan-in scope note (see below), or the no-markup note. |

**Scope.** In the audit view the scope narrows which definitions are audited; references still count solution-wide, so a key referenced outside the scope is not a false orphan. With a key, the scope narrows both the definitions and the references that are reported, and the counts follow.

Note: the tool reads the current `.xaml`/`.axaml`/`.cs` files on disk (`bin`, `obj` and `.vs` are excluded). It is never stale after an edit, needs no `refresh_session`, and works on recalled sessions.

Note: only string keys are in scope. A structural `x:Key="{x:Type ...}"` and the long form `{StaticResource ResourceKey=...}` are not seen; XML-commented markup is ignored.

Note: fan-in comes from two channels — the solution's markup and C# string literals equal to the key. A matching literal is not by itself proof of a resource lookup: it may be a test assertion or a documentation `cref` naming a same-named converter type. Still invisible are a key assembled at runtime (interpolated or concatenated), a source file that is not `.cs`, and a third-party library template that resolves the key from its own assembly. Zero references means "verify before deleting", not proof.

Availability: in the default tool set; usable as a sub-query of `batch`.

### `find_binding_usages`

**Purpose.** Binding-path fan-in across the solution's markup. The symbol graph records a `{Binding}` root member against a resolved view-model as a low-confidence edge tagged `(xaml)`; this tool adds the site list, the resolution form, the deeper-path split and the forms the fan-in layer skips.

**When to use it.** Before renaming or deleting a bound member, to see every markup site that consumes it — and to see which bindings hang on an ancestor lookup instead of on the DataContext.

| Parameter | Type | Required | Default | Meaning |
|---|---|---|---|---|
| `sessionId` | string | yes | — | The session id returned by `analyze_solution`. |
| `path` | string | no | `null` | The exact, case-sensitive bound member path, e.g. `GestureLabel` or `Foo.Bar`. Omit it for the inventory view. |
| `scope` | string | no | `"solution"` | `solution`, or a view-path substring (e.g. `AIContextBuilder.UI/Views/Dialogs`) to narrow which markup files are reported. |
| `form` | string | no | `null` | Form filter: `dataContext`, `elementName`, `relativeSource` or `source`. Omit it for all forms. Applies to both views. |

**With a path.**

| Field | Meaning |
|---|---|
| `sites` | Every binding site: `view`, `line`, `path`, `form`. |
| `siteCount` | True number of sites (the list is capped at 200). |
| `byForm` | Site counts per form: `dataContext`, `elementName`, `relativeSource`, `source`. |
| `deeperSegmentSites`, `deeperSegmentSiteCount` | Sites that name the path only as a deeper segment of another member's path (see below). |
| `pathlessBindingCount` | Bindings that name no member at all — solution-wide, not narrowed by `scope` or `form`. |
| `sitesTruncated` | `true` when the site list was capped at 200. |
| `note` | The matching result, the deeper-segment disclosure and the fan-in scope note. |

The `form` of a site tells you what it resolves against:

- `dataContext` — the view-model; the only form that is a view-model member edge.
- `elementName` — another named element in the same scope.
- `relativeSource` — an ancestor, the templated parent, or self.
- `source` — an explicit object (a static, a resource).

**Matching rule.** A path matches as the whole path or as its root segment. `Foo` finds `{Binding Foo}` and `{Binding Foo.Bar}` — both consume `Foo`. The `Bar` in `{Binding Foo.Bar}` does not match: it is a member of `Foo`'s type. Such sites are reported separately under `deeperSegmentSites` with their own count, because a rename of the same-named member on the nested type goes through exactly them. When there are deeper-segment sites, the `note` names up to two of them and points at the list.

**Element hop rule.** On an `elementName` or `relativeSource` redirect, a leading `DataContext.` is the hop to the element's view-model, not a member: `{Binding DataContext.Cmd, RelativeSource={RelativeSource AncestorType=UserControl}}` — the item-template idiom for a command on the page view-model — is a site of `Cmd`. On a plain binding or a `Source=` binding the segment stays the root, because there the source is not an element by construction. A hop in the middle of a path, such as `PlacementTarget.DataContext.Cmd` in a ContextMenu, is not followed either; such a site roots at `PlacementTarget`.

**Without a path (inventory view).**

| Field | Meaning |
|---|---|
| `members` | Every distinct bound root member with `member`, `siteCount` and `byForm`, most-bound first. `{Binding Foo}`, `{Binding Foo.Bar}` and the hop form are one entry. |
| `distinctMemberCount`, `totalSiteCount` | Distinct members and total sites in scope. |
| `pathlessBindingCount` | Bindings that name no member — solution-wide. |
| `membersTruncated` | `true` when the member list was capped at 200. |
| `note` | The fan-in scope note, or a note about an unknown form filter. |

`pathlessBindingCount` covers an empty `{Binding}`, a parameters-only `{Binding Mode=OneWay}` and an attached-property path, so the listed sites and the markup's binding count differ visibly rather than silently.

Note: an unrecognized `form` value matches nothing rather than everything — widening a typo to "all forms" would answer a question nobody asked. The `note` names the typo and the valid values, so the zero is not read as a finding.

Note: this is markup-only fan-in. It sees the `{Binding}` markup-extension form in the solution's own `.xaml`/`.axaml` files. A binding built in code-behind (`SetBinding`, `BindingOperations`), the element syntax `<Binding Path="..."/>`, a WinUI `{x:Bind}`, a `{TemplateBinding}` and any path assembled at runtime are invisible here — zero sites means "verify before renaming or deleting", not proof. This scan also does not resolve the path against a DataContext; `find_unresolved_bindings` is the tool that checks whether a bound member actually exists on its view-model.

The tool reads the current files on disk, so it is never stale after an edit, needs no `refresh_session`, and works on recalled sessions.

Availability: in the default tool set; usable as a sub-query of `batch`.

## 9.2 Packing and exporting context

Four tools with overlapping purpose. The order below is the decision aid: read one symbol with `get_context`; read one symbol with a chosen environment with `explain_symbol`; bundle a task from a goal, read-only, with `pack_for_task`; bundle the same task edit-ready with `prepare_task`; render the whole solution with `export_markdown`.

### `pack_for_task`

**Purpose.** Goal-driven context packing: given a natural-language task, seed on every symbol the goal names (type or method), expand the neighborhood, and return a token-budgeted AI-Builder-Markdown bundle with goal-aware trimming that keeps the most task-relevant methods when the budget is tight.

**When to use it.** You have a task description and want the relevant code in one answer, without the extra material `prepare_task` adds.

| Parameter | Type | Required | Default | Meaning |
|---|---|---|---|---|
| `sessionId` | string | yes | — | The session id returned by `analyze_solution`. |
| `goal` | string | yes | — | The task description. Name the relevant types and methods in it, e.g. `refactor OrderService.Cancel and Validate`. |
| `budget` | integer | no | `null` | Token budget (floor 8000). Exact type names and exact method names with one owner are pinned; broad subword or ambiguous same-name families may be capped by closeness and in-slice fan-in. A leading comment discloses how many types were dropped. Omitted, the bundle renders against a ceiling: the active MCP profile's token budget, else about 10000 tokens. |
| `includeQualityMetrics` | boolean | no | `false` | When true, also emit the `<QUALITY_HOTSPOTS>` section plus `complexity=""` and `ce=""` attributes for the packed symbols. |
| `lean` | boolean | no | `true` | Drop the repeated format-rules preamble and omit enabled-but-empty graph sections; keeps the legends and all non-empty sections. Set `false` for the full AI-Builder-Markdown document. |
| `facet` | string | no | `null` | The task axis of this call: `General` (default), `Exploration`, `Refactoring`, `Debugging`, `Review`, `Testing`, `Documentation`, `Architecture`, `Performance`. The former name `slot` is still accepted. |

Note: `pack_for_task` always renders the lean bundle — its render deliberately stays template-free. The facet only appends a short work-style trailer with suggested next tools. For a template-shaped bundle, use `prepare_task`.

**Response.** The Markdown bundle. If the goal names no known symbol, the answer is an HTML comment that says so (`pack_for_task: goal mentions no known symbol - try naming a type or method`) rather than an empty document.

Note: on a multi-targeted solution, the bundle is deduplicated to one logical project per name, using the newest target framework's instance — the same view `find_symbol` uses.

Availability: in the default tool set; usable as a sub-query of `batch`.

### `prepare_task`

**Purpose.** A task-ready context bundle: seed on the symbols the goal names, expand the neighborhood, and additionally add the test methods that cover those symbols plus one or two naming or file-convention siblings — the test, the factory, the validator you would otherwise miss. Prefer this over `pack_for_task` when you are about to edit, not just read.

| Parameter | Type | Required | Default | Meaning |
|---|---|---|---|---|
| `sessionId` | string | yes | — | The session id returned by `analyze_solution`. |
| `goal` | string | yes | — | The task description; name the relevant types and methods in it. |
| `facet` | string | no | `null` | The task axis (same values as `pack_for_task`). On a profile-aware server (`aicb mcp --db-path`) the facet's template shapes the render; a work-style trailer is always appended. |
| `budget` | integer | no | `null` | Token budget (floor 8000). Applies to both render paths. The goal-named seeds are always kept; the bundled covering tests and siblings are budget-bound and are dropped under a tight budget, with a leading comment naming the drops. Precedence: this parameter, then the MCP profile, then the template, then the global default. Omitted, the bundle renders against a ceiling: the profile's token budget, else about 10000 tokens. |
| `includeTests` | boolean | no | `true` | Include the test methods that cover the seeded symbols. |
| `includeSiblings` | boolean | no | `true` | Include one or two naming or file-convention siblings of the seeded types. |
| `includeQualityMetrics` | boolean | no | `false` | Emit the `<QUALITY_HOTSPOTS>` section and `complexity=""`/`ce=""` attributes. Applies to the lean render path only. |
| `lean` | boolean | no | `true` | Lean slice on the lean render path. Ignored on the profile-aware slot-template render path, which the active profile controls. |

**Response.** The Markdown bundle, led by a one-line manifest so you can see what was covered — and what was not:

```
<!-- prepare_task | goal: "..." | seeds: ... | tests: ... | siblings: ... | render: lean -->
```

Each bundled test carries its evidence tier: `(invokes)` means the test calls the symbol, `(invokes-via)` means it reaches the symbol through one method it calls, and `(name)` is a name guess. When nothing in the list invokes the symbol at either hop, the manifest says so. At most 40 covering tests are bundled per bundle; a cap is disclosed as `(+N more, capped)`. An axis that found nothing reads `(none)`. The `render` segment reads `lean` or `template`.

Note: on a multi-targeted solution, the bundle is deduplicated to one logical project per name, using the newest target framework's instance.

Availability: in the default tool set; not usable as a sub-query of `batch` (it is a heavyweight renderer).

### `export_markdown`

**Purpose.** Render the cached analysis of a session as AI-Builder-Markdown. No re-analysis — the answer is instant.

Note: this renders the whole solution. On a large codebase the default render is a multi-MB document that can exceed the response or token limit. For a bounded view prefer `architecture_overview` (whole-solution orientation, structural only, no per-type source) or `get_context` / `explain_symbol` (one symbol's world).

| Parameter | Type | Required | Default | Meaning |
|---|---|---|---|---|
| `sessionId` | string | yes | — | The session id returned by `analyze_solution`. |
| `facet` | string | no | `null` | The task axis of this call (same nine values as `pack_for_task`). The facet picks the active MCP profile's matching template and appends a short work-style trailer. Unknown or empty falls back to `General`; a facet whose slot has no template assigned falls back to the active context template. The former name `slot` is still accepted. |
| `outputPath` | string | no | `null` | Absolute path to write the Markdown to (UTF-8, no BOM). When given, the tool writes the file and returns a short confirmation — `Wrote N chars of AI-Builder Markdown to '<path>'. ...` — instead of the full Markdown, so a large render does not flood the response. A missing target directory is created. |
| `format` | string | no | `null` | The inner notation of the rendered Markdown: `tag` (the established AI-Builder tag format) or `yaml` (idiomatic YAML — a lossless re-notation, not a different selection of content). An explicit value wins; when omitted, the active MCP profile's `OutputFormat` applies on a profile-aware server, otherwise `yaml`. The `.md` file extension is unchanged. |

Note: an unrecognized explicit `format` value falls back to `tag`. Since a present value counts as explicit, a typo overrides a correctly configured profile format — pass only `tag` or `yaml`.

Note: on a profile-aware server (`aicb mcp --db-path`), the active MCP profile drives the render — the chosen facet's template (detail presets, graphs, line numbers, quality metrics) is used. Without a profile, the full default render is used.

Note: the work-style trailer is appended to the response only; it is never written into the `outputPath` file.

**Response.** The Markdown, or the short confirmation when `outputPath` is set.

Availability: in the default tool set; not usable as a sub-query of `batch` (it writes when `outputPath` is set).

## 9.3 Diff, review and change gates

### `semantic_diff`

**Purpose.** Diff two analyzed sessions structurally: added and removed types and, for types present in both, added and removed methods plus method-signature changes (return type, parameters, accessibility, `static`).

**When to use it.** Analyze the same solution twice — for example before and after a refactor — and compare the two states. Both arguments are session ids; analyze the two states first.

| Parameter | Type | Required | Default | Meaning |
|---|---|---|---|---|
| `sessionA` | string | yes | — | The "left" (baseline) session. |
| `sessionB` | string | yes | — | The "right" (changed) session. |

**Response.**

| Field | Meaning |
|---|---|
| `addedTypes`, `removedTypes`, `changedTypes` | Each a capped envelope with `items`, `count`, `totalFound` and `truncated`; capped at 100 entries per list. |
| `changedTypes[].addedMethods`, `.removedMethods` | Method names added to or removed from a type that exists in both states. |
| `changedTypes[].changedMethodSignatures` | One entry per method whose signature changed, with `methodName`, `leftSignature`, `rightSignature` and the flags `returnTypeChanged`, `parametersChanged`, `accessibilityChanged`, `staticChanged`. |
| `totalChangeCount` | Sum of the three lists. |
| `isIdentical` | `true` when all three lists are empty. |

Note: types are matched by fully qualified identity, so two same-named types in different namespaces are distinguished, not conflated. A removed type whose simple name is ambiguous solution-wide is rendered by its full name. The diff is syntactic — it compares types, methods and signatures, not method bodies.

Availability: not in the default tool set — the default profile withholds the two-session comparison family from its tool menus. Expose it with the `Full Select` profile (`aicb mcp --mcp-profile mcp-profile/full`) or `AICB_MCP_TOOLS`. Not usable as a sub-query of `batch` (it needs two sessions).

### `diff_review`

**Purpose.** Review a change end to end in one call:

1. the structural diff of two analyzed sessions (before → after);
2. the blast radius of the added and changed types — for each, its fan-in usages, transitive change impact and risk, implementations, and covering tests;
3. the introduced findings — the code-quality, design-smell and layer-violation findings that exist in "after" but not in "before" (a delta, so pre-existing debt is never blamed), with a `pass` / `warn` / `block` verdict.

It is the natural "review my change" bundle: `semantic_diff` plus `review_context` plus the introduced-findings delta.

| Parameter | Type | Required | Default | Meaning |
|---|---|---|---|---|
| `sessionBefore` | string | yes | — | The "before" (baseline) session id. Must be live. |
| `sessionAfter` | string | yes | — | The "after" (changed) session id. Must be live. |
| `policy` | string | no | `null` (= `block_on_critical`) | `block_on_critical`, `block_on_warning` or `advisory`. An unknown policy is rejected, not silently treated as `advisory`. |
| `dbPath` | string | no | `null` | The active QualityProfile (producer thresholds and toggles) and the configured default layer profile of that database. Omitted: the server's default configuration database, else the default profile. |
| `recordRegressions` | boolean | no | `false` | When true, each introduced finding is also written to the database's triage log as a `regression` event on its `(producer, type, member)` scope. This is the one thing this tool does that is not read-only, which is why it is opt-in and off by default. |

Note: both sessions must be live. A session recalled from memory is rejected, because the findings delta needs equal-fidelity analysis on both sides — a recalled session lacks the live-only smell and metric facts, so a live-versus-recalled delta would falsely report all of the after state's live-only findings as introduced.

**The policy verdict.**

| Policy | Verdict |
|---|---|
| any | `pass` when no finding was introduced. |
| `advisory` | `warn` whenever a finding was introduced; never blocks. |
| `block_on_warning` | `block` when the highest introduced severity is warning or critical; otherwise `warn`. |
| `block_on_critical` (default) | `block` when the highest introduced severity is critical; otherwise `warn`. |

The findings delta honors the after session's explicit layer profile and its resolved test-detection profile; both delta sides are always generated under the same axes, so a configuration difference is never blamed as a code difference. Passing `dbPath` additionally unlocks that database's active QualityProfile and its configured default layer profile (per solution, then application-wide); an explicit layer profile passed to `analyze_solution` still wins.

**`recordRegressions` in detail.** When true, each introduced finding is recorded as a `regression` event in the database's triage log, so "this came back" survives a restart. At most one open regression is recorded per scope, so re-running the same review adds nothing. When no database is configured, or the database has never seen this solution, nothing is written — and the call still succeeds, with the reason in `regressionLog.skippedReason`; the solution row is never created here. You are asserting the direction: findings are recorded as introduced by `sessionBefore` → `sessionAfter`.

**Response.**

| Field | Meaning |
|---|---|
| `diff` | The structural diff, in the same shape as `semantic_diff` (each list capped at 100). |
| `changedSymbolReviews` | The blast-radius reviews, capped at 50 changed symbols; the envelope carries the true total and `truncated`. Each review has the fields of `review_context`. |
| `introducedFindings` | The gate verdict: `result`, `reason`, `policy` and `introduced`. |
| `regressionLog` | Present only when `recordRegressions: true` was passed: `recorded`, `alreadyOpen`, `skippedReason`. |

Availability: not in the default tool set; expose it with the `Full Select` profile or `AICB_MCP_TOOLS`. Not usable as a sub-query of `batch` (it needs two sessions).

### `review_context`

**Purpose.** Assemble review context for a set of changed symbols: for each symbol, its fan-in usages, the transitive change impact plus a risk level, the types that implement it (if it is an interface), and the test methods that likely cover it.

**When to use it.** Before reviewing or refactoring: pass the type and method names you touched — for example the symbols in a diff — and see blast radius and test coverage at a glance.

| Parameter | Type | Required | Default | Meaning |
|---|---|---|---|---|
| `sessionId` | string | yes | — | The session id returned by `analyze_solution`. |
| `symbols` | array of strings | yes | — | The changed type or method names to assemble review context for. At least one is required. |

**Response.** One review per symbol, each with:

| Field | Meaning |
|---|---|
| `symbol` | The name you passed. |
| `note` | Present when the name resolved to nothing or when the counts are the union across several same-named types. |
| `resolvedKind` | What the name resolved to: `type`, `method`, `property`, `field`, `event`, `enum_member`, `not_found`. |
| `directUsages` | Number of direct users or callers. |
| `transitiveImpact` | Number of dependents through chains. |
| `risk` | `none`, `low`, `medium` or `high`, calibrated on production fan-in only — test callers count toward the usage numbers but not toward the risk. |
| `implementations` | The types implementing the symbol, when it is an interface. |
| `invokesTotal` | How many of the covering tests are strong matches. |
| `coveringTests` | The covering test methods, each with its evidence tier. |

Note: `coveringTests` is the `find_tests_for` list under the same contract — strong `invokes` matches are ordered ahead of weak name guesses, and `invokesTotal` names how many of them are strong. Ranking by position is therefore meaningful, and you can see where the evidence stops.

Note: unlike `find_tests_for`, this tool applies no cap — a symbol with a hundred covering tests contributes a hundred rows. Budget the symbol list accordingly.

Note: the response is ordered by symbol name, not by the order you passed the symbols. Index it by `symbol`, never by request position.

Availability: in the default tool set; not usable as a sub-query of `batch` (heavyweight renderer).

### `verify_claim`

**Purpose.** Verify a structured claim about a change by diffing two analyzed sessions (baseline → changed). Returns a verdict of `confirmed`, `refuted` or `indeterminate`, with a reason and evidence.

**When to use it.** To check a promise you or an agent made about a change — for example "this change adds no public API" — against the analyzed baseline and the analyzed result.

| Parameter | Type | Required | Default | Meaning |
|---|---|---|---|---|
| `baselineSessionId` | string | yes | — | The baseline session (before the change). |
| `changedSessionId` | string | yes | — | The changed session (after the change). |
| `claimType` | string | yes | — | `no_new_api` or `symbol_removed_unused`. |
| `symbol` | string | no | `null` | Required for `symbol_removed_unused`: the symbol name the claim is about. A bare name or the qualified `Type.Member` form — the same strings `find_usages`, `impact_of_change` and `find_tests_for` resolve. |

**Claim types.**

- `no_new_api` — no types or methods were added and no method signature changed between the two states. The check is overload-aware: an added overload and a signature change on any overload are detected.
- `symbol_removed_unused` — the named symbol was removed and had no usages in the baseline's static fan-in graph.

Note — the scope of `no_new_api`: it is about additions and signature changes, so a removal does not refute it; a change set that only deletes public API is legitimately `confirmed`. Removals are therefore never silent: the reason states the boundary, and every removal the same diff records is listed as evidence, prefixed with `-`. For the removal question, ask `symbol_removed_unused`.

Note: the tool is conservative in both directions — what the diff cannot prove is never falsely confirmed and never falsely refuted. `indeterminate` is returned, with the cause named, for a name that resolves to nothing; for a property, field, event or enum member (the diff models types and methods only); and for the simple name of a removed type that the diff had to render by its full name because it is ambiguous — pass that full name instead. An unsupported claim type also returns `indeterminate`.

For `symbol` with `symbol_removed_unused`: a namespace-qualified type name is accepted even when nothing was removed — this tool resolves it against the baseline's declared type identities, which the fan-in tools do not, and the answer then names the simple name to carry on with. A dotted name that no namespace declares stays unresolved rather than falling back to whatever type carries its last segment.

**Response.** `claim`, `verdict`, `reason`, `evidence` (the change list or the carriers the verdict rests on).

Availability: in the default tool set; not usable as a sub-query of `batch` (it needs two sessions).

### `evaluate_change_set`

**Purpose.** An advisory policy gate: which code-quality, design-smell and layer-violation findings would this edit introduce? Ask before writing it. Findings are a delta against the current session, so pre-existing debt is never blamed. The change set is applied as an in-memory overlay and the amended solution is re-analyzed; nothing is written to disk and the session is untouched.

| Parameter | Type | Required | Default | Meaning |
|---|---|---|---|---|
| `sessionId` | string | yes | — | The baseline session id. |
| `changes` | array | yes | — | The proposed file changes (see below). At least one is required. |
| `policy` | string | no | `null` (= `block_on_critical`) | `block_on_critical`, `block_on_warning` or `advisory`. An unknown policy is rejected, not silently treated as `advisory`. |
| `dbPath` | string | no | `null` | The active QualityProfile (producer thresholds and toggles) and the configured default layer profile of that database. Omitted: the server's default configuration database, else the default profile. |

**The `changes` entries.** Each entry needs `filePath` (absolute, matching the analyzed documents) plus one of two content forms:

- **Anchor patch (preferred):** `oldText` and `newText` — the snippet being replaced and what it becomes. This is the shape an editor takes, and the payload is the size of the change, not of the file: the full file is rebuilt from the analyzed document. `operation` may be omitted and defaults to `modify`.
- **Full text:** `newContent` — the complete new file content — with `operation` set to `modify` or `add`. A `delete` entry takes neither content field.

Anchor patch rules:

- `oldText` must occur exactly once in the file. A missing or ambiguous anchor is an error, never a silently different edit.
- Line endings are reconciled for you.
- An empty `newText` deletes the snippet.

**The verdict.** `pass` / `warn` / `block`, following the same policy table as `diff_review`: no introduced finding is `pass`; `advisory` is `warn` whenever something is introduced and never blocks; `block_on_warning` blocks on a warning or critical; `block_on_critical` blocks on a critical.

**Response.** `result`, `reason`, `policy` and `introduced`. Each introduced finding carries `id` (the producer-level insight id), `detail` (the display line, metric included), `severity` and `locator` (the structured symbol reference for that line, when the producer emitted one).

Note: the tool is advisory — an MCP tool cannot block. The real blocking gate is the CLI `--fail-on` option. `apply_change_set` is out of scope: this tool never applies your change.

Note: the tool reports an error for an unknown `operation`, a `filePath` that is not part of the analyzed solution, or a change that cannot be assigned to a target project.

Availability: in the default tool set; not usable as a sub-query of `batch` (it runs the heaviest re-analysis).

### `compare_public_api`

**Purpose.** Compare the public API surface of two compiled .NET assemblies — a baseline `.dll` and a current `.dll` — and report the breaking changes as CPxxxx diagnostics: removed types (CP0001), removed members (CP0002), changed signatures, reduced visibility, and similar.

**When to use it.** Before shipping a library version, to check whether the new build breaks consumers of the old one.

| Parameter | Type | Required | Default | Meaning |
|---|---|---|---|---|
| `baselineDllPath` | string | yes | — | Absolute path to the baseline (old) assembly `.dll`. |
| `currentDllPath` | string | yes | — | Absolute path to the current (new) assembly `.dll`. |

No session and no solution is needed — both assemblies must be built.

Note: the tool runs the Microsoft `apicompat` command out of process. It must be installed as a local .NET tool in the repository the server runs in (`.config/dotnet-tools.json`); run `dotnet tool restore` once there. If a file is missing or the tool cannot run, the answer is an error, never a false "no breaks".

**Response.** `hasBreakingChanges`, `breakCount` and `breaks`, each break with `diagnosticId` and `message`.

Availability: not in the default tool set. Expose it by enabling the `api-surface` bundle in an MCP profile, or with `AICB_MCP_TOOLS`. Not usable as a sub-query of `batch`.

## 9.4 Insights

### `list_insights`

**Purpose.** List the code-quality, async and design-smell insights for a session — long methods, fat interfaces, unused types, missing async suffixes, many-parameter methods, and more. Each insight is aggregated per producer with a details list.

**When to use it.** As the entry point of a quality review: it tells you which kinds of findings exist for this solution and how many of each.

| Parameter | Type | Required | Default | Meaning |
|---|---|---|---|---|
| `sessionId` | string | yes | — | The session id returned by `analyze_solution`. |
| `dbPath` | string | no | `null` | The active QualityProfile (producer thresholds and toggles) and the configured default layer profile of that database. An explicit layer profile passed to `analyze_solution` wins over the database-configured one. Omitted: the server's default configuration database, else the default profile. |

**Response.** An array of summaries, one per producer that found something:

| Field | Meaning |
|---|---|
| `id` | The producer-level insight id, e.g. `quality-long-methods` — pass it to `get_insight`. |
| `featureId` | The feature identifier of the insight. |
| `title` | The producer's headline. |
| `severity` | `critical`, `warning`, `info` or `ok`. |
| `persistent` | `true` for reminder findings that are not removed by a dismissal. |
| `detailsCount` | Number of detail lines after filtering. |
| `remediationCostMinutes` | The producer's cost estimate, when it has one. |
| `suggestion` | A short, concrete fix sentence, when the producer has one. |
| `suppressed` | How many detail lines were removed by triage; `null` when nothing was filtered. |

Note: this answer is triage-filtered on both axes. Findings the solution marked as intentional (a suppression, in the database or in the git-tracked `<Solution>.aicb.json` sidecar) and findings a user dismissed as seen (in the solution record, not the sidecar) are removed, and an insight whose findings are all gone does not appear at all.

Note: `suppressed` counts what both axes removed together, so it is not a count of sidecar entries. And `title` is producer text computed before filtering, so on a partially filtered insight it still names the pre-filter total — `detailsCount` plus `suppressed` are the real split.

Note: insights that depend on facts computed live during analysis (for example the unresolved-binding findings) are absent on a session recalled from a saved snapshot.

Availability: in the default tool set; usable as a sub-query of `batch`.

### `get_insight`

**Purpose.** Get the full detail of one insight by its id, including the per-item details list.

**When to use it.** After `list_insights` told you which producer found something, to see the individual findings.

| Parameter | Type | Required | Default | Meaning |
|---|---|---|---|---|
| `sessionId` | string | yes | — | The session id returned by `analyze_solution`. |
| `insightId` | string | yes | — | The producer-level insight id, e.g. `quality-long-methods`. Discover the ids with `list_insights` or `list_insight_producers`. |
| `dbPath` | string | no | `null` | Same semantics as `list_insights`. |
| `maxDetails` | integer | no | `null` (= 20) | Cap on the returned details list. Raise it (for example to 200) for a full per-item drill-down; a `(... and N more)` marker still discloses any remainder beyond the value. Applies only to this call; omitted or `0` or less keeps the default cap of 20. |

Note: ids are case-sensitive. An unknown or misspelled id is rejected together with the known producer ids, so the error doubles as a did-you-mean list. A producer that is registered but found nothing in this session reports that explicitly — which is different from a typo, because `list_insights` lists only the producers that found something.

**Response.** The full insight: `id`, `featureId`, `title`, `description`, `actionLabel`, `severity`, `persistent`, `allowsPromptInput`, `secondaryActionLabel`, `details`, `remediationCostMinutes`, `suggestion`, `detailLocators` and `suppressedDetailCount`.

Note: triage-filtered like `list_insights`, on both axes. `suppressedDetailCount` reports the two axes added together, so it is not a count of sidecar entries. A producer silenced outright reports as "registered but 0 hits".

Availability: in the default tool set; usable as a sub-query of `batch`.

### `list_insight_producers`

**Purpose.** List the registered insight producers (id, name, group). This is a static catalog — no session is needed.

**When to use it.** To look up the exact `insightId` values for `get_insight`, including producers that found nothing in the current session and therefore do not appear in `list_insights`.

**Parameters.** None.

**Response.** An array of entries with `id`, `name` and `group`, ordered by group and then by name. `id` is the stable insight id you pass to `get_insight`; `name` is the producer's implementation name.

Note: producers that need the solution database — the public-API breaking-changes and LLM-findings producers — and the auto-compression producer are not available in the MCP server, so they do not appear in this catalog.

Availability: not in the default tool set; expose it with the `Full Select` profile (`aicb mcp --mcp-profile mcp-profile/full`) or `AICB_MCP_TOOLS`. Usable as a sub-query of `batch` (it takes no session).

---

[&larr; 8 Tool reference: facts, dead code, metrics and patterns](08-tool-reference-facts-dead-code-metrics-and-patterns.md) &middot; [Contents](README.md) &middot; [10 Tool reference: snapshots, configuration, memory and wiring &rarr;](10-tool-reference-snapshots-configuration-memory-and-wiring.md)
