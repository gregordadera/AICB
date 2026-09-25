[AICB – General Documentation](README.md) &middot; chapter 7 of 12

# 7 Profiles, master data and solution configuration

AICB is steered by named, editable configuration entries. They fall into two groups: **profiles**, which decide how something is done (which tools an MCP client sees, which quality checks run, how a document is rendered), and the remaining **master data**, the building blocks a profile or a template is assembled from. This chapter describes the entry model, the kinds that exist, how a configuration is pinned per solution, how the `.aicb.json` sidecar carries it into your repository, and in which order AICB resolves a value when several places define one.

## 7.1 Master data and profiles

### What every entry shares

All library entries share a stable identifier, a `Name`, and the list markers described below, and they use the same management gestures. Many entry types also have an optional `Description`; it is not a universal field (for example, tag schemata and test descriptions have their own type-specific content instead).

### Built-in entries, your own entries, and the pills

- A **built-in** entry ships with the application. It cannot be removed permanently.
- A **custom** entry is one you created, either with `Add` or with `Duplicate`.
- Editing a built-in and pressing `Save` does not destroy it: the entry is marked as overridden and shows the `Overridden` pill. AICB then leaves the entry alone when a later version refreshes the built-in defaults. The hint above the editor states it plainly: `Built-in profile - edits will be marked overridden. Use Restore to revert to code defaults.`
- `Restore Built-In` resets a built-in to its code defaults and clears the override/hidden flag. The tooltip reads: `Restore Built-In: reset this built-in to its code defaults and clear the override/hidden flag.` The action is available whenever the selected built-in is overridden or hidden.
- `Delete` on a built-in **hides** it instead of removing it (the `Hidden` pill appears in the list once you tick `Show hidden`). Hidden entries are invisible in the normal list; with `Show hidden` switched on they reappear and can be brought back with `Restore Built-In`. `Delete` on a custom entry removes it permanently.
- `Duplicate` creates a custom copy of the selected entry with a new identity and the name `<name> (Copy)`. This is the usual way to adapt a built-in without touching it.
- `Save` persists the editor values; `Reload` re-reads the library from the database and discards unsaved editor changes. The pages offer the same keyboard shortcuts throughout: `Ctrl+S` for Save, `Ctrl+D` for Duplicate, `Ctrl+N` for Add, `F5` for Reload.
- Each library page can `Export...` all of its entries to a JSON file and `Import...` them back. Entries marked as built-in in the import file are always skipped. For custom entries, conflicting ids can be skipped or replaced; in `Replace` mode a custom entry whose id collides with a built-in id can overwrite that built-in row, so use `Skip existing` for untrusted files.

The list rows carry up to six pills:

| Pill | Meaning |
|---|---|
| `Built-in` | The entry ships with the application. |
| `Overridden` | You edited a built-in; `Restore Built-In` returns it to its code defaults. |
| `Hidden` | A built-in you soft-deleted; visible with `Show hidden` and recoverable with `Restore Built-In`. |
| `ACTIVE` | This is the globally active entry of a family that has exactly one active member. `Apply as Active` moves the marker. |
| `DEFAULT` | This is the default entry where a family may have several defaults (detail presets, model profiles, expansion strategies, tag schemata per section type). |
| `IN USE · N` | Other master entries reference this custom entry `N` times. The pill's tooltip says references must be removed before deleting; treat it as a warning to check before you delete, because nothing in the library actually blocks the deletion. |

### Where the libraries are edited

Most libraries live on the `Settings` page, in the left sub-navigation. The 18 entries are visually grouped under the non-clickable headers `General`, `LLM & Prompts`, `Analysis`, `Rendering`, `Selection & Compression` and `Tools`. Three further master-data pages live outside `Settings`: `Templates` (under `Configuration`), `Run Templates` (under `Workspace`) and `MCP Profiles` (under `MCP`).

### The kinds of profiles and master data

