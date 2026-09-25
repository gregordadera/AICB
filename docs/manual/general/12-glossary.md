[AICB – General Documentation](README.md) &middot; chapter 12 of 12

# 12 Glossary

This glossary explains the terms this manual uses. UI labels, tool names, parameters, environment variables and file names are set in `code` and quoted exactly as they appear on screen or in a file. Where a term carries more than one meaning in the product, the entry says so and gives the qualified form to use. Terms marked **not yet released** exist only as placeholders in the data format and cannot be used yet.

## 12.1 A – B

**`aicb.acb`** — The single application database (SQLite). It holds the master data, the known solutions, sessions, snapshots, runs and the local MCP usage record. The file name must end in `.acb`; any other extension is refused, both when opening and when creating a database. Its location is the path set under `Settings > Storage` (default `{BasePath}\user-data\aicb.acb`). See the file table under "Terms that are easy to confuse".

**`aicb.mcp.json`** — The **server** configuration of the MCP for headless operation, read once at server start. It sits with the server data (default `<ApplicationData>/AIContextBuilder/aicb.mcp.json`) and sets the exposed tool set and the session cache. Precedence: defaults < `aicb.mcp.json` < environment variable (`AICB_MCP_TOOLS`, `AICB_MCP_SESSION`).

**`.aicb.json`** — The **sidecar** of a solution: a git-tracked JSON file next to the `.sln`, named `<SolutionName>.aicb.json`. It can carry layer rules and strictness (`layeringPolicy`), namespace exclusions, test-project rules and test-attribute names, suppressions, auto-init flags and the preferred-target-framework scope. Consumers apply these fields differently: database-free headless analysis uses the layer/exclusion fallback and analysis scope, but does not resolve its test profile from the sidecar; suppression-aware reading tools separately combine their documented database and sidecar sources. The desktop app restores profile content into its database. The file carries configuration only—no analysis results, sessions, snapshots or credentials. `Export Config` on the `Workspace` page and the MCP tool `apply_solution_config` write it; `Import Config` and `solution_config_status` read it. `aicb init` does not touch it.

**`.mcp.json`** — The **client** configuration of your agent tool: it tells the agent which server to start. `aicb init` can write an entry for it, but the file belongs to the agent, not to aicb. Not to be confused with `aicb.mcp.json`.

**Agent harness** — The environment your AI agent runs in and that has its own configuration: Claude Code, Codex, OpenCode. `aicb init` detects it and can write skills and a symbol guard into it. `aicb init --hooks` accepts `auto` (default), `none`, `all`, `claude-code`, `codex` or `opencode`.

**Analysis** — The read-only pass in which aicb loads a solution with Roslyn and derives its symbol graph and facts. Without an analysis there is nothing to export and no session-bound MCP tool can answer; session-less tools such as `server_info`, `list_skills`, `usage_report`, `docs` and `list_mcp_profiles` remain available. The analysis never modifies your source files.

**Auto-refresh** — How the MCP server keeps a session's analysis in step with the code on disk. Three modes: `Off` (nothing happens by itself; a drifted session is disclosed and repaired only when `refresh_session` is called), `Reactive` (before a reading tool answers, the server re-analyzes if needed — the shipped default), `Proactive` (a file watcher starts the re-analysis once saving has gone quiet). The mode is set per MCP profile on the `Session` sub-tab.

**Axis** — In this manual, one of the three per-solution configuration axes: layer mapping, namespace exclusions and test detection. Other dimensions have their own names (detail level, severity, facet).

**`batch`** — An MCP tool that runs several **read-only** queries in one round trip. A sub-query that fails does not take the others down, and a result too large to fit is omitted with a pointer to the direct call. Not every tool can be batched: a tool that mutates, holds state, recurses or is otherwise unsuitable is refused, and the refusal names the reason. At most 16 sub-queries per call.

**Built-in** — A master entry that ships with the product. A built-in can be edited; editing marks it `Overridden` and keeps the original, which `Restore Built-In` brings back.

**Bundle** — An opt-in group of tools outside the task facets. The product ships one, `api-surface` (the public-API compatibility tools). Enable it per MCP profile or through `AICB_MCP_TOOLS`.

