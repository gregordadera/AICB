[AICB – General Documentation](README.md) &middot; chapter 5 of 12

# 5 The context document (AI-Builder-MD)

The context document is the deliverable of AIContextBuilder: a single text file that describes one analyzed .NET solution in a structured, compact form. It is written for language models, but it is deliberately readable for humans as well. Instead of raw source code, it contains the solution's structure (projects, files, types, members), its architecture (dependency and call graphs), the resolved semantics and developer annotations, plus the supporting build and configuration files.

This chapter explains the file itself: its name, the two notations it can be written in, every section it contains, the legends that decode it, the detail and compression levels, and the token budget that limits its size.

## 5.1 The file

The document is written as one UTF-8 file per solution. `{SolutionName}.analysis.ai.md` is the automatic exporter convention; the GUI's `Save as...` action proposes `{SolutionName}-context.md`, while CLI and MCP exports use the path supplied by the caller. The extension stays `.md` regardless of the notation used for the content.

The same solution can be rendered more than once with different settings - for example through a different context template, a different MD profile or a different token budget. Each render produces a complete document of its own.

![A rendered context document in the desktop app's MD Input tab](img/gui-context-md.png)

## 5.2 The two notations

The content of the document can be written in two notations. The information, the section order and the field values are identical in both; only the way they are written changes.

| Notation | Value | Description |
|---|---|---|
| Tag | `tag` | The established AI-Builder format: every block is wrapped in explicit `<TAG>` and `</TAG>` lines, fields are written as `Key: Value`, lists as `- item`. |
| YAML | `yaml` | The same content as idiomatic YAML. This is the product default. |

Select the notation with the `--format tag|yaml` option of the CLI, with the `format` parameter of the MCP tool `export_markdown`, or through the output format configured on a run template or on the active MCP profile. The GUI exposes the same switch.

Two details are worth knowing:

- `Tag` is the numeric zero value of the notation setting and therefore the technical fallback wherever no notation is configured. It is **not** the product default - that is `yaml`.
- The CLI rejects an unknown `--format` value with an error message (`--format must be 'tag' or 'yaml'`). In `export_markdown`, an unrecognized `format` value falls back to the tag notation; because any supplied value counts as explicit, it also overrides the notation configured on the active MCP profile.

Note: YAML is a re-notation, not a different selection of content, and it is not promised to be cheaper. Whether it needs fewer tokens than the tag notation depends on the individual document; both notations carry exactly the same information.

### How the YAML notation is shaped

The YAML rendering follows a fixed set of rules:

- The frontmatter fields (`type`, `title`, `description`) become top-level keys.
- Every block becomes a mapping key in lower camel case: `<SOLUTION>` becomes `solution:`, `<AI_CONTEXT_SPEC>` becomes `aiContextSpec:`, `<BUILD_AND_UI_FILES>` becomes `buildAndUiFiles:`.
- Repeated blocks become sequences under a plural key: `PROJECT` becomes `projects:`, `FILE` becomes `files:`, `CLASS` becomes `classes:`, `INTERFACE` becomes `interfaces:`, `ENUM` becomes `enums:`, `METHOD` becomes `methods:`.
- A list item that carries a confidence marker in the tag notation (`- IWidgetStore [high]`) becomes a nested mapping with `name` and `confidence` keys.
- Multi-line content (source code, the format contract, a verbatim file body) becomes a block scalar introduced by `|`. When the first content line of such a block already starts with a space, the explicit indicator `|2` is used so the indentation stays unambiguous.
- Block attributes such as `compact="near_flow"`, `lines="10-20"` or `path="App/Widget.cs"` are carried over as regular fields.
- The format contract of the tag notation is not split into YAML keys. It is a description of a different notation, so it is preserved as one string field.

Values that could be misread as numbers or booleans are quoted so they stay strings - for example `version: "1.0"`. The transformation is lossless: no section, no field and no code line is dropped.

## 5.3 The document header

Every non-lean document starts with three blocks that describe the document itself.

### YAML frontmatter

```
---
type: ai-builder-context
title: Acme.Solution
description: Roslyn-generated AI-Builder-MD context for the Acme.Solution solution.
---
```

The frontmatter makes the document indexable for tools that read YAML frontmatter. `title` is the solution name (or `solution` when the name is empty). The frontmatter is written when the document is not lean **and** the format contract section is actually part of the document - if that section is switched off by a profile, the frontmatter is omitted with it.

### AI_CONTEXT_SPEC

`AI_CONTEXT_SPEC` is the format contract. It tells the reader how the rest of the document is written and is present in full exports:

- `Purpose` and `Goals`: what the document is for.
- `Rules` 1-4: every block uses explicit opening and closing tags; fields follow `Key: Value`; lists use `- item`; the document starts with the YAML frontmatter followed by `AI_CONTEXT_SPEC`.
- `AliasRules` 5-7: `PATH_LEGEND` maps type names to short aliases; aliases may replace type names **only** in ten named sections; `PATH_LEGEND` always contains the full mapping. See "PATH_LEGEND and alias rules" below.
- `GraphSemantics`: `A -> B` means "A depends on B"; `A implements B` means "A implements interface B"; `A <- B` means "A is used by B".
- `DependencyConfidenceSemantics`: the meaning of the confidence markers `[high]`, `[medium]` and `[low]`.
- One semantics paragraph per included graph section (for example `LayerMapSemantics` or `MethodUsedByGraphSemantics`).
- `SemanticModel`: which sub-blocks a type block and a method block may contain, where the values come from, and that empty blocks and empty fields are omitted.
- `Sections`: the list of sections contained in **this** document.

Note: the `Sections:` list is document-specific, not a static contract. It lists only the sections that this particular render produced, so a document with a switched-off section or without XAML files names fewer sections than a full export. Use it as a table of contents for the document in front of you, not as the definition of the format.

### AI_CONTEXT_META

`AI_CONTEXT_META` identifies the producer and counts the content:

```
<AI_CONTEXT_META>
Generator: AIContextBuilder
Version: 1.0
Format: AIContextMarkdown
Solution: Acme.Solution
GeneratedAt: 2026-09-21T09:15:42Z
AnalyzerVersion: 0.5.464.xxx
Projects: 2
Files: 2
Types: 4
Classes: 2
Interfaces: 1
Enums: 1
Methods: 5
Properties: 2
Constructors: 1
DistinctDependencies: 3
</AI_CONTEXT_META>
```

| Field | Meaning |
|---|---|
| `Generator` | Always `AIContextBuilder`. |
| `Version` | The document format version. |
| `Format` | Always `AIContextMarkdown`. |
| `Solution` | The name of the analyzed solution. |
| `GeneratedAt` | The render time in UTC. |
| `AnalyzerVersion` | The version of the analysis engine that produced the model. |
| `Projects` | Number of projects in the document. |
| `Files` | Number of source files. |
| `Types` | Total number of types. |
| `Classes` | Types that are neither interfaces nor enums. |
| `Interfaces` | Number of interface types. |
| `Enums` | Number of enum types. |
| `Methods` | Number of methods. |
| `Properties` | Number of properties. |
| `Constructors` | Number of constructors. |
| `DistinctDependencies` | Number of distinct type dependencies across all types. |

When the document covers only part of the solution - a slice, or a render reduced by the token budget - the counts are written as `X of Y`, for example `Types: 4 of 37`. A plain number means the document covers everything.

### AI_PROMPT

If the export was given a prompt, the prompt is reproduced as bullet lists under the headings `SystemRole`, `Instructions`, `Goal`, `Constraints` and `AdditionalContext`. Each field is split at line breaks; leading `-` or `*` characters are removed so the result is a clean list. Fields without content are omitted, and the whole section is omitted when no prompt was set.

## 5.4 The sections at a glance

The following table lists the sections in the order they appear in a full export. The right-hand column names the conditions under which a section can be missing.

| # | Section | Content | Can be missing when |
|---|---|---|---|
| 1 | `SPEC` | Format contract (see above). | The section slot is switched off. |
| 2 | `META` | Producer, version, solution, counts. | The section slot is switched off. |
| 3 | `AI_PROMPT` | The export prompt. | The slot is off or all five prompt fields are empty. |
| 4 | `QUALITY_HOTSPOTS` | Most complex methods, most coupled types, namespaces furthest from the main sequence. Opt-in. | Quality metrics are not enabled (the default). |
| 5 | `PATH_LEGEND` | Type name to alias mapping. | The slot is off, layout is disabled, or there are no aliases. |
| 6 | `COMPRESSION_LEGEND` | Explanation of the compression modes, the provenance vocabulary and the caller lists. | Never - always rendered. |
| 7 | `DOMAIN` | Solution name and its core components with their roles. | The section slot is switched off. |
| 8 | `ARCHITECTURE_FLOW` | High-level relations between important components. | The slot is off or the graph is not enabled. |
| 9 | `INTERFACE_RELATIONS` | Interface implementation and usage relations. | The slot is off or the graph is not enabled. |
| 10 | `ENTRY_POINTS` | Primary runtime and orchestration entry methods. | The slot is off or the graph is not enabled. |
| 11 | `ENTRY_POINT_FLOW` | Method-level execution flows starting at the entry points. | The slot is off or the graph is not enabled. |
| 12 | `SERVICE_DEPENDENCY_GRAPH` | Architecture-relevant service and workflow dependencies. | The slot is off or the graph is not enabled. |
| 13 | `LAYER_MAP` | Type to inferred layer assignment. | The slot is off or the graph is not enabled. |
| 14 | `CLASS_DEPENDENCY_GRAPH` | Architecture-relevant class and interface dependencies. | The slot is off or the graph is not enabled. |
| 15 | `ROLE_GRAPH` | Role-to-role dependencies such as `Controller -> Service`. | The slot is off or the graph is not enabled. |
| 16 | `METHOD_GRAPH` | Method-level call dependencies. | The slot is off or the graph is not enabled. |
| 17 | `METHOD_USED_BY_GRAPH` | Reverse method usage relations. | The slot is off or the graph is not enabled. |
| 18 | `ENUM_SUMMARY` | List of all enum types. | The slot is off or the solution has no enum. |
| 19 | `FILE_INDEX` | Directory map: per file its project, relative path, type and method count. | The slot is off or no project contains a file. |
| 20 | `BUILD_AND_UI_FILES` | `.csproj` of every included project and the relevant `.xaml` views. | The disk scan finds nothing. |
| 21 | `AUXILIARY_FILES` | Config, build, documentation and resource files. | No file passes the inclusion rule. |
| 22 | `SOLUTION` | Start of the nested structure tree. | Never - the head block is written even for a solution without projects. |
| 23 | `PROJECT` | One project of the tree. | Part of the tree; omitted when there is no project. |
| 24 | `FILE` | One source file of the tree. | Part of the tree; omitted when a project has no file. |
| 25 | `CLASS` | One class (including records and structs). | Part of the tree. |
| 26 | `INTERFACE` | One interface. | Part of the tree. |
| 27 | `ENUM` | One enum. | Part of the tree. |
| - | `QUALITY_FINDINGS` | Code-quality findings, symbol by symbol. | The document is lean, or the finding list is empty. It has no profile slot and trails the document. |

A section can also be absent because the document mode removed it (see "Document modes"). The quality findings section is deliberately not part of the ordered section list; it is appended after the tree in a full export, and sorted alphabetically in the ordinal ordering described below.

### Section order

The sections follow a reading order that is oriented on the use case: format descriptions and legends first, then the architecture graphs, then the file index and supporting files, then the type tree. An alternative ordering sorts the sections alphabetically by their section id. It exists to maximize the shared prompt prefix when a provider caches prompt tokens across calls. Note: the alphabetical ordering is implemented but not yet released as a user option - the standard export, GUI and MCP paths all use the reading order.

## 5.5 The architecture graphs

The ten graph sections describe the solution's architecture without repeating source code. Their edges use a small, consistent vocabulary:

- `A -> B` - A depends on B (architecture flow, service graph, class graph, method graph).
- `A <- B` - A is used by B (method used-by graph).
- `A implements B` - A implements interface B (interface relations).
- `A => Layer` - the inferred layer of type A (layer map).
- `Role -> Role` - a role-to-role dependency such as `Service -> Interface` (role graph).

Concrete examples of the rendered lines:

```
<ARCHITECTURE_FLOW>
Flows:
- CMS -> CBC
- MCUC -> ICMS
</ARCHITECTURE_FLOW>

<INTERFACE_RELATIONS>
- OR implements IO
</INTERFACE_RELATIONS>

<LAYER_MAP>
- IO => Domain
- OS => Application
</LAYER_MAP>

<ROLE_GRAPH>
- Service -> Interface
</ROLE_GRAPH>

<ENTRY_POINTS>
- DR.RunAll()
- LPUC.ExecuteAsync(string, CancellationToken)
</ENTRY_POINTS>

<METHOD_GRAPH>
- CBC.BlendAdditive(RgbColor, RgbColor) -> CNH.Normalize(RgbColor)
</METHOD_GRAPH>

<METHOD_USED_BY_GRAPH>
- CNH.Normalize(RgbColor) <- CBC.BlendAverage(RgbColor, RgbColor)
</METHOD_USED_BY_GRAPH>
```

`ENTRY_POINTS` lists the entry methods with their parameter list. `ENTRY_POINT_FLOW` adds the direct first hop for each of them, in the form `Caller(params) -> Callee(param types)`. `METHOD_GRAPH` and `METHOD_USED_BY_GRAPH` list complete call edges; the method graph mode configured on the active detail preset decides how much of the signature each side carries. Outside its `Full` mode, calls within one type are omitted - the graph shows calls *between* types, so a chain that delegates internally first appears without that hop. `ENTRY_POINT_FLOW` deliberately keeps those first-hop edges.

An empty graph is rendered as a single `- none` line, so you can always tell "the section was rendered and is empty" from "the section is not in the document".

A full export enables all ten graphs. The bounded architecture overview enables the eight macro graphs and leaves out `METHOD_GRAPH` and `METHOD_USED_BY_GRAPH`; for method-level structure, query a specific symbol instead.

## 5.6 DOMAIN, ENUM_SUMMARY and FILE_INDEX

`DOMAIN` names the solution and lists its core components as `- {name} [{role}]`, one line per type that has a resolved role:

```
<DOMAIN>
Name: Acme.Solution
CoreComponents:
- IO [contract]
- OR [entity]
- OS [service]
</DOMAIN>
```

`ENUM_SUMMARY` lists the names of all enum types under an `Enums:` header. It is only written when the solution actually contains an enum.

`FILE_INDEX` is the directory map of the document. Each file contributes a block with four lines:

```
<FILE_INDEX>
[Project: Acme.Domain]
**RelativePath:** src/Domain/Order.cs
Types: 3
Methods: 4
</FILE_INDEX>
```

`Types` counts the types declared in the file, `Methods` the declared methods of those types.

## 5.7 BUILD_AND_UI_FILES

`BUILD_AND_UI_FILES` brings the build and UI files of the analyzed code into the document. It is always on and relevance-filtered:

- The `.csproj` of every included project is always written.
- A `.xaml` file is written only when it is tied to the included code slice - either its code-behind type is part of the document, or an included type references or binds it.

Each file becomes a `FILE` block whose attributes name the relative path, the file type and both sizes, followed by the file content:

```
<FILE path="Sample.UI/MainWindow.xaml" type="xaml" original_bytes="180" compressed_bytes="90">
... content ...
</FILE>
```

The content is compressed according to the detail level resolved for that file. A `.xaml` file defaults to the `Detailed` level, a `.csproj` to `Normal`; both keep everything that carries meaning while removing formatting noise. The `Source` level writes the raw file. Per-file levels can be set in the solution tree; without an explicit setting the file type default applies.

## 5.8 AUXILIARY_FILES

`AUXILIARY_FILES` collects the non-code supporting files of the analyzed projects. The following extensions are considered: `.json`, `.xml`, `.config`, `.resx`, `.props`, `.targets`, `.md`, `.txt`, `.editorconfig`, `.yml`, `.yaml`. Files inside `bin`, `obj` and `.vs` folders are skipped.

The inclusion rule is a hybrid:

- **Project-wide structure and build files are always included**: `.props` and `.targets` files, `.editorconfig`, `global.json` and `README.md`.
- **Other loose configuration and documentation files are included only when the export prompt names them** - by file name (for example `config.json`) or, when it is specific enough, by its stem (`config`). The match is case-insensitive and must hit a whole word, so `config` does not match `reconfigure`. All five prompt fields are searched.
- **Potentially sensitive configuration files are gated behind their own opt-in** (`IncludeSensitiveConfigFiles`, default off). This subset contains every `*.config` file (for example `web.config`, `app.config`, `nuget.config`) as well as files whose name is or starts with `appsettings`, `launchSettings`, `secrets`, `compose` or `docker-compose` in one of the formats `.json`, `.yaml` or `.yml`. These files routinely carry connection strings, API keys or credentials, so they are never included unless you enable the option explicitly.

Each included file is written as a `FILE` block with the same attributes as above. The default detail level is `Source`, which writes the raw content; per-file levels from the solution tree are honored.

## 5.9 The solution tree

`SOLUTION`, `PROJECT`, `FILE` and the type blocks form one nested tree:

```
<SOLUTION>
Name: Acme.Solution
Projects: 2
<PROJECT>
Name: Acme.Domain
<FILE>
Name: Order.cs
Path: src/Domain/Order.cs
<CLASS>
...
</CLASS>
</FILE>
</PROJECT>
</SOLUTION>
```

The `SOLUTION` head block always names the solution and the number of projects; the tree is then nested one level deeper per project, file and type. `PROJECT` carries the project name and, when known, the project file path. `FILE` carries the file name, the path relative to the solution root and - when set - the namespace.

If a file's code is part of the selection, a `FILE_CODE` block with the complete file content is written inside the `FILE` block, fenced as C#.

## 5.10 The type blocks

A type becomes one `CLASS`, `INTERFACE` or `ENUM` block. The type kind decides which sub-blocks are possible; every sub-block that has no content is omitted.

| Sub-block | CLASS | INTERFACE | ENUM | Content |
|---|---|---|---|---|
| header | yes | yes | yes | Type name, layer and role. |
| `TYPE_INFO` | yes | yes | yes | Objective metadata extracted from the source. |
| `SEMANTICS` | yes | yes | yes | Resolved semantic values with their provenance. |
| `SUMMARY` | yes | yes | yes | XML documentation summary. |
| `AI_TAGS` | yes | yes | yes | Developer-provided annotations. |
| `STRUCTURE` | yes | yes | yes | Members and declaration facts. |
| `DEPENDENCIES` | yes | yes | no | Type dependencies grouped by relation. |
| `METHODS` | yes | yes | no | The method blocks. |
| `USED_BY` | yes | yes | yes | Types in this document that use this type. |
| `TYPE_CODE` | yes | yes | yes | Verbatim source of the type. |

The header renders the type name in bold, followed by the layer and role as bracket fields when they are resolved:

```
<CLASS>
**TypeName:** Order
[Layer: Domain]
[Role: Entity]
```

### TYPE_INFO

`TYPE_INFO` contains facts taken directly from the source, without interpretation. Fields without a value are omitted; flag fields are written only when they are true.

| Field | Meaning |
|---|---|
| `Name` | Simple type name. |
| `FullName` | Namespace-qualified name. |
| `AssemblyName` | Name of the assembly the type is compiled into. |
| `Kind` | Type kind (class, interface, enum, ...). |
| `Accessibility` | Declared accessibility. |
| `Modifiers` | List of declaration modifiers. |
| `IsStatic`, `IsAbstract`, `IsSealed`, `IsGeneric` | Flags, written only when true. |
| `TypeParameters` | List of generic type parameters. |
| `Attributes` | List of applied attributes. |
| `BaseTypeFullName` | Base type. |
| `InterfaceFullNames` | Implemented interfaces. |
| `SourceFilePath` | File the type is declared in. |

### SEMANTICS and provenance markers

`SEMANTICS` contains the resolved semantic values of a type or method: `Role`, `Layer`, `Domain`, `Context` and - for types - `Responsibility`. Layer values honor the active layer-mapping profile, so they agree with `LAYER_MAP` in the same document.

The last line of the block states where the values came from:

```
<SEMANTICS>
Role: entity
Layer: Domain
Source: Resolved
</SEMANTICS>
```

`Source: Resolved` means the values come from the resolved analysis. When no per-field provenance was recorded, the marker stands alone. When the fields of a block have different origins, the line breaks them down:

```
Source: Resolved (role=inferred, layer=ai)
```

The four tokens are:

| Token | Meaning |
|---|---|
| `fact` | Deterministic, taken from the source. |
| `ai` | Explicitly asserted by a developer annotation. |
| `inferred` | Heuristic guess - low confidence, may be wrong. |
| `verified-absent` | The author confirmed that the field is empty. |

Fields confirmed as empty are listed after the breakdown, for example `Source: Resolved (; verified-absent: sideEffects)`. Treat `inferred` values as hints, not as ground truth, and do not rely on them where correctness matters.

A compact `SEMANTICS` block (see "Method compression modes") writes the values as one pipe-separated line and carries an optional `src:` line with the same vocabulary. A compact block without a `src:` line is fully inferred.

### SUMMARY and AI_TAGS

`SUMMARY` reproduces the XML documentation summary of the type or method. A single-line summary is written as one bold line; a multi-line summary becomes a heading followed by a fenced block, so the original formatting survives.

`AI_TAGS` contains the annotations a developer attached to the element - the explicit semantic metadata that takes precedence over heuristic inference. Types can carry `Role`, `Layer`, `Context`, `Domain`, `Priority`, `Complexity`, `SideEffects`, `Stability`, `Responsibility`, `Pattern`, `DependencyType`, `Determinism`, `DataAccess`, `Interaction`, `Validation` and `ErrorHandling`; methods carry `Role`, `Layer`, `Context`, `Domain`, `Priority`, `Complexity`, `SideEffects` and `Stability`. Only the fields that are set are written, and the block is omitted entirely when nothing is annotated.

### STRUCTURE

`STRUCTURE` describes the declaration itself. The header fields are `Access`, `BaseType`, `TypeKey` (the fully qualified identity) and `Ifaces`. Depending on the type kind, member lists follow:

```
<STRUCTURE>
Access: public
BaseType: Acme.Domain.Entity
TypeKey: Acme.Domain.Order
Ifaces:
- IOrder
Ctors:
- Order()
Props:
- Guid Id
- OrderStatus Status
</STRUCTURE>
```

Constructors appear under `Ctors:`, properties under `Props:`, fields under `Fields:` and enum members under `Members:`. Each member line carries its accessibility and, where applicable, modifiers such as `static`, `readonly` or `const`. When the detail settings ask for inferred values, a property or field with an initializer also shows `= <initializer>`; with the additional value-source annotation the line names where the value comes from, for example `(from property-init)`, `(from field-init)` or `(from const-definition)`. Method parameters with a default value show `= <value>` and, when enabled, the annotation `(from method-param-default)`.

### DEPENDENCIES

`DEPENDENCIES` groups the type's relations into five lists:

| Group | Meaning |
|---|---|
| `Implements` | Interfaces the type implements. |
| `DependsOn` | Dependencies the type receives or holds. |
| `Contracts` | Data- and contract-shaped dependencies (models, DTOs, records, enums). |
| `Uses` | Types the type uses without depending on them structurally. |
| `UnknownDependencies` | Names that could not be resolved to a type in the solution. |

Every entry carries a confidence marker in square brackets:

```
<DEPENDENCIES>
Implements:
- IOrder [high]
UnknownDependencies:
- ICustomer [low]
- IRepository [low]
</DEPENDENCIES>
```

`[high]` marks a strong, architecture-relevant relation - typically a direct implementation, a constructor dependency or a central operational dependency. `[medium]` marks a relevant but less central relation, typically recurring usage. `[low]` marks a weak or data-oriented relation - typically DTO, model or enum usage, a contract-only transfer or an uncertain fallback. The markers are relative heuristics for the reader, not formal proof levels.

Note: `DEPENDENCIES` and `METHODS` are written for classes and interfaces even when they end up empty; the other sub-blocks are omitted when they have no content.

### METHODS

`METHODS` contains one `METHOD` block per method, plus a comment when a type declares methods that are not rendered in this document - for example in a slice that projected the type without its methods. Depending on the detail settings, a method is written in one of the compression modes described below.

### USED_BY

`USED_BY` lists the types (or methods, inside a method block) that use this element, one name per line:

```
<USED_BY>
- Acme.OrderService
- Acme.OrderController
</USED_BY>
```

This list is a statement about the document, not about the whole solution. It names only the callers that are rendered in this document; a caller outside the slice is absent, and when no caller is inside the slice the block is missing entirely. The lists are also resolved statically: reflection, dependency-injection containers, serializers and external assemblies stay invisible. **The absence of callers is therefore not proof of dead code.** To get the full caller list of a symbol, ask the producing tool for its caller axis.

### Source-code blocks

`TYPE_CODE`, `METHOD_CODE` and `FILE_CODE` contain verbatim source code in a fenced block. The fence adapts to the content: when the code itself contains a run of backticks, the fence is made longer than that run, so the code block cannot be closed early by its own content. When a source file cannot be read or the code of an element cannot be extracted, the block contains a short comment saying so instead of the code.

Two opt-in annotations can be added to the tags:

- **Line numbers** (`lines="START-END"`): every `METHOD`, `CLASS`, `INTERFACE` and `ENUM` tag gets the 1-based line range of the declaration, in the same convention as the IDE status bar. When the feature is on but no line data is available - for example after reloading a stored analysis - the attribute reads `lines="n/a"` instead of being silently absent.
- **Quality metrics**: method tags get `complexity="N"` (cyclomatic complexity) and `loc="N"` (lines of code); type tags get `ce="N"` (efferent coupling), `ca="N"` (afferent coupling) and `members="N"` (member count). When the afferent coupling of a type is not known in the current render view, the attribute reads `ca="n/a"` rather than `0`, so "not measured" cannot be mistaken for "nothing depends on this".

## 5.11 Method compression modes

The document writes methods in one of three compression modes. Which modes actually occur is stated in the `COMPRESSION_LEGEND` of the document itself.

| Mode | Rendered as | Content |
|---|---|---|
| Full | `<METHOD>` | All sub-blocks: `METHOD_INFO`, `DEPENDENCIES`, `USED_BY`, `SEMANTICS`, `SUMMARY`, `AI_TAGS`, `METHOD_CODE`. |
| Compact | `<METHOD compact="isolated">` | A single line. |
| Semi-compact | `<METHOD compact="near_flow">` | Signature, the top three dependencies and the AI tags, without the body. |

A missing `compact=` attribute means full mode. The compact line has this shape:

```
<METHOD compact="isolated">
ProcessOrder(int orderId) → Task<bool> | public static | Role: service
</METHOD>
```

It contains the signature, the return type (or `void`), the accessibility (or `private` when none is recorded), the declared modifiers and the resolved role. Because this line is the only information the reader gets about a compacted method, it carries the full modifier list - a dropped `override` or `async` would not be recoverable from anywhere else in the document.

The mode of a method is the result of several rules. A method is written compact only when its detail level is not `Full`, it does not belong to the primary or near flow, it is private, and it has no documentation summary, no AI annotations, no callers and no dependencies. Per-node overrides and the auto-compression heuristic can move any method into compact or detailed rendering.

Note: the semi-compact mode is implemented but not yet released - the two settings that switch it on are off by default and are not set by any standard render path. Until then, the compression legend names it only when it is actually reachable.

`METHOD_INFO` inside a full method block contains the objective method facts: `Name`, `Signature`, `Return`, `Access`, `Modifiers`, `ReturnKind`, `Parameters`, and the flags `IsStatic`, `IsAsync`, `IsExtension`, `ThrowsDetected`, `UsesLinq` and `UsesReflection` (each written only when true). A method block additionally carries `DEPENDENCIES` with a `Types:` list and a `Calls:` list of the methods it invokes in the solution, and a `USED_BY` list of its callers.

## 5.12 The legends

### PATH_LEGEND and alias rules

Long type names repeat throughout the graph sections, so the document abbreviates them. `PATH_LEGEND` is the decoding table and maps every abbreviated type name to its alias, sorted by name:

```
<PATH_LEGEND>
ColorBlendCalculator => CBC
ColorMixResult => CMR2
IColorMixService => ICMS
</PATH_LEGEND>
```

The alias rules are strict, and reading them correctly matters:

- Aliases may replace type names **only** in these ten sections: `DOMAIN`, `ARCHITECTURE_FLOW`, `INTERFACE_RELATIONS`, `ENTRY_POINTS`, `ENTRY_POINT_FLOW`, `SERVICE_DEPENDENCY_GRAPH`, `LAYER_MAP`, `CLASS_DEPENDENCY_GRAPH`, `METHOD_GRAPH`, `METHOD_USED_BY_GRAPH`. Everywhere else - code blocks included - every name is literal.
- `PATH_LEGEND` itself prints the mapping; it does not substitute.
- `ROLE_GRAPH` looks like the other graph sections but carries no type names: its edges connect roles (`Service -> Interface`), so it never uses the mapping.

Aliases are derived from the type name's capital letters. Names longer than twelve characters get an alias from their initials; a collision gets a numeric suffix, so two types with the same initials become `CA` and `CA2`. All remaining types are added alphabetically in a second pass, using their initials or, when there are too few, the first two characters of the name. Two rules keep the table unambiguous:

- A name shorter than two characters never gets an alias. The only alias it could carry is itself, which compresses nothing while still claiming that a bare letter refers to that type.
- Names of twelve characters or fewer are reserved first, so a longer type's alias cannot shadow them. They can still receive their own alias in the second pass (initials, or the first two characters).

The mapping is keyed by the simple type name. Two types with the same simple name in different namespaces therefore share one alias; the per-type `[Layer: ...]` and `[Role: ...]` fields are the unambiguous source when this matters.

If layout rendering is switched off, no aliases are built, `PATH_LEGEND` and the alias rules are omitted, and every name is written out in full.

### COMPRESSION_LEGEND

`COMPRESSION_LEGEND` is always rendered. It tells the reader

- which compression modes the document actually uses (two or three, depending on the render path),
- how a method is selected for full, semi-compact or compact rendering,
- what a missing `compact=` attribute means,
- the provenance vocabulary of the `SEMANTICS` blocks (`Resolved`, the breakdown form and the four tokens),
- and the caveat that applies to every caller list: the lists name only the callers this document renders, and they are statically resolved. Reflection, dependency-injection containers, serializers and external assemblies stay invisible; the absence of callers is not proof of dead code.

Read this section first when you interpret a rendered document - it describes exactly the notation in front of you.

## 5.13 Detail levels and auto-compression

How much of a type or method is written is decided by a **detail level** with four steps:

| Level | Effect |
|---|---|
| `Compact` | Shortest form. For a method, the single compact line. |
| `Normal` | Standard form: type information, semantics, summary, structure, dependencies, methods. |
| `Detailed` | Normal plus the extended fields. |
| `Source` | Detailed plus the verbatim source-code block. |

A context template holds one detail preset per level (`Compact`, `Normal`, `Detailed`, `Source`), and a node in the solution tree can override its level individually. Without a per-node setting, the `Normal` preset governs the whole export.

The **auto-compression heuristic** proposes a level per method so that an export does not have to be tuned by hand. It runs on first use of a solution when enabled and can also be triggered manually:

| Rule | Result |
|---|---|
| AI priority `high` or `important` | `Detailed` |
| AI priority `low` or `nice to have` | `Compact` |
| Entry point (static `Main`, or a public method of a `Controller` type) | `Detailed` |
| Public method with at least 3 callers | `Normal` |
| Everything else | `Compact` |

The caller threshold, the three force rules and the master switch are configurable in the active compression rules profile. The heuristic only proposes a level; the context template turns that level into a concrete detail preset, so changing the template changes the final rendering while the heuristic stays the same.

Two more axes influence the result:

- **Expansion strategies** decide how far the neighborhood of the selection is expanded before rendering - only the explicitly selected nodes, their direct neighbors, or everything reachable within the configured depth. They are separate from the detail level: expansion decides *what* enters the document, the detail level decides *how much* of it is written.
- **The method graph mode** on a detail preset decides how much of a method signature the method graph carries (four values: complete graph, semantic edges only, with signature, with body). The built-in presets mostly use the signature variant.

## 5.14 Token budget and trimming

A document can be limited to a token budget. The budget and its trimming behavior come from the active **pipeline profile**:

| Setting | Default | Meaning |
|---|---|---|
| `BudgetedTrimmingEnabled` | off | Master switch for the budget-trimming pipeline. |
| `MaxTokenBudget` | 60 000 | The token budget for the rendered document. Lower values are raised to a floor of 8 000. |
| `MaxOvershootPercent` | 50 | How far the document may exceed the budget before types are dropped. The admissible ceiling is `budget × (1 + percent / 100)`. |
| `AutoBypassSnapshots` | on | Skips trimming in read-only snapshot tabs. |
| `ShowBudgetHeaderInOutput` | off | Writes the budget comment into the document (see below). |

Three built-in pipeline profiles ship with the product:

| Profile | Behavior |
|---|---|
| `Default` | Trimming off, snapshots bypassed. Recommended default. |
| `Aggressive Trimming` | Trimming on with a 20 000 token budget, a +10 % overshoot tolerance and the budget header enabled. |
| `No Trimming (Snapshot-Mode)` | Trimming off with a 200 000 token budget and no automatic bypass. Suited to models with a very large context window and to reproducible comparisons. |

In the MCP render path the effective budget is resolved from the first of these tiers that is set:

```
explicit call parameter  >  MCP profile  >  context template  >  global pipeline profile
```

The MCP `budget` parameter of the slice tools (`get_context`, `explain_symbol`, `pack_for_task`, `prepare_task`) is the explicit tier and is raised to 8 000 when lower. When no budget is set at all, the slice tools still render against a ceiling (the active MCP profile's budget, otherwise about 10 000 tokens), so a slice stays bounded.

Note: a token budget set on a context template takes effect only in the MCP render path. The GUI and CLI renders ignore it, so that stored snapshots stay reproducible.

### What trimming does

Trimming runs in two stages, both aimed at the same number:

1. **Type pruning.** Over-budget selected types are first reduced to their structure - they keep their identity and members, but lose their source code - to reach the target. Only if that is not enough are types dropped, down to the ceiling. At least one type always survives, and the export pruner never takes the code of the focal, top-ranked type away. Retrieval slices (`get_context`, `explain_symbol`, `pack_for_task`, `prepare_task`) may still degrade the focal type to structure, with a warning and budget recommendation, when its source alone exceeds the slice budget.
2. **Method trimming.** The remaining methods are compressed along the compression ladder until the estimate fits.

The trimming is estimate-based, so the export path measures the finished document and corrects itself in bounded passes. A correction pass may lower the internal floor from 8 000 to 2 000 tokens so that a tight target is reachable.

### The compression ladder

The trimming pipeline orders methods by importance and walks them down a five-step ladder until the estimated size fits the budget:

```
Drop = 0, NameOnly = 1, SignatureOnly = 2, SignatureDoc = 3, FullBody = 4
```

Each method starts on a rung derived from its detail level (`Source` and `Detailed` start at full body, `Normal` at signature plus documentation, `Compact` at signature only). The methods with the lowest score are moved down first.

Note: the ladder decides the order and the number of removals, not the rendering of the survivors. Only the `Drop` rung removes a method from the output; whether a surviving method is written with its body is decided by the detail preset, independently of the ladder. Mapping the intermediate rungs onto the render paths is a planned product decision, not current behavior.

Two settings of the compression rules profile are not yet in effect: the trimming mode `Sweep` (which is defined but behaves like the default `Greedy` mode) and the tiebreaker order list (the comparator uses a fixed order of score, lines of code, name and qualified key).

### The budget header

When `ShowBudgetHeaderInOutput` is enabled on the active pipeline profile, the document starts with an HTML comment that reports the trimming result:

```
<!-- token_budget: 60000 | est_after_trim: 58423 | trimmed: 142 methods (6 dropped) -->
```

A run that bypassed the trimming prints one of these instead:

```
<!-- token_budget: 60000 | bypassed (read-only snapshot) -->
<!-- token_budget: 60000 | bypassed (trimming disabled) -->
```

Read the three fields carefully:

- `token_budget` is the budget **you** asked for. It is not necessarily the number the trim aimed at internally, but it is always the user-facing budget.
- `est_after_trim` is the estimated size after trimming. It may legitimately exceed the budget when overshoot was granted, and it is **not** the delivered size: it states what the document would cost if the render honored every compression level. Because only the `Drop` level reaches the output, the real document is usually larger.
- `trimmed: N methods` counts the methods that ended below their starting level. The dropped methods are included in that number, so `dropped <= trimmed <= total`.

The header is off by default, and only the `Aggressive Trimming` built-in profile enables it.

## 5.15 Document modes

Four document modes decide which sections exist at all. You do not select them directly - each render path uses its own - but they explain why two documents of the same solution can differ.

| Mode | Used by | Effect |
|---|---|---|
| Full export | `export_markdown`, the GUI export, the CLI export | Nothing is removed. |
| Lean | `get_context`, `explain_symbol`, `pack_for_task`, `prepare_task`, `architecture_overview` (default) | Drops the format preamble (`SPEC` and `META`) and every enabled graph section that would only contain `- none`. `PATH_LEGEND`, `COMPRESSION_LEGEND` and all non-empty sections stay. |
| Structure-only | `architecture_overview` | Drops the sections with source code and type trees (`SOLUTION`, `FILE_INDEX`, `ENUM_SUMMARY`, `BUILD_AND_UI_FILES`, `AUXILIARY_FILES`) and keeps the macro sections, the legends and the domain summary. Quality hotspots are enabled in this mode. |
| Focused slice | `explain_symbol`, `get_context`, `pack_for_task` | Additionally drops the two solution-wide verbatim file sections `BUILD_AND_UI_FILES` and `AUXILIARY_FILES`. |

The lean mode is the default for all slice tools; pass `lean: false` to get the full document with the format contract. `prepare_task` ignores the flag on its template-based render path, which the active MCP profile controls.

The bounded **architecture overview** caps each macro section except `LAYER_MAP` at 80 entries and appends a truncation note when the cap bites; the complete type-to-layer map remains uncapped. Its `summaryOnly` mode collapses the other macro sections to the first five entries plus a count line, while `LAYER_MAP` becomes an aggregate with a total and per-layer counts. In that mode the document also renders plain type names instead of aliases, so it never advertises a legend it does not carry.

Four sections cannot be switched off through an MD profile because they have no profile slot: `COMPRESSION_LEGEND`, `BUILD_AND_UI_FILES`, `AUXILIARY_FILES` and `QUALITY_HOTSPOTS`. The first three are always on and relevance-filtered; quality hotspots are controlled by the quality-metrics setting.

## 5.16 What the document does not tell you

A few properties of the format are easy to misread. They are listed here so you can interpret a document correctly:

- **Caller lists are partial by construction.** `USED_BY` names only the callers rendered in the same document. In a slice, a caller outside the slice is missing and the block may be absent altogether.
- **Caller lists are static.** Reflection, dependency-injection containers, serializers and external assemblies are not visible to the analysis. A missing caller is not dead code.
- **`inferred` values are guesses.** They are useful hints, but they are not facts. Rely on `fact` and `ai` values when correctness matters.
- **`ca="n/a"` and `lines="n/a"` mean "not measured here"**, not "zero" and not "the feature is off".
- **Empty fields and empty blocks are omitted.** A flag such as `IsStatic: true` appears only when the flag is set, so an absent flag means false. A missing optional field means it has no value in this render - not that it was empty in the source.
- **`UnknownDependencies` names what could not be resolved**, not what does not exist. It typically contains dependencies from external assemblies.
- **The namespace part of `QUALITY_HOTSPOTS` is omitted in partial exports**, and the document says why: measuring namespace coupling over a pruned view would understate the afferent and overstate the efferent coupling and could produce a misleadingly clean result.

## 5.17 A complete example

The following excerpt is real product output, abbreviated to the essentials. It shows a small solution with one project, one file and one class:

```
---
type: ai-builder-context
title: Acme.Minimal
description: Roslyn-generated AI-Builder-MD context for the Acme.Minimal solution.
---
<AI_CONTEXT_SPEC>
Purpose: Structured semantic representation of a .NET solution optimized for LLM understanding.
...
AliasRules:
5. PATH_LEGEND maps type names to short aliases.
6. Aliases may replace type names only in these sections: DOMAIN, ARCHITECTURE_FLOW, ...
7. PATH_LEGEND always contains the full type name mapping.
...
Sections:
- SPEC
- META
- PATH_LEGEND
- COMPRESSION_LEGEND
- DOMAIN
...
</AI_CONTEXT_SPEC>

<AI_CONTEXT_META>
Generator: AIContextBuilder
Version: 1.0
Format: AIContextMarkdown
Solution: Acme.Minimal
GeneratedAt: 2026-09-21T09:15:42Z
AnalyzerVersion: 0.5.464.xxx
Projects: 1
Files: 1
Types: 1
Classes: 1
Interfaces: 0
Enums: 0
Methods: 0
Properties: 0
Constructors: 0
DistinctDependencies: 0
</AI_CONTEXT_META>

<PATH_LEGEND>
Hello => HE
</PATH_LEGEND>

<COMPRESSION_LEGEND>
Format: Methods are emitted in one of two compression modes.
...
</COMPRESSION_LEGEND>

<DOMAIN>
Name: Acme.Minimal
CoreComponents:
</DOMAIN>

<ARCHITECTURE_FLOW>
Flows:
- none
</ARCHITECTURE_FLOW>

<FILE_INDEX>
[Project: Acme.Minimal]
**RelativePath:** src/Hello.cs
Types: 1
Methods: 0
</FILE_INDEX>

<SOLUTION>
Name: Acme.Minimal
Projects: 1
<PROJECT>
Name: Acme.Minimal
<FILE>
Name: Hello.cs
Path: src/Hello.cs
<CLASS>
**TypeName:** Hello
<STRUCTURE>
Access: public
</STRUCTURE>
<DEPENDENCIES>
</DEPENDENCIES>
<METHODS>
</METHODS>
</CLASS>
</FILE>
</PROJECT>
</SOLUTION>
```

The same content in the YAML notation begins like this:

```yaml
type: ai-builder-context
title: Acme.Minimal
description: Roslyn-generated AI-Builder-MD context for the Acme.Minimal solution.
aiContextSpec: |
  Purpose: Structured semantic representation of a .NET solution optimized for LLM understanding.
  ...
aiContextMeta:
  generator: AIContextBuilder
  version: "1.0"
  format: AIContextMarkdown
  solution: Acme.Minimal
solution:
  name: Acme.Minimal
  projects:
  - name: Acme.Minimal
    files:
    - name: Hello.cs
      path: src/Hello.cs
      classes:
      - typeName: Hello
        structure:
          access: public
```

Both notations carry the same information: the frontmatter fields as top-level keys, the sections as mappings, repeated blocks as sequences, and the format contract as one string field.

---

[&larr; 4 How the analysis works](04-how-the-analysis-works.md) &middot; [Contents](README.md) &middot; [6 Templates, rendering and markup analysis &rarr;](06-templates-rendering-and-markup-analysis.md)