| Page | What it controls |
|---|---|
| `Model Profiles` | A named LLM configuration: endpoint, model name, token limits and optional prices. `Test Connection` checks the profile against the real endpoint. Built-in profiles ship **without** prices, so cost estimates appear only after you fill in the optional pricing fields yourself. |
| `Prompts` | Reusable user-prompt presets that context templates reference. |
| `Test Descriptions` | Reusable acceptance-test descriptions for run templates. |
| `Layer Profiles` | Namespace-pattern → architecture-layer mappings. Rules are evaluated in list order, the first match wins; an empty rule list means no namespace matching at all and the role-based heuristic applies. Each profile also carries a `Layering Policy`: `Advisory` reports layer violations as warnings, `Strict` as critical findings. |
| `Exclude Namespaces` | Named lists of namespace patterns the analyzer skips. Built-in lists: `None (do not exclude any namespace)`, `BCL default (System. / Microsoft. / Windows. / Syncfusion.)` and `SAP Business One default (SAPbouiCOM. / SAPbobsCOM.)`. The BCL preset also excludes `CommunityToolkit.*`; that rule is not repeated in its shorter display name. |
| `Quality Profiles` | Switches the individual quality checks (the insight producers) on and off and holds their thresholds (method length, cyclomatic complexity, member counts), dismissal policy, action mode and optional send-template id. Debt costs are fixed by the individual producers, and the CLI gate threshold comes from `--fail-on`; neither is configured by the profile. A quality profile decides **whether** a check runs; the severity of its finding is a separate axis. |
| `Test Profiles` | Which projects count as test projects and which method attributes mark a test case. Built-in presets: `Default`, `xUnit`, `NUnit`, `MSTest`. The `Default` preset replicates the built-in heuristic exactly: a project name containing `Test`, `Tests`, `Spec` or `Specs` is a test project, and `Fact`, `Theory`, `Test`, `TestMethod`, `TestCase` mark a test case (matched as substrings, so `WindowsFact` matches through `Fact`). |
| `MD Profile` | A container with one slot per output-section type. There are 27 section types (6 of them graph sections); four are staged slots (`Class`, `Method`, `Interface`, `Enum`). In each slot you choose a tag schema. The editor has the tabs `Overview`, `Non-graph slots`, `Graph slots` and `Referenced by`. Note: the label is singular even though the page manages several profiles. |
| `Tag Schemata` | The actual rendering configuration of one output-section type: which tags, in which order, in which layout. Per section type there are several built-in schemata and optionally your own; exactly one is the default for its type. The MD profile is the mapping, the tag schema is the content. |
| `Detail Presets` | Describes **how** content is compressed at one detail level. The detail level (`Compact`, `Normal`, `Detailed`, `Source`) says how much; the preset says how. A context template has four slots, one per level. |
| `Other File Types` | A read-only reference page: the recognized file types and the four detail stages. The compression stage itself is chosen per node in the Solution Tree. |
| `Expansion Strategies` | How far the selection reaches from a marked tree node: method depth, type depth and flags. The expansion strategy decides **what goes into** the context; a compression rule decides how short it is then written. |
| `Compression Rules` | A named rule set for how strongly code blocks and sections are shortened when the token budget gets tight. |
| `Pipeline Profiles` | The token-budget trimming configuration. |
| `Constellations` | Import and export bundles of master data plus portable settings as a single JSON file. |
| `General`, `Storage`, `About` | Plain settings and information pages, not libraries. `General` holds the app-wide preferences and the global defaults; `Storage` holds the database location and backup settings. |
| `Templates` | **Context templates**: the configuration root of an export. A context template binds a prompt, an MD profile, the four detail-preset slots, the four expansion-strategy slots, an optional test description and the profile overrides. The editor sections are `Prompt & MD profile`, `Selection engine (per detail level)`, `Export content` and `Profile overrides`. |
| `Run Templates` | **Run templates**: the configuration of a run. A run template selects a context template and adds the per-run-type configuration. Three run types are available in the editor (`Manual`, `Iteration`, `Preselection`); the `Pipeline` run type is planned and not yet released, so it is not offered. |
| `MCP Profiles` | Which tools an MCP client sees, plus the render notation, the token budget and the automatic-refresh behaviour. Exactly one MCP profile is active; it drives the MCP server. |

Note: `Templates` and `Run Templates` are two different things with similar names. A context template is the configuration root of an export; a run template is the configuration of a run and merely **selects** a context template. On screen the labels are `Templates` and `Run Templates`.