## 12.2 C

**Card** — A single entry in a list, for example in a master-data list or the snapshot list.

**Chip** — A clickable filter or switch: the five layout-mode chips in the Context Builder header, or the severity filters in the `Insights` tab. A non-clickable marker on a card (`Built-in`, the run type) is a **pill**.

**Circular dependency** — A chain of namespaces that leads back to its own start (A → B → A). The C# compiler allows it, so it is a modularity smell, not an error. `detect_circular_dependencies` finds them.

**`Compression Rules`** — A named **rule set** (not a single rule) that decides how strongly code blocks and sections are shortened when the token budget is tight: scoring multipliers by accessibility, role and path, a tiebreaker order, and the trimming mode `Greedy` or `Sweep`. One entry is therefore a set of rules, not "a compression rule". Page `Compression Rules`; a context template can reference its own rule set. The output section `COMPRESSION_LEGEND` is always rendered and explains the notation the rules produce.

**Constellation** — An exportable and importable **bundle of master data**: several library entries in one JSON file, validated against a schema. Managed on the `Constellations` settings page; `aicb import --file <file.json> --mode SkipExisting|Replace` applies one (add `--preview` for a dry run).

**`Context Builder`** — The working area for one solution: the `Solution Tree`, the six configuration panels (`Prompt`, `Sections`, `Graph Selection`, `Selection Engine`, `Test Description`, `Export Output`) and the generated document. One tab per solution.

**Context document** — The output of an export: a dense Markdown document in the `AI-Builder-MD` format, written to a `.md` file and meant to be handed to a language model. The notation inside is either tag or YAML (see `Format`).

**Context template** — The configuration root of an export: which prompt and which MD profile it uses, which detail preset and expansion strategy apply at each of the four detail levels, which test description, compression rules, pipeline profile and quality profile are attached, and its own switches (line numbers, quality metrics, config files that may contain secrets, layout legend). The settings page is `Templates`. Not to be confused with a run template (`Run Templates`).

## 12.3 D – G

**Dead code** — A symbol that nothing in the **analyzed scope** references. Note: reflection, dependency injection resolved by string, XAML and external callers are invisible to the analysis, so "no callers" is a lead to verify, not proof. `find_dead_code` lists suspects.

**Detail level** — The four-step axis that says **how much** of a symbol enters the document: `Compact`, `Normal`, `Detailed`, `Source`. It is resolved per node in the `Solution Tree`; `Source` behaves as `Detailed` plus the source-code block.

**Detail preset** — A master entry that describes **how** the content of a detail level is written. A context template has one slot per level. Rule of thumb: the level says how much, the preset says how. Page `Detail Presets`; the slots are under `Selection engine (per detail level)` in the template editor.

**Drift** — A measured divergence between two states that should match. `server_info` reports `CONFIG DRIFT` (the active MCP profile changed after the server started), `VERSION DRIFT` (the running binary is older than the database it reads) and `ANALYZER DRIFT` (the analysis code moved ahead of the build). `check_solution_config_drift` checks whether a solution's configuration still fits its code. Source staleness is a different thing; see **Staleness**.

**Edge** — A modeled relationship between two symbols: calls, is called by, depends on, implements, inherits from, XAML names a type, XAML binds a member.

**`Exclude Namespaces`** — A named list of namespaces that the analysis skips. Note the label is identical in both places it appears: `Settings > Exclude Namespaces` is the library editor, `Workspace > Profiles > Exclude Namespaces` is the per-solution picker.

**Exit code** — The value the command line returns. Seven values with a fixed meaning:

| Code | Meaning |
|---|---|
| 0 | Success |
| 1 | User error (invalid arguments, missing files) |
| 2 | Runtime error (unexpected exception) |
| 3 | Cancelled (`Ctrl+C`) |
| 4 | Database migration failed |
| 5 | MSBuild not found (`aicb analyze` only) |
| 6 | Quality gate failed (`aicb analyze --fail-on` only; the document is still produced) |

**Expansion strategy** — Controls **how far** the selection reaches from a marked node into the graph: a strategy mode (`Reachable`, `Select`, `Frontier`), a method depth and a type depth, eight switches (callers, callees, used-by members, inheritance hierarchy, interface implementations, created types, used types, injected dependencies) and four stop conditions (exclude framework types, exclude external assemblies, exclude test classes, exclude generated code), plus an optional total node limit. A context template has one slot per detail level. Not to be confused with compression: expansion decides **what gets in**, compression how briefly it is then written.

**Export** — The act of writing the context document, and the document itself. Other kinds of output carry their object: master-data export, session export, sidecar export, usage-report export.

**Fact** — A measured property of a symbol that the analysis derives from the code: cyclomatic complexity, lines of code, called methods, used types, side effects. A fact is measured; a semantic axis is resolved and carries a provenance.

**Facet** — The one task axis of the MCP. Nine values: `general`, `exploration`, `refactoring`, `debugging`, `review`, `testing`, `documentation`, `architecture`, `performance`. A facet has three effects: it picks a context template, it composes a tool menu, and it contributes a guiding sentence. You address it per call with the `facet` parameter of `prepare_task`, `pack_for_task` and `export_markdown` — a call parameter, not a server state.

**False positive** — A finding that the analysis reports and that is not one. Each producer has documented false-positive classes; where a producer knows one, the finding names it. Treat a finding as a lead to verify.

**Fan-in** — The set of places that name a symbol: "who calls this?". `find_usages` lists the direct references (one level); `impact_of_change` adds the transitive closure. The output section `METHOD_USED_BY_GRAPH` is the rendered fan-in of a method.

**`File-Set-Hash`** — A checksum over the set of a solution's source files. If it has not changed, an existing snapshot can be reused instead of re-analyzing the solution; a plain `refresh_session` compares it before it re-runs the analysis.

**`Findings`** — The findings parsed out of the **language model's answer**, shown in the `Findings` region of the `Reasoning` panel. aicb's own quality findings are `Insights` — the product's tab is named `Insights` for exactly this reason. In this manual, `Findings` means only the model-derived kind.

**Format** — The inner notation of the context document: `Tag` (the established AI-Builder tag Markdown) or `YAML` (idiomatic YAML, the product default). It is a notation of the same content, not a different selection, and the file keeps its `.md` name either way.

## 12.4 H – L

**Handshake** — The text the MCP server hands a client when it connects: what the server can do, how to use it, which conventions apply. It is composed of blocks, and a block whose tools the active profile does not expose is left out.

**Hook** — A script that your agent environment runs at a defined point. `aicb init --hooks` installs the aicb symbol guard as a hook; `install_agent_hooks` does the same for a project that is already set up.

**Impact** — The **transitive** fan-in closure: everything that could be affected by a change to a symbol, including consumers a compiler does not check. `impact_of_change` reports it with a `risk` level. Note: the risk is measured on the symbol's fan-in, not on the semantics of your specific edit — a `high` rating on a purely additive change is expected and is not a stop sign. `find_usages` lists only the direct references.

**Insight** — A finding of the built-in code-quality analysis: a place where aicb found something worth mentioning, with a severity, a category and one or more sites. Shown in the `Insights` tab and returned by `list_insights` / `get_insight`; also rendered into the output section `QUALITY_FINDINGS`.

**`inPool` / `outOfPool` / `uncatalogued`** — The pool states of MCP tools. The **pool** is what the active profile exposes right now. `inPool.core` are the tools in every profile, `inPool.extras` the rest of the exposed set, `outOfPool` tools that exist but are not exposed (a name there proves the tool is real), and `uncatalogued` tools that no menu and no bundle names and that only `AICB_MCP_TOOLS` can expose. `list_skills` reports the current split; the server registers 82 tools in total.

**Layer** — An architecture layer such as `Domain`, `Application` or `Infrastructure`.

**Layer profile** — A named rule set that maps types to layers and sets how strictly a violation is judged: `Advisory` (violations are warnings; the default for new profiles) or `Strict` (violations are critical). Pages: `Settings > Layer Profiles` is the library, `Workspace > Profiles > Layer Profile` is the picker for one solution.

**Library** — The collection of master entries (the library pages under `Settings`). Not an assembly and not a NuGet package.

## 12.5 M – N