## 7.2 Per-solution configuration

### The three axes in `Workspace`

Select a solution on the `Workspace` page and open the `Profiles` detail region. It shows three pickers side by side, one per configuration axis: `Layer Profile`, `Exclude Namespaces` and `Test Profile`. Each picker chooses the entry that is active for the selected solution.

- The header shows how many entries the library offers, for example `(12 available)`.
- A card marked `Built-in` is a shipped preset.
- The selected card unfolds a rule preview: a layer profile shows its rules as `pattern > Layer`, an exclusion list as `MatchType pattern`, a test profile its project rules.
- The pickers only choose. Creating and editing happens in the `Settings` libraries, and each picker points there, for example `Manage profiles in Settings > Layer Profiles.`
- Without a selected solution the pickers are inert and show the global default; the exclusion picker explains why: `Select a solution to choose its active list.`

![The per-solution profile pickers on the Workspace page](img/aicb-gui-profiles.png)

The precedence for each axis is:

| Axis | Resolution |
|---|---|
| Layer profile | per-solution choice > global default (`Settings > General > Application`, `Default layer-mapping profile`) > role-based heuristic |
| Exclusions | per-solution choice > global default (`Default namespace-exclusion list`) > built-in `BCL default` |
| Test profile | per-solution choice > globally active test profile (`Settings > Test Profiles`, `Apply as Active`) > built-in `Default` |

### First-time setup on load

Each picker carries a checkbox: `Auto-initialize via LLM on next load` for the layer profile and the exclusion list, `Auto-initialize on next load` for the test profile. A freshly registered solution starts with all three flags enabled. They are evaluated the next time you open that solution in the Context Builder — the loading happens there, not in the `Workspace` tab.

When such a solution is loaded and an armed axis is still unconfigured, AICB offers to set it up:

- If the sidecar covers the axis, it is **restored**, with no LLM call. The created entry carries the description `Restored from the .aicb.json sidecar`; its name stays `<solution> - layers`, `<solution> - exclusions` or `<solution> - tests`.
- Otherwise the axis is **generated**: with a usable default model profile, the layer rules and exclusions come from one LLM call over the solution's declared and referenced namespace lists; the test axis comes from a local heuristic over the analysis. The created entry carries `Auto-initialized on load`. If no model profile is available or no tests are detected, the corresponding proposal may remain unavailable.
- A restore asks for confirmation before it is applied. For generated layer/exclusion proposals, the LLM request is made first and the resulting proposal is then shown for confirmation; declining prevents the database change but cannot undo the request. An axis that already has a choice is never overwritten, and after a successful initialization the checkbox is cleared.

Successful first-load setup creates and activates per-solution entries in the local configuration database. It does **not** write the sidecar. Use `Workspace > Profiles > Export Config` afterwards if the configuration should travel with the repository.

`Initialize Now` in each picker applies a stored configuration immediately, without waiting for a load and without any analysis: it restores the axis from the sidecar. If there is nothing to restore — the axis is already configured, or the sidecar does not cover it — a dialog says so.

### Guided setup through an agent

Three MCP tools drive the same configuration:

- `solution_config_status` reports whether each of the three axes is initialized, which entry is active and where the active value comes from (`db`, `sidecar` or `none`). "Initialized" is an explicit marker set by `apply_solution_config`; a repository with a valid sidecar but no database row reads as initialized with source `sidecar`.
- `init_solution_config` returns the proposal material: the solution's own (declared) namespaces for layer rules, its referenced namespaces for exclusion rules, and the detected test projects plus the test-attribute markers that actually occur in the code.
- `apply_solution_config` applies a proposal: it creates custom entries, activates them, stamps the axes as initialized, and writes both the configuration database and the `<SolutionName>.aicb.json` sidecar next to the solution. It returns the sidecar path. An invalid `matchType` is rejected rather than silently corrected, and the test axis can alternatively be cloned from a built-in preset (`xunit`, `nunit`, `mstest`, `default`).

`check_solution_config_drift` checks whether a configuration still fits the code: declared namespaces that no layer rule maps, referenced namespaces that no exclusion covers, and test projects the active test profile does not match. Only a custom configuration is evaluated; a built-in preset counts as a deliberate generic choice, not as drift.