**`Manual`** — Four different things carry the word: the run type `Manual` (one call per trigger), the snapshot type `Manual` (created and named by you), a manual override on a tree node, and the provenance `Manual` of a value you typed yourself.

**Master data** — The editable library entries an export is assembled from. Every master entry has the same shape: an id, a name, a description, built-in/overridden/hidden flags, an active and a default marker, and a reference count. The settings pages are the library editor; the matching pickers under `Workspace > Profiles` only choose, they do not create.

**MCP** — Model Context Protocol, the protocol over which an AI agent calls the tools of an external server. `aicb mcp` starts that server.

**MCP profile** — A named combination of: which tools a client sees, which facets are active, how the output is shaped, how the session behaves, and which handshake text goes along. Its own `MCP Profiles` page is in the main sidebar group `MCP`, with the sub-tabs `Facets`, `Tools`, `Output`, `Session` and `Instructions`; it is not a Settings page. Four profiles ship with the product (`Default`, `Full Select`, `Refactoring Focus`, `Debugging Focus`). Pin one for a server process with `aicb mcp --mcp-profile <id>`; `list_mcp_profiles` lists the ids.

**MCP session** — An analysis result held in the server process, addressed by a `session_id`, with no name and no database row; it is gone when the process ends. Every tool that takes a session also accepts the absolute `.sln` path directly and analyzes on first use — that is `Self-Init`, and it makes `analyze_solution` optional. The cache is keyed by `.sln` path within one server process, with a sliding expiry (default 90 minutes, at most 8 sessions); a second process analyzes from scratch. `AICB_MCP_SESSION` tunes `ttlMinutes`, `maxSessions` and `sweepMinutes`.

**MD profile** — A container with one slot per output-section type (27 types, six of them graph types; four are staged slots for classes, methods, interfaces and enums), and in each slot a tag schema. The navigation entry is literally `MD Profile` (singular), even though the page manages several profiles. The MD profile is the assignment, the tag schema is the content.

**`measure`** — An MCP tool that reports how large a read-only query's answer would be, in tokens, without returning the answer. It still runs the query, so it saves context, not time.

**Member** — A part of a type: method, property, field, event, constructor.

**Migration** — A numbered step that advances the database schema. Missing steps run at the first start after an update, so a database is migrated when you first open it with a newer version. Note: this is one-way — an older build cannot read a database that a newer build has already migrated. If you run two versions side by side, give one of them its own database path under `Settings > Storage`.

**Mode** — Two kinds are common: the layout mode (the five chips in the Context Builder) and the auto-refresh mode (`Off`, `Reactive`, `Proactive`).

**Model profile** — A named LLM configuration: provider and kind, endpoint, model name, token limits, temperature, context window and prices per million tokens. The `Test Connection` button checks the profile against the real endpoint. Page `Model Profiles`.

**Namespace** — A C# namespace. In the `Solution Tree` it sits between the project and its types.

**Navigation** — The left sidebar of the main window. It has four groups: `Quick Access` (`Start`), `Workspace` (`Context Builder`, `Workspace`, `Run Templates`), `Configuration` (`Templates`, `Settings`) and `MCP` (`MCP Profiles`, `MCP Usage`). Clicking an entry opens it as a tab.

**Node** — One entry of the `Solution Tree`: solution, project, namespace, type or member.

## 12.6 O – R

**Omission** — The handshake rule that leaves out a block whose tools the active profile does not expose. Do not use the word for the separate case in which a `batch` result is too large to fit: that one is reported as omitted with a pointer to the direct call.

**Overlay** — A modal layer over the work area: the loading overlay while a solution is analyzed, and the export overlay while a document is rendered. The window stays responsive behind it.

**Overridden** — A built-in master entry that you have edited. The original is kept and `Restore Built-In` brings it back. Both `Built-in` and `Overridden` appear as pills on the card.

**Page** — A whole surface with its own header, reached from the sidebar (`Layer Profiles`, `General`, `MCP Usage`). A register inside a page is a **sub-tab**; a bounded block inside a page with its own heading is a **panel**.

**Panel** — A delimited block inside a page or tab with its own heading, for example `Prompt`, `Sections` or `Graph Selection`.

**Pill** — A non-clickable marker on a card or row: `Built-in`, `Overridden`, the run type. A clickable one is a **chip**.

**Pipeline profile** — Token budget and trimming behavior of the export, plus two switches for snapshot tabs. `BudgetedTrimmingEnabled` is off by default; `MaxTokenBudget` defaults to 60,000 tokens (floor 8,000) and `MaxOvershootPercent` to 50 (clamped to 0–1000). Page `Pipeline Profiles`. Note: do not confuse it with the run type `Pipeline` (not yet released).

**Pool** — The set of MCP tools the active profile delivers right now. See `inPool` / `outOfPool` / `uncatalogued`.

**Profile** — Seven different things carry the name:

| Label | What it controls | Where |
|---|---|---|
| `Layer Profiles` | type → architecture layer, plus strictness | `Settings` library + per-solution picker |
| `MD Profile` | one slot per output-section type, with the chosen tag schema | `Settings` |
| `Quality Profiles` | which insight producers run | `Settings` |
| `Test Profiles` | what counts as a test project and as a test method | `Settings` library + per-solution picker |
| `Pipeline Profiles` | token budget and trimming behavior of the export | `Settings` |
| `Model Profiles` | LLM endpoint, token limits, prices | `Settings` |
| `MCP Profiles` | which MCP tools a client sees, plus session behavior | `Settings` |

**Project** — A `.csproj` inside the solution. A project that targets several frameworks appears in the analysis once per framework.

**Prompt** — Three related things. (a) The master entry `Prompt` (a prompt template) that a context template references. (b) The five fields of the `Prompt` panel in the Context Builder — `System Role`, `Instructions`, `Goal / Task (User Prompt)`, `Constraints / Rules`, `Additional Context` — from which the text actually sent is assembled; the first two are initialized from the referenced prompt template, the other three are per-session. (c) The assembled text itself, which is what goes to the model.

**Provenance** — The recorded origin of a resolved semantic value, printed in the output document so you can tell a measured value from a guess: `fact` (a deterministic Roslyn fact), `ai` (asserted by the developer in a `/// <ai>` comment), `verified-absent` (the developer declared "none"), or `inferred` (a heuristic). A semantic axis without provenance is unknown, not empty.

**Quality gate** — The option that makes `aicb analyze` fail when findings at or above a severity are found: `--fail-on "<expression>"` (for example `critical>0 OR ce-max>50`). The document is still produced; the exit code is 6. An empty expression is rejected rather than passing silently. This is the option that makes aicb useful in a CI pipeline.

**Quality profile** — Switches the insight producers on and off — it decides which kinds of finding are produced at all, together with their thresholds, whether findings are dismissable, and which action mode the `Apply` button uses (`DirectApply` or `ConfirmDialog`). Not to be confused with severity: the profile decides **whether** a check runs, the severity how heavy its result weighs.

**Reasoning** — The panel that shows what happened in a run: what the model answered, what it thought, which tools it called, which `Findings` were parsed out of the answer, and the evaluation. 

**Run** — A pass in which aicb sends an assembled context to a language model and collects the answer. Labels such as `Run Templates`, `Active Run` and the layout mode `Run` keep the word. Not to be confused with the traversal depth of the tree expansion.

**Run template** — The configuration of a run: which run type, which context template, a description, and an optional suggested text for the goal field of a manual run. Page `Run Templates`. A run template **selects** a context template; it is not one.

**Run type** — What a run does per trigger. The released type is `Manual` (one model call per trigger, or a pure Markdown render). Two further types are **not yet released**: `Iteration` (one call per tree node of the selection) and `Preselection` (the model selects first, then the actual processing runs in two or three stages). A fourth value, `Pipeline`, exists in the data format as a placeholder for a planned multi-step run with optional loops and splits; it is **not yet released** and cannot be selected.

## 12.7 S

**Section** — A named part of the generated context document, for example `SPEC`, `META`, `QUALITY_FINDINGS` or `LAYER_MAP`. A labelled group on a settings page is a *settings section*, not a document section.

**Self-Init** — The behavior that makes `analyze_solution` optional: every MCP tool that takes a session also accepts the absolute `.sln` path instead and analyzes the solution on first use. The returned `session_id` is reused for all further, cheap calls.