### Marking findings as intentional

A finding you decide is by design becomes a **suppression**. In the Insights panel, the eye-off button on a line records it. Its tooltip describes the effect: `Mark this finding as intentional - it stops being reported here and to the MCP. The quality gate (--fail-on / solution_metrics) still counts it. Export the solution config to share the decision via the .aicb.json sidecar.` A suppression can address a whole check, one type, or one member, and it can carry a reason. Suppressions are per solution and reach your team through the sidecar. The reset button in the Insights toolbar (`Reset what you hid`) brings dismissed findings and your own suppressions back into view, while suppressions declared in the committed sidecar stay in force.

## 7.3 The `.aicb.json` sidecar

### What it is and where it lives

The sidecar is a configuration file next to your solution file, named after it: `<SolutionName>.aicb.json`. For `MyApp.sln` the file is `MyApp.aicb.json` in the same folder. It is meant to be committed to your repository, so the solution configuration is versioned with the code. Headless hosts consume the supported fallback axes directly; the desktop app can restore its profile content into the local database.

The file carries the **content** of a configuration — patterns, names, rules — and no database identifiers. That is what makes it portable: it is not tied to the database of one machine.

### The complete schema

```json
{
  "layerRules": [
    { "pattern": ".Application.", "matchType": "Contains", "layer": "Application" }
  ],
  "layeringPolicy": "Strict",
  "exclusions": [
    { "pattern": "System.", "matchType": "StartsWith" }
  ],
  "testProjectRules": [
    { "pattern": ".Tests", "matchType": "EndsWith" }
  ],
  "testAttributeNames": [ "Fact", "Theory" ],
  "autoInit": { "layer": false, "exclusions": false, "test": true },
  "suppressions": [
    { "producer": "quality-long-methods", "type": "LegacyImporter", "member": "Import", "reason": "generated" }
  ],
  "analyzePreferredTfmOnly": true
}
```

| Key | Form | Meaning | When omitted |
|---|---|---|---|
| `layerRules` | array of `{ pattern, matchType, layer }` | Namespace pattern → architecture layer. The first matching rule wins. | The layer axis is unset. `matchType` defaults to `Contains`. |
| `layeringPolicy` | `"Advisory"` or `"Strict"` | How a layer violation is reported. `Advisory` = warning, `Strict` = critical (acts as a gate). | `Advisory`. The key is only written when the value is not `Advisory`, so an advisory file stays byte-identical to older files. |
| `exclusions` | array of `{ pattern, matchType }` | Namespace patterns the analysis skips. | The exclusion axis is unset. `matchType` defaults to `StartsWith`. |
| `testProjectRules` | array of `{ pattern, matchType }` | Rules that classify a **project name** as a test project; any match counts. | The test axis is unset. `matchType` defaults to `Contains`. |
| `testAttributeNames` | array of strings | Attribute names that mark a method as a test case, matched as substrings. | The test axis is unset. |
| `autoInit` | `{ layer, exclusions, test }` booleans | The "auto-initialize on next load" opt-ins per axis, so the intent travels with the repository. The database record remains the primary source; this is the fallback for a fresh clone. | Written only when at least one flag is `true`. |
| `suppressions` | array of `{ producer, type?, member?, reason? }` | Triage decisions. `producer` alone silences a whole check, `producer` + `type` every hit on one type, `producer` + `type` + `member` exactly one member. `reason` is free text for reviewers. | No suppressions are declared. |
| `analyzePreferredTfmOnly` | `true` or `false` | Analysis scope: analyze only the preferred target framework's instance of a multi-targeted project. | The scope is not declared. An explicit `false` is a deliberate statement and is written back as `false`. |

The allowed `matchType` values are `Contains`, `StartsWith`, `EndsWith` and `Exact`; on reading they are matched case-insensitively. `apply_solution_config` rejects an invalid value; in a hand-edited file an unparsable value falls back to the axis default.

Note: `layeringPolicy` belongs to the layer axis, and `testProjectRules` plus `testAttributeNames` together are the test axis. That makes eight keys but six axes: layer, exclusions, test, auto-init, suppressions and analysis scope.