**Semantic axis** — A derived value on a type or method — role, layer, domain, responsibility, side effects and others — resolved from several sources. The provenance travels with it in the output document, so you can see whether a value was measured, asserted or inferred.

**Session** — A named, saved working state of a solution that you can reopen and continue: the tree selection, the detail-level overrides per node, the prompt text, and the template as it was when you saved. `Save Session` (or `Ctrl+S` in the Context Builder) always opens the name dialog, prefilled for an existing session. Auto-Save and the non-interactive save-before-close path update it without asking. The `Sessions` sub-tab of the `Workspace` page lists them. See "Terms that are easy to confuse" for the difference from an MCP session.

**`session_id`** — The handle of an MCP session. You normally do not have to manage it: pass the `.sln` path and let `Self-Init` do the rest.

**Sidecar** — The git-tracked configuration file next to a solution: see `.aicb.json`.

**Side effect** — What a unit touches outside its own memory. The vocabulary is closed and has eight values: `io`, `network`, `database`, `serialization`, `logging`, `cache`, `messaging`, `unknown`. You meet them in `find_by_side_effects(effect: …)`, in the output section `SEMANTICS` and in the quality-profile checkbox `Side-effect concentration (methods mixing 3+ effect categories)`. Worth remembering: the classification judges by **contact, not by topic** — `Path` and `MemoryStream` carry no `io` effect, while `File` and `FileStream` do. A cache a type holds in memory is not an outside-world effect.

**Skill** — An instruction file that an agent loads. `aicb init --skills=all` writes the aicb context skill plus the review pair and the usage check; the default `context` writes only the context skill.

**Snapshot** — A frozen analysis of a solution at a point in time. Runs are pinned to a snapshot so that a later re-analysis cannot change a finished run. A snapshot is created automatically on every fresh analysis (type `Auto`) or by you via `Create Manual Snapshot` (type `Manual`). `Max snapshots per solution` limits how many automatic snapshots are kept; snapshots you saved yourself are never deleted and do not count towards the limit. `Diff Two Snapshots` compares two of them. The `Snapshots` sub-tab of the `MCP Usage` page shows something else — see "Terms that are easy to confuse".

**Solution** — A Visual Studio solution: the `.sln` file plus everything it contains. It is the unit aicb analyzes; without a solution nothing happens. You meet it in the `Solutions` list, the `Solution Tree`, the CLI option `--sln` and the MCP parameter `sessionId`, which accepts an absolute `.sln` path. Note: a solution entry in the database is the stored record with its active profile assignments — say "the solution entry" when you mean that.

**`Solution Tree`** — The tree on the left of the Context Builder: solution → project → folder/file → type → member. A namespace is not a tree level. Here you choose what goes into the document.

**`Solutions`** — The list on the left of the `Workspace` page. The word appears only there.

**Staleness** — The state in which the analysis graph is older than the source files, because something was edited since the analysis. A session-bound answer from a stale session carries a `staleness` trailer (a JSON member or Markdown comment); a current answer carries none. Note the difference from **incompleteness** (`incompleteProjects`): staleness means the source moved on, incompleteness means the project references could not be resolved because the solution was not built. A `not_found` on a type you just wrote is staleness and is cured by an ordinary refresh; a plausible but too short fan-in that discloses `incompleteProjects` needs `refresh_session(force: true)` after a restore or build.

**Style** — A cross-cutting working guideline that adds text to the server instructions without changing the tool set. The product ships two: async/concurrency correctness and security review. A style that belongs to one kind of work sits on that facet instead.

**Sub-tab** — A register **inside** a page or surface: `Facets` in the MCP profile editor, `Details` in the Context Builder. The strip at the top of the window is the tab strip; a sidebar entry opens a page as a tab.

**Suppression** — A single insight that you deliberately hid. In the `Insights` tab you mark a line as intentional; that action stores the suppression in the local database. It reaches the committed sidecar's `suppressions` array only when you explicitly run `Export Config`; the reading path combines both sources. The reading surfaces (`Insights`, `list_insights`, `get_insight`) honor it; the quality gate and `solution_metrics` keep counting it. Do not confuse it with dismissing a finding as seen: a dismissal is a local database record, while an exported suppression can become a shared decision.