### The analysis scope, written by hand

`analyzePreferredTfmOnly` is the one key with no wizard and no control in the graphical interface, so it is written by hand:

```json
{ "analyzePreferredTfmOnly": true }
```

A multi-targeted project (`<TargetFrameworks>net8.0;netstandard2.0</TargetFrameworks>`) is loaded once per target framework, so every source file is analyzed N times. With this key set, AICB analyzes only the newest target framework's instance of each project, and the export contains one copy of each project instead of N.

The symbol inventory is unchanged — every symbol a query can name is still there. Two things do change: a fan-in edge whose only source is a non-preferred instance is lost, so `find_usages`, `impact_of_change` and `call_graph` can report a smaller blast radius; and transitive side-effect facts shift. The default is off, and on a solution without multi-targeting the setting does nothing at all.

### Creating and updating the file

- In the graphical interface, select the solution in `Workspace` and use `Export Config`. It writes the active layer profile, exclusion list, test profile, your triage decisions and the auto-init flags to the sidecar. If the file already exists you are asked before it is overwritten. The confirmation reminds you to commit it. Headless analysis auto-discovers the sidecar without `--db-path`, but applies each field according to the per-axis matrix below rather than treating the whole file as one profile.
- `Import Config` reads the layer rules and exclusions from a selected JSON/sidecar file and applies those two axes to the selected solution: it creates and activates a custom layer profile and exclusion list. It does not import the sidecar's test profile, suppressions, auto-init flags or analysis-scope key.
- `apply_solution_config` writes the configuration database and the sidecar together and returns the path.
- You can edit the file by hand; it is designed for that.

Note: `aicb init` does not write the sidecar, and neither does `init_solution_config` — the latter only gathers proposal material. The file is written by `Export Config`, by `apply_solution_config`, or by you.

### Reading and writing rules

- Reading is all-or-nothing. A missing, unreadable or malformed file counts as "no sidecar file" — never as a partial configuration. A file whose `layerRules` is a string is a broken file, not "the layer axis is unset".
- The one deliberate exception is `suppressions`: it is read entry by entry, and a malformed entry costs only that entry. A suppression optimizes what a reader has to look at, while a broken layer or exclusion rule would silently change what the analysis reports, so those still fail the whole file.
- Comments and trailing commas are accepted, as are differently-cased key names and enum names. Numeric enum values are rejected, so `"layeringPolicy": "7"` does not silently become something.
- There are no key aliases. `layer_rules` is not `layerRules`: an unknown key configures no axis, and a file with no axis at all is not treated as a sidecar.
- A file with content on none of the five content axes (layer, exclusions, test, suppressions, analysis scope) loads as "no sidecar". The `autoInit` flags ride along with a content-bearing file; a file containing only flags is neither written nor read.
- Writing **replaces** the whole file. Axes that are not present are omitted, so a file that uses only the original two axes stays byte-identical to the older format. `analyzePreferredTfmOnly` is written back exactly as it came in, including an explicit `false`. The write is atomic (a temporary file, then a replace), UTF-8, indented and camelCase.

### Which axis wins

The sidecar does not outrank everything — the precedence differs per axis:

| Axis | What wins in the graphical interface | What wins in `aicb analyze` |
|---|---|---|
| Layer profile | explicit/per-solution database choice > global default > role-based heuristic. Sidecar rules participate only after they are restored into the database | `--layer-profile` > database (per solution > global default) > sidecar > role-based heuristic |
| Namespace exclusions | per-solution database choice > global default > built-in `BCL default`. Sidecar rules participate only after they are restored into the database | database (as soon as any database is available) > sidecar > none |
| Test profile | database (per solution > global) > built-in default | database (per solution > global) > built-in default — the sidecar's test axis is not part of this chain |
| Auto-init flags | database record, mirrored into the sidecar for a fresh clone | not evaluated |
| Suppressions | database, shared through the sidecar export | not evaluated |
| Analysis scope | sidecar only | sidecar only |

Note: if a database is available at all, the sidecar's exclusions are not consulted, even when the database list is empty. The sidecar is the database-free fallback.