**Symbol** — A C# type or member. A glyph on screen is an `Icon`.

## 12.8 T – Z

**Tab** — An entry in the top strip of the window, and the surface it shows. Closing one with `Ctrl+W` closes the innermost first: an open file before its solution tab, a solution tab before the page tab.

**Tab strip** — The row of tabs at the top of the window.

**Tag schema** — The actual render configuration of one output-section type: which marks are used, in which order, in which layout. Per section type there are several built-in schemata and optionally your own; exactly one is the default. Page `Tag Schemata`; the `Sections` panel picks one per output section for a run. The MD profile is the assignment, the tag schema is the content.

**`Templates`** — The settings page that manages context templates (see `Context template`). Do not confuse it with `Run Templates`, which manages runs.

**Test profile** — Makes test detection pinnable: which projects count as test projects (`TestProjectRules`, matching the project name with `Contains`, `StartsWith`, `EndsWith` or `Exact`) and which method attributes mark a test case (`TestAttributeNames`, matched as a substring). Built-in presets are `default` (project name contains `Test`, `Tests`, `Spec` or `Specs`; attributes `Fact`, `Theory`, `Test`, `TestMethod`, `TestCase`), `xunit`, `nunit` and `mstest`. Pages: `Settings > Test Profiles` is the library, `Workspace > Profiles > Test Profile` is the per-solution picker.

**Token budget** — The upper limit on how large the generated document may become. When it is reached, compression and trimming take effect. You meet it on the `Max MD size` slider in the Context Builder header, in the template editor as `Token budget (MCP render)`, in the pipeline profile, and in the confirmation before a run. The floor is 8,000 tokens; the global default is 60,000. Precedence: explicit call parameter > MCP profile > template > global pipeline profile.

**Tool** — A single callable function of the MCP server, for example `find_usages`. The word also appears in the protocol concepts `tools/list` and `tools/call`.

**Type** — A class, struct, interface, record or enum. The third level of the `Solution Tree`.

**Unit** — Everything with an **executable body**, and therefore everything the analysis can judge: not only declared methods, but every property, indexer and event accessor with a body, every constructor including the member initializers it runs, top-level statements and Razor components. An auto-property accessor (`get;`) has no body and is not a unit. You meet the word in MCP answers as a counter (`methodsScanned`, "over N units") and in hits such as `Type.Name.get`. The difference from "method" matters: a private method that is called only from a setter would look uncalled if accessors were not units of their own.

**Usage recording** — The local record of which MCP tool was called how often, how fast and with which outcome. It is visible and deletable on the `MCP Usage` page (six sub-tabs: `Tools`, `Calls`, `Notes`, `Errors`, `Clients & protocol`, `Snapshots`) and through `usage_report`. Nothing of it leaves your machine — it stays in the local database. With `AICB_MCP_ERROR_TEXT=off` you reduce the one free-text error field to the exception type. There is no switch to turn the recording off; you can clear the data at any time.

**Usage snapshot** — An imported usage report kept beside your own live numbers on the `MCP Usage` page. Imported reports are never merged into the live data; you can compare one against the current numbers and delete it again. The export writes the same JSON that `usage_report` returns, so a report can travel between machines.

**Workspace** — The page that manages all known solutions. On the left is the `Solutions` list; on the right are four sub-tabs: `Overview`, `Profiles`, `Sessions` and `Snapshots`. Note that `Workspace` is also the name of the sidebar group that contains this page, so say "the `Workspace` page" when the distinction matters.

## 12.9 Terms that are easy to confuse

Four pairs cause most of the confusion in this product. Read these first; the table after them covers the rest.

**`Insights` vs `Findings`** — `Insights` are aicb's own quality findings: the `Insights` tab, `list_insights` and `get_insight`, and the output section `QUALITY_FINDINGS`. `Findings` are the findings parsed out of the language model's answer, shown in the `Findings` region of the `Reasoning` panel. In this manual, `Findings` always means the model-derived kind.

**`Session` vs MCP session** — A `Session` is the named, saved working state of a solution that you reopen and continue. An **MCP session** is an in-memory analysis result inside the server process, addressed by a `session_id`, with no name and no database row. This manual writes `MCP session` whenever both could be meant. There is a third place the word appears: the `Session` sub-tab of the MCP profile editor, which configures auto-refresh (`Off`, `Reactive` or `Proactive`) and its scope, not a session. The headless session cache is configured through `aicb.mcp.json` or `AICB_MCP_SESSION`, not in that GUI tab.

**`Snapshot` vs usage snapshot** — A `Snapshot` is a frozen analysis of a solution at a point in time; runs are pinned to one. The `Snapshots` sub-tab on the `MCP Usage` page holds imported usage reports instead. Call the second one a **usage snapshot**.

**`Workspace` vs `Solutions`** — `Workspace` is the sidebar group and the page inside it; the page title is `Workspace`. `Solutions` is the list on the left of that page and the only place the word appears. This manual writes "the `Workspace` page" and "the `Solutions` list".

| Term alone | Means | The other meanings are called |
|---|---|---|
| `Session` | the saved working state in the GUI | `MCP session`; the `Session` sub-tab of the MCP profile editor |
| `Snapshot` | the frozen analysis of a solution | usage snapshot |
| `Findings` | findings parsed from the model's answer | `Insights` (aicb's own) |
| `Template` | — ambiguous | context template, run template |
| `Profile` | — ambiguous | layer profile, MD profile, quality profile, test profile, pipeline profile, model profile, MCP profile |
| `Mode` | — ambiguous | layout mode, auto-refresh mode |
| `Axis` | the solution configuration (layer, exclusions, test) | detail level, severity, facet |
| `Card` | a list entry | sub-tab (the register of an editor) |
| `Section` | a named part of the context document | a settings section (a labelled group on a settings page) |
| `Symbol` | a C# type or member | `Icon` (a glyph on screen) |
| `Library` | the master-data collection | assembly, NuGet package |
| `Manual` | — ambiguous | run type `Manual`, snapshot type `Manual`, manual override, provenance `Manual` |
| `Run` | a pass that sends context to a language model | traversal depth of the tree expansion |
| `Level` | the detail level | the font size under `Settings > General` |
| `Export` | the context document | master-data export, session export, sidecar export, usage-report export |
| `Block` | a handshake block | the `staleness` trailer of an answer |
| `Drift` | — ambiguous | `CONFIG DRIFT`, `VERSION DRIFT`, `ANALYZER DRIFT`; staleness |
| `Slot` | a rendering or template slot | the `slot` parameter alias (an older name for `facet`) |
| `Bundle` | the opt-in tool group (`api-surface`) | the rendered context document |
| `Dispatch` | running several queries in one `batch` or `measure` round trip | interface dispatch (a C# call through an interface) |
| `Omission` | the handshake rule for unexposed tools | an oversized `batch` result omitted with a pointer |

Four file names look alike and mean four different things:

| File | What it is | Where it lives |
|---|---|---|
| `aicb.acb` | the application database (SQLite) | where `Settings > Storage` points, default `{BasePath}\user-data\aicb.acb` |
| `.aicb.json` | the **sidecar** of a solution (layer, exclusions, test detection, suppressions) | next to the `.sln`, committed to version control |
| `aicb.mcp.json` | the **server** configuration of the MCP for headless operation | with the server data |
| `.mcp.json` | the **client** configuration of your agent (what it starts) | in your project; `aicb init` adds the `aicb` entry |


Finally, three product terms that look like each other but are not:

- `Layer Profiles` (plural, the library under `Settings`) against `Layer Profile` (singular, the picker for one solution). The same singular/plural rule separates `Test Profiles` from `Test Profile`. `Exclude Namespaces` is spelled the same in both places, so use the location to distinguish them: `Settings > Exclude Namespaces` against `Workspace > Profiles > Exclude Namespaces`.
- `Run Templates` (the configuration of a run) against `Templates` (the context templates). A run template selects a context template.
- `Pipeline Profiles` (the token budget and trimming behavior of an export) against the run type `Pipeline`, which is not yet released.

---

[&larr; 11 Troubleshooting](11-troubleshooting.md) &middot; [Contents](README.md)