Note: the analysis scope is not part of the file-set hash with which AICB decides whether a stored snapshot can be reused. `aicb analyze` therefore prints a note when a snapshot is reused although the scope may have changed since it was written, and points you to `--force`.

## 7.4 How settings are resolved

Five separate resolution paths exist. They are independent of each other; confusing them is the fastest way to look in the wrong place.

### Where settings live

Application settings come from two sources:

1. `app-settings.json` — it holds only three things: the storage settings (database path, base path, backup configuration), the recent solution paths and the recent database paths.
2. The configuration database — everything else, stored as key/value entries.

The split exists because the database path must be known before the database can be opened. The practical consequences:

- Every value that is neither in the file nor in the database falls back to the built-in default. The defaults have a single source, so a default is never defined twice.
- On the very first start, before the database schema exists, the built-in defaults are used and the settings are re-read once the schema is ready.
- A settings file that cannot be read does not crash the application: AICB continues with defaults and preserves a copy of the unreadable file next to it as `app-settings.json.corrupt-<timestamp>`. Because the file also holds the database path, the notice tells you that your sessions and solutions may look missing and where the preserved copy is.
- Note: the file always lives at `%APPDATA%\AIContextBuilder\app-settings.json`. The `App settings file` field under `Settings > Storage` is stored but does not move it.
- Note: settings that were removed in a later version stay in the database as inert entries. They are never read or written again, so a value you find there may simply do nothing.

### Which profile is active

For the profile families, the first **resolvable, non-hidden** tier wins. A tier that is set but points at a hidden (soft-deleted) or deleted entry is skipped and the **next** tier applies — not the default. Only the last tier ignores the hidden marker, because it has to return something.

| Profile | In the graphical interface | In MCP / headless |
|---|---|---|
| Pipeline profile | context template's `Pipeline profile` slot > globally active pipeline profile > built-in default | additionally the active MCP profile's template first |
| Quality profile | context template's `Insights profile` slot > globally active quality profile > built-in default | additionally the active MCP profile's template first |
| Test profile | per-solution test profile > globally active test profile > built-in default | identical |
| MCP profile | globally active MCP profile > built-in default (exactly one is active) | identical |
| Compression rules | globally active compression-rules profile > built-in default; a context template can override it through its slot | identical |
| Context template | globally active context template > `default` | the MCP profile's slot template for the facet > the MCP profile's template > globally active context template |

Two consequences are worth knowing:

- Hiding an entry that an active context template still points at is silent: from the next render on the next tier applies, with no error and no log entry.
- On the shipped default configuration, changing the globally active quality, pipeline or compression profile in the graphical interface does **not** change MCP answers. All built-in MCP profiles point at the `AI Optimized` context template, and that template pins the built-in defaults for those three slots, so the template tier wins before your global setting is read. This is what pinning a template slot means, not a defect. What does move MCP answers is the corresponding slot of the template your active MCP profile names, or a different MCP profile.

### The MCP server configuration file and environment variables

The MCP server has its own precedence:

```
built-in defaults  <  aicb.mcp.json  <  environment variable
```

`aicb.mcp.json` lives at `%APPDATA%\AIContextBuilder\aicb.mcp.json` and is only read, never written. If it is missing or unreadable it is ignored and the server starts on the built-in defaults. Its keys:

| Key | Meaning |
|---|---|
| `toolSpec` | Which tools the server exposes: `"lean"`, `"all"`, or a comma-separated list of tool group names. Not set = the active profile's pool. |
| `sessionCache.ttlMinutes` | How long an analyzed session is kept, in minutes, sliding from the last access. |
| `sessionCache.maxSessions` | How many sessions are held at the same time. |
| `sessionCache.sweepMinutes` | Interval of the background cleanup, in minutes. |

Environment variables override the file for the process they are set in:

| Variable | Effect |
|---|---|
| `AICB_MCP_TOOLS` | Tool selection: `all` exposes every tool including the opt-in infrastructure tools; literal `lean` exposes the complete 72-tool lean core; a comma-separated list of tool group names narrows the selection; unset = no override, so the active profile's pool applies. |
| `AICB_MCP_SESSION` | Session cache, for example `ttlMinutes=120,maxSessions=4,sweepMinutes=15`. |
| `AICB_MCP_AUTO_REFRESH` | Overrides the automatic-refresh mode for this server process (`off`, `reactive`, `proactive`). |
| `AICB_MCP_ERROR_TEXT` | Set to `off` to record only the exception type in the server's usage report, not the message. |
| `AICB_MCP_DEBOUNCE_MS` | How long the source-change watcher waits before it reacts, in milliseconds. |
| `AICB_MCP_STALENESS_WINDOW_MS` | The window in which a session counts as stale, in milliseconds. |
| `AICB_MCP_LOAD_WAIT_MS` | How long a tool call waits at the solution load gate before it is told what is holding it, in milliseconds. |
| `APPDATA` | Determines the base path and therefore all storage locations. |

For the three `*_MS` values, an unparsable or non-positive value falls back to the built-in default. Three further variables tune the analysis itself: `AICB_DESIGN_TIME_BUILD_CACHE` (`0`, `off` or `false` disables the design-time build cache; an absolute path relocates it), `AICB_ANALYZE_PREFETCH_DEPTH` (how many builds to keep in flight; `0` disables the prefetch) and `AICB_ANALYZE_NULLABLE_FLOW` (`1`, `true`, `yes` or `y` keeps nullable flow analysis in the semantic model).

### The source badge on a field

Where a value can come from several tiers, a small pill next to the field shows where the effective value came from. In the `Sections` panel of the Context Builder it has three states, with the tooltip `Source of the active Tag Schema selection for this slot`:

| Badge | Meaning |
|---|---|
| `default` | The built-in default. |
| `profile` | The value from the active MD profile. |
| `override` | A per-run override you made in this panel. |

Behind this sits a general four-level ladder, from lowest to highest precedence: built-in code default → template slot → solution/session override → per-node override.

### Token budget

Two resolution paths exist for a token budget:

- Template-aware MCP renders (`export_markdown`, `prepare_task`): explicit `budget` parameter > the active MCP profile's token budget > the context template's token budget > the global pipeline profile. No budget is enforced only when none of those sources supplies one and trimming is disabled; a trimming profile such as Aggressive Trimming can still impose its global budget.
- The slice tools (`get_context`, `explain_symbol`, `pack_for_task` and the other tools with a `budget` parameter): explicit `budget` parameter > the active MCP profile's token budget > a default ceiling of 10,000 tokens.

Both MCP paths floor the value at 8,000 tokens. The active MCP profile's token budget is the only setting both MCP paths honour. The graphical interface instead passes the current `Max MD size` slider value (or no cap when `No limit` is selected). The CLI has no explicit budget option; when rendering through a run template it uses that context template's pipeline-profile override, or the globally active pipeline profile when no override is set.

### When a change takes effect

- Most settings take effect as soon as you save them. The library pages and the per-solution pickers stay in sync live.
- A change to `Base path` under `Settings > Storage` requires an application restart. The same holds for the LLM retry settings under `Settings > General > LLM Retry`.
- The MCP server reads the active MCP profile and the automatic-refresh mode once at start, so restart the server for a change to apply — the tool list and the server instructions are delivered when a client connects. The `AICB_MCP_AUTO_REFRESH` environment variable overrides the mode for one process. If the active profile changed since the server started, `server_info` reports the pending change. `aicb mcp --mcp-profile <id>` pins which profile a server process uses; the pin is process-local and writes nothing back.
- A session that has already been analyzed keeps the configuration it was analyzed with (see "Sessions and staleness"). `refresh_session` deliberately reuses the session's layer profile, exclusion list and analysis scope instead of re-reading the sidecar, so editing the sidecar does not change a running session. Analyze the solution again, or use `refresh_remembered`, which returns a new session and reads the sidecar again.
- The run-confirmation threshold under `Settings > General > Run Confirmation` is read at each run, so a change applies immediately. Note: the value `0` means that **every** run asks for confirmation; there is no "never ask" value. Enter a very high number if you want to switch the pre-flight confirmation off.

---

[&larr; 6 Templates, rendering and markup analysis](06-templates-rendering-and-markup-analysis.md) &middot; [Contents](README.md) &middot; [8 Insights: the code quality catalog &rarr;](08-insights-the-code-quality-catalog.md)
