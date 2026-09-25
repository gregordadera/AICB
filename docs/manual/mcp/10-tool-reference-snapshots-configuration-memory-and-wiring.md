[AICB – MCP Server](README.md) &middot; chapter 10 of 12

# 10 Tool reference: snapshots, configuration, memory and wiring

This chapter documents the tools that persist and compare analyzed state, configure how a solution is analyzed, keep a cross-process memory of a codebase, browse the aicb database's master data, install the agent-side symbol guard, and run several read-only queries in a single call. The other tool families (symbol lookup, fan-in, tests, insights, markup, and so on) are documented in their own chapters.

**Reading the parameter tables.** `sessionId` is either an id returned by `analyze_solution` (or by a recall) or an absolute path to a `.sln`, `.slnx` or `.slnf` file. Passing a path analyzes that solution on first use and reuses the result afterwards, so a separate `analyze_solution` call is optional; see "Sessions and staleness". A tool marked as needing a *live* session refuses a session that was recalled from a database with `recall_codebase`, because the open analyzer workspace is gone.

**`dbPath` and the standard config database.** Several tools take an optional `dbPath` pointing at an aicb SQLite database. When a tool says "omit to use the server's standard config DB", the server falls back to the database it was started with — for the standalone `aicb mcp` command that is the same file the desktop GUI uses (`%APPDATA%/AIContextBuilder/user-data/aicb.acb`). A call without `dbPath` therefore reads and writes the database you actually work in; pass an explicit `dbPath` whenever the write should land elsewhere.

**Pool membership.** The shipped `Default` MCP profile exposes 54 of the 82 registered tools. `Full Select` exposes the 72-tool lean core. `compare_public_api` is reached through the opt-in `api-surface` bundle or an `AICB_MCP_TOOLS` override. Nine uncatalogued tools are available only through that override: `import_constellation`, `inspect_session`, `list_constellations`, `list_remembered`, `list_run_templates`, `list_sessions`, `recall_codebase`, `refresh_remembered`, `remember_codebase`. The variable (`all`, `lean`, or a comma-separated list such as `MemoryTools,DbEntityTools`) replaces the profile's tool set rather than adding to it, so name every group you need. The final index states Default membership, not reachability through `Full Select`.

## 10.1 Snapshots and comparison with a stored state

A snapshot is a persisted copy of the analyzed model of a solution inside an aicb database. `save_session` writes one; `compare_with_previous` and `diff_public_contract` compare the current session against one of the same solution. Snapshots are selected by age: `snapshotsBack` `0` is the newest saved snapshot, `1` the one before it, and so on.

### `save_session`

**Purpose.** Persist the current session's analyzed model as a named manual snapshot in an aicb database, so that a later session can be compared against it.

**When to use it.** Before a refactoring or any larger change, so that "what changed since then" can be answered structurally later. The snapshot is a baseline of the analyzed model, not a backup of the source files.

| Parameter | Type | Required | Default | Meaning |
|---|---|---|---|---|
| `sessionId` | string | yes | — | The session whose current state is snapshotted; live or recalled. |
| `name` | string | yes | — | A human-readable label, for example `before refactor`. An empty name is rejected. |
| `dbPath` | string? | no | `null` | The aicb database to persist into. Omit to use the server's standard config DB (the GUI's). |

**Response.**
- `snapshotId` — the id of the new snapshot.
- `sessionId`, `solutionId` — the session and the solution record the snapshot belongs to.
- `name` — the label you passed.
- `lineNumbersAvailable` — whether the session carries line numbers.
- `totalSnapshots` — how many snapshots this solution now has (manual and automatic).

**Notes and limits.**
- The snapshot is stored as a *manual* snapshot. The automatic retention that caps the memory tools' snapshot history never deletes a manual snapshot, so a baseline stays until it is removed deliberately.
- Snapshots lose line numbers (`startLine`/`endLine`) on the database round-trip. Line-number-dependent output is therefore degraded when a snapshot is read back.
- Without an explicit `dbPath` the snapshot lands in the database the GUI uses.

### `compare_with_previous`

**Purpose.** Diff the current session against a previously saved snapshot of the same solution — the newest by default, or the N-th previous via `snapshotsBack`.

**When to use it.** To answer "what changed since the last known-good state": which types were added or removed and, per changed type, which methods were added or removed and which signatures changed. The diff is name- and signature-based; method bodies are not compared.

| Parameter | Type | Required | Default | Meaning |
|---|---|---|---|---|
| `sessionId` | string | yes | — | The "after" side of the diff. |
| `dbPath` | string? | no | `null` | The aicb database holding the saved snapshots. Omit for the server's standard config DB. |
| `snapshotsBack` | int | no | `0` | `0` = newest saved snapshot, `1` = the one before it, etc. Must be `>= 0` and within the saved history. |
| `typeName` | string? | no | `null` | Restrict the diff to this type. Simple name, case-insensitive. Not a substring match: `MyApi` never matches `MyApiExtensions`. A simple name also matches the namespace-qualified form the diff uses when a simple name collides — the answer then spans every type of that name and `note` says which. |
| `methodName` | string? | no | `null` | Within that type, restrict to this method name (case-insensitive). |

**Response.**
- `sessionId` — the session that was compared.
- `note` — present only when the filter owes a disclosure; omitted otherwise.
- `baselineSnapshotId`, `baselineName`, `baselineCreatedUtc` — which snapshot was used as the baseline.
- `snapshotsBack`, `totalSnapshots` — the index used and the size of the history.
- `diff` — `addedTypes`, `removedTypes`, `changedTypes`, plus `isIdentical` and `totalChangeCount`. Each changed type carries `typeName`, `addedMethods`, `removedMethods` and `changedMethodSignatures`; a signature entry gives `methodName`, `leftSignature`, `rightSignature` and the flags `returnTypeChanged`, `parametersChanged`, `accessibilityChanged`, `staticChanged`.

**Notes and limits.**
- At least one earlier `save_session` for the same solution is required; otherwise the call is rejected with a message telling you to call `save_session` first. A `snapshotsBack` outside the saved history is rejected with the number of available snapshots.
- The filter disclosure is the important property. When a filter empties a diff that did have changes, `note` says so and names the axis that missed, because `isIdentical: true` then describes the filtered view and not the solution. A changed type whose method lists the `methodName` filter emptied is dropped from the answer, so an empty view is never evidence that the method is unchanged.
- On a diff that was already empty there is no note, and none is owed: "your filter matched nothing" and "nothing changed" are the same state there, so a mistyped and a real name answer identically. Check the spelling with `find_symbol` rather than reading that agreement as confirmation.

### `diff_public_contract`

**Purpose.** Report the breaking and additive changes to the public API surface of the current session compared with a saved snapshot of the same solution.

**When to use it.** Before releasing a library or any code other callers depend on: this answers "did I break a caller?" at the contract level rather than at the line level.

**Not exposed by the `Default` profile** — reachable under `Full Select` or via `AICB_MCP_TOOLS`.

| Parameter | Type | Required | Default | Meaning |
|---|---|---|---|---|
| `sessionId` | string | yes | — | The "after" side of the diff. |
| `dbPath` | string? | no | `null` | The aicb database holding the saved snapshots. Omit for the server's standard config DB. |
| `snapshotsBack` | int | no | `0` | `0` = newest saved snapshot, `1` = the one before it, etc. |
| `scope` | string? | no | `null` | Restrict the diff to a namespace prefix (case-insensitive). |
| `includeInternal` | bool | no | `false` | Also diff the internal family, not only the externally visible public/protected contract. |

**Response.**
- `sessionId`, `baselineSnapshotId`, `baselineName`, `baselineCreatedUtc`, `snapshotsBack`, `totalSnapshots` — the baseline metadata.
- `scope`, `includeInternal` — the echo of what was compared.
- `hasBreakingChanges`, `breakingCount`, `additiveCount` — true totals, even when a list below is truncated.
- `removedTypes`, `removedMembers`, `changedMembers`, `addedTypes`, `addedMembers` — the five diff lists, each a capped envelope with `items`, `count`, `totalFound` and `truncated`.

**Notes and limits.**
- Classification: a removed public type or member, or a changed member signature, is **breaking**; an added type or member is **additive**.
- Both sides are projected through the same public-surface view, so the comparison is like for like.
- The comparison is name- and signature-based; method bodies are not diffed. A change of a parameter *type* appears as a removal plus an addition.
- At least one earlier `save_session` is required; a missing baseline is rejected with a message telling you to save one first.

## 10.2 Solution configuration (layers, exclusions, test detection)

Three per-solution settings decide how aicb reads your code: the **layer profile** (which namespace belongs to which architectural layer), the **namespace exclusion list** (which namespaces are not yours), and the **test-detection profile** (which projects are test projects and which attributes mark a test method). The four tools below form one guided flow: check the status, fetch the material, apply a proposal, and later check whether the configuration still fits the code. Only `apply_solution_config` writes.

### `solution_config_status`

**Purpose.** Check whether the three axes have been initialized through the guided setup, and which layer profile, exclusion list and test profile are currently active.

**When to use it.** On first contact with a solution, before proposing a setup.

| Parameter | Type | Required | Default | Meaning |
|---|---|---|---|---|
| `sessionId` | string | yes | — | The session of the solution to inspect. |
| `dbPath` | string? | no | `null` | The aicb config/master database. Omit to use the server's standard config DB (the GUI's). |

**Response.**
- `solutionId`, `solutionName`.
- One slot per axis — `layerProfile`, `exclusionList`, `testProfile` — each with `initialized`, `initializedAt`, `activeId`, `activeName` and `source`. The test slot additionally carries `isCustom`.

**Notes and limits.**
- Although the tool is observational, resolving an unknown solution ensures its row in the configuration database and can insert that row with the auto-initialization flags enabled.
- `initialized` is an **explicit marker** stamped by `apply_solution_config`. It is not inferred from an active id, because an active profile can also be set by hand in the Settings panel.
- `source` says where the axis comes from: `db` (a row in the config database, with its timestamp), `sidecar` (the git-tracked `<SolutionName>.aicb.json` next to the .sln, which is read at analyze time), or `none`. A repository with a valid sidecar and no database row therefore reports `initialized: true` with `source: "sidecar"`, not a misleading "not initialized".
- The test slot resolves the effectively active test profile through the full chain (per-solution setting, then the global application setting, then the built-in default). `activeId` is `null` when the built-in default heuristic is in effect; `isCustom` tells you whether the resolved profile is a custom profile rather than a built-in preset.
- If a slot is not initialized, offer `init_solution_config` followed by `apply_solution_config`.

### `init_solution_config`

**Purpose.** Start the guided setup and return the raw material for a proposal. The tool writes nothing.

**When to use it.** After `solution_config_status` reports an axis as not initialized, and before `apply_solution_config`.

| Parameter | Type | Required | Default | Meaning |
|---|---|---|---|---|
| `sessionId` | string | yes | — | Must be a live session. |

**Response.**
- `solutionPath`.
- `declaredNamespaces` — the solution's own namespaces, production-focused (test-project and framework/generated namespaces are dropped); the source for layer rules. Capped at 300 entries with `count`, `totalFound` and `truncated`.
- `referencedNamespaces` — every namespace referenced through `using`, including namespaces owned by the solution itself. Capped at 300 entries. When proposing exclusion rules, use only its framework and third-party subset.
- `testProjects` — the projects the default heuristic classifies as test projects. Capped at 300 entries.
- `detectedTestAttributes` — the test-attribute markers that actually occur in the code, out of the built-in set (`Fact`, `Theory`, `Test`, `TestMethod`, `TestCase`). Not capped; the set is small by construction.
- `proposalFormat` — a format hint that spells out the expected `proposalJson` and `testProposalJson` shapes.

**Notes and limits.**
- Requires a live session: a session recalled from memory has no live workspace. The tool walks the already-warm session, so it triggers no re-analysis.
- Budget for the answer rather than for the work: on a mid-sized solution the four lists arrive in one reply and can be several thousand tokens. Check the `truncated` flag before treating a namespace list as complete — otherwise your rules come from a sample.
- This tool is not one of the read-only query tools that `batch` or `measure` can dispatch, so `measure` cannot price it.

### `apply_solution_config`

**Purpose.** Apply a proposed layer, exclusion and test configuration: create a new custom layer profile, exclusion list and/or test profile (tagged with the source solution for provenance), activate them, and mark each touched slot as initialized.

**When to use it.** As the second half of the guided flow, using the material from `init_solution_config` or rules of your own.

| Parameter | Type | Required | Default | Meaning |
|---|---|---|---|---|
| `sessionId` | string | yes | — | The session of the solution to configure. |
| `dbPath` | string? | no | `null` | The config/master database to write into; created if missing. Omit to use the server's standard config DB (the GUI's). |
| `proposalJson` | string? | no | `null` | A JSON object with `layerRules` and/or `exclusions` (see below). Omit for a test-only apply. |
| `layerProfileName` | string? | no | `null` | Display name of the created layer profile. Omit for an auto-generated name. |
| `exclusionListName` | string? | no | `null` | Display name of the created exclusion list. Omit for an auto-generated name. |
| `layeringPolicy` | string? | no | `null` (`Advisory`) | `Advisory` or `Strict`. |
| `testProposalJson` | string? | no | `null` | A JSON object with `testProjectRules` and `testAttributeNames`; the rules match **project** names. Mutually exclusive with `testPreset`. |
| `testPreset` | string? | no | `null` | Shortcut: clone a built-in test profile (`xunit`, `nunit`, `mstest`, `default`) into a custom per-solution profile. Mutually exclusive with `testProposalJson`. |
| `testProfileName` | string? | no | `null` | Display name of the created test profile. Omit for an auto-generated name. |

`proposalJson` shape:

```json
{
  "layerRules": [ { "pattern": ".Application.", "matchType": "Contains", "layer": "Application" } ],
  "exclusions": [ { "pattern": "System.", "matchType": "StartsWith" } ]
}
```

`matchType` is `Contains`, `StartsWith`, `EndsWith` or `Exact`. Layer rules default to `Contains` and exclusions to `StartsWith` when `matchType` is omitted. An invalid `matchType` is rejected rather than silently defaulted — for a writing tool, a silent fallback would turn a mistyped `EndsWith` rule into the broader `Contains` rule.

`testProposalJson` shape:

```json
{
  "testProjectRules": [ { "pattern": ".Tests", "matchType": "EndsWith" } ],
  "testAttributeNames": [ "Fact", "Theory" ]
}
```

**Response.**
- `layerProfileInitialized`, `layerProfileId`, `layerProfileName`, `layerRuleCount`.
- `exclusionListInitialized`, `exclusionListId`, `exclusionListName`, `exclusionRuleCount`.
- `testProfileInitialized`, `testProfileId`, `testProfileName`, `testProjectRuleCount`.
- `warnings` — non-fatal problems, including a failed sidecar write.
- `sidecarPath` — the written sidecar file; omitted when the sidecar write failed.

**Notes and limits.**
- At least one axis must be non-empty; empty arrays and slots are skipped, and a proposal that leaves all three axes empty is rejected with a message naming the accepted forms.
- Auto-generated display names follow the pattern `LLM init (<solution name>) - layers`, `- exclusions` and `- tests`.
- The tool writes to **two places at once**: the config database, and the git-tracked `<SolutionName>.aicb.json` sidecar next to the .sln. The returned `sidecarPath` comes with the explicit request to commit it, so the configuration travels with the repository — the next clone and the next agent then analyze the solution the same way. This sidecar write is headless and does not ask for overwrite confirmation, unlike the GUI's export.
- If the sidecar write fails (for example in a read-only directory), the database write is **not** rolled back; the failure is disclosed in `warnings` and `sidecarPath` is omitted.
- The sidecar is rewritten as a whole, so its existing triage suppressions and the analysis-scope setting are read first and carried forward. Saving a configuration does not reset your triage.
- An unknown `testPreset` is rejected with the list of known presets; passing `testProposalJson` and `testPreset` together is rejected as well.
- Omit `dbPath` and the write lands in the database the GUI uses. If you keep more than one database, name the target explicitly.

### `check_solution_config_drift`

**Purpose.** Check whether the active configuration still fits the code — has it drifted since it was set up?

**When to use it.** After the code has grown (new projects, new namespaces, new dependencies), or periodically as a health check.

| Parameter | Type | Required | Default | Meaning |
|---|---|---|---|---|
| `sessionId` | string | yes | — | Must be a live session. |
| `dbPath` | string? | no | `null` | The aicb config/master database. If given, its active layer profile, exclusion list and test profile take precedence over the sidecar. Omit to fall back to the server's standard config DB, or — when the server has none — to the `.aicb.json` sidecar only. |

**Response.** One axis object each for `layer`, `exclusion` and `test`, with:
- `source` — where the checked configuration came from (`db`, `sidecar` or `none`).
- `name` — its display name.
- `status` — `stale`, `ok`, `not-configured` or `built-in-preset`.
- `stale` — the boolean shorthand for `status == "stale"`.
- `considered` — the size of the examined set (the denominator); `0` when the axis was not evaluated.
- `sample` — the capped evidence list (up to 50 entries), whose `totalFound` is the full drift count.
- `reason` — a sentence explaining the result.

**The three signals.**

| Axis | Signal | Meaning |
|---|---|---|
| Layer | unmapped | Declared (own) namespaces that no rule of the active layer profile maps. |
| Exclusion | uncovered | External referenced namespaces (the solution's own are excluded from this check) that the active exclusion list does not cover. |
| Test | unmatched | Projects the canonical default heuristic classifies as test projects that the rules of the active custom test profile do not match — the profile may be too narrow. |

**Notes and limits.**
- Although the tool reports drift rather than applying configuration, resolving an unknown solution ensures its row in the configuration database and can insert that row.
- Only a **custom** configuration is evaluated. A built-in preset (for example the Clean Architecture layer profile, the BCL exclusion default or the default test heuristic) and an empty or role-heuristic configuration are reported as `not-configured` or `built-in-preset` — a deliberate generic choice is not stale.
- An axis reports `stale` once the drift count reaches the threshold of 3; below that it reports `ok` with the evidence still listed.
- A database-active id that no longer resolves (a deleted profile) falls back cleanly to the sidecar or to `none`.
- Requires a live session.

## 10.3 Cross-process memory

The four memory tools persist an analyzed codebase in an aicb database and bring it back later — from the same process or a different one — without running the analyzer again. They are not part of any facet menu or bundle, so **no shipped profile exposes them**, and they are also not reachable through `batch` or `measure`. An operator exposes them with the `AICB_MCP_TOOLS` environment variable, for example `AICB_MCP_TOOLS=MemoryTools`.

### `remember_codebase`

**Purpose.** Analyze a `.sln` and persist it as a snapshot in an aicb database so it can be recalled later, even from another process. Returns a **live** `sessionId` (line numbers intact) that you can use immediately.

**When to use it.** To make a codebase available to a later server process — for example a second harness or a nightly job — without paying for a fresh analysis there.

| Parameter | Type | Required | Default | Meaning |
|---|---|---|---|---|
| `solutionPath` | string | yes | — | Absolute path to the `.sln` file to analyze and remember. |
| `dbPath` | string | yes | — | Absolute path to the aicb memory database to persist into. There is no server default; the database is created and migrated if it does not exist. |
| `layerProfile` | string? | no | `null` | Absolute path to a layer-mapping profile JSON. Omit for role-based heuristics. |

**Response.** The session metadata: `sessionId`, `solutionPath`, `solutionName`, `projectCount`, `fileSetHash`, `layerProfile`, `lastAccessUtc`, `origin`, `lineNumbersAvailable` (and `analyzePreferredTfmOnly` when the sidecar asked for the preferred target framework only).

**Notes and limits.**
- The persisted snapshot carries the same analysis scope as an `analyze_solution` run of the same solution: the namespace exclusions and the preferred-target-framework setting from the git-tracked `<SolutionName>.aicb.json` sidecar are applied.
- Each call appends a new automatic snapshot. The automatic history per solution is capped at 10 entries, so older automatic snapshots are pruned; manual snapshots written by `save_session` are never pruned by this cap.
- Remembering the same solution again after an edit re-analyzes it and writes a fresh snapshot, so the memory database does not keep serving a stale model from a warm cache.

### `list_remembered`

**Purpose.** List the codebases remembered in an aicb database.

| Parameter | Type | Required | Default | Meaning |
|---|---|---|---|---|
| `dbPath` | string | yes | — | Absolute path to the aicb memory database. |

**Response.** A JSON array, one entry per remembered solution, ordered by solution path:
- `solutionId`, `solutionPath`, `name`.
- `lastSnapshotUtc` — the timestamp of the latest snapshot.
- `fileSetHash` — the file-set hash of that snapshot.
- `hasModel` — whether a usable model payload is present.

**Notes and limits.** Metadata only; no payload is loaded. `lastSnapshotUtc`, `fileSetHash` and `hasModel` come from the latest snapshot of each solution.

### `recall_codebase`

**Purpose.** Recall a previously remembered codebase **without** running Roslyn — instant cross-process context.

**When to use it.** To start working on a codebase in a new process without paying for a fresh analysis, or to answer structural questions when the analyzer cannot run.

| Parameter | Type | Required | Default | Meaning |
|---|---|---|---|---|
| `solutionPath` | string | yes | — | Absolute path to the `.sln` that was remembered. |
| `dbPath` | string | yes | — | Absolute path to the aicb memory database. |

**Response.** `session` (the session metadata, including the new `sessionId`), `stale`, `lineNumbersAvailable` (always `false`), `reason`.

**Notes and limits.**
- A recalled model has **no line numbers**, and line-number-dependent insights are degraded. Call `refresh_remembered` for a live re-analysis.
- `stale` is `true` when the files changed since the snapshot, or the payload schema or the analyzer identity differs. For a stale result, `reason` lists these possible causes in one fixed sentence; it does not identify which one occurred.
- The recalled model is served **even when it is stale** — that is the point of instant cross-process context. Treat a stale answer as a hint and refresh before relying on it.
- The lookup is read-only: a solution that was never remembered is rejected with a message telling you to call `remember_codebase` first.

### `refresh_remembered`

**Purpose.** Re-analyze a recalled session live (acquiring a fresh analyzer workspace), restoring line numbers and full insights, and re-persist the snapshot.

**When to use it.** After `recall_codebase` has served its instant answer and you need line-accurate data or the full insight set.

| Parameter | Type | Required | Default | Meaning |
|---|---|---|---|---|
| `sessionId` | string | yes | — | The recalled session id from `recall_codebase`. |
| `dbPath` | string | yes | — | Absolute path to the aicb memory database to re-persist into. |

**Response.** `session` (a fresh **live** session, including its new `sessionId`), `lineNumbersAvailable` (`true`), `reason`.

**Notes and limits.**
- The old recalled session is evicted; use the returned id from now on.
- The live re-analysis applies the same sidecar settings as a fresh `analyze_solution`, so it yields the same facts and the same project inventory.
- The snapshot is re-persisted (and the automatic-history cap applied) before the old session is dropped, so a failure leaves the old session intact.

## 10.4 aicb database entities

These three tools browse and import the master data of an aicb database rather than the analyzed code. They are not part of any facet menu or bundle, so no shipped profile exposes them; expose them with `AICB_MCP_TOOLS` (for example `AICB_MCP_TOOLS=DbEntityTools`).

### `list_run_templates`

**Purpose.** List the run templates available in an aicb database. Built-in run templates are always returned; passing an absolute `dbPath` additionally includes the custom ones from that database.

| Parameter | Type | Required | Default | Meaning |
|---|---|---|---|---|
| `dbPath` | string? | no | `null` | An absolute path to an aicb database. Omit to use the server's standard config DB (the GUI's) if it resolved one, otherwise only the built-ins are listed. |

**Response.** A JSON array, ordered by id, each item with `id`, `name`, `isBuiltIn`, `isOverridden`, `isHidden` and `builtInsOnly`.

**Notes and limits.** `builtInsOnly` is `true` when only the built-in templates were listed, i.e. no database was used. An explicit `dbPath` that does not exist is rejected (it is not created), and a directory is rejected as well.

### `list_constellations`

**Purpose.** The same listing for constellations (context templates).

| Parameter | Type | Required | Default | Meaning |
|---|---|---|---|---|
| `dbPath` | string? | no | `null` | As for `list_run_templates`. |

**Response.** The same item shape as `list_run_templates`, ordered by id.

### `import_constellation`

**Purpose.** Import a constellation JSON file into an aicb database, following the read → preview → apply sequence.

**When to use it.** To move a set of master-data entities (prompts, context templates, run templates, layer profiles, exclusion lists, test profiles, MCP profiles, quality profiles and more, plus application-settings keys) from one database or machine to another.

| Parameter | Type | Required | Default | Meaning |
|---|---|---|---|---|
| `filePath` | string | yes | — | Absolute path to the constellation `.json` file to import. Must exist. |
| `dbPath` | string | yes | — | Absolute path to the target database. Created if it does not exist; a directory is rejected. |
| `mode` | string | no | `"SkipExisting"` | `SkipExisting` keeps existing ids; `Replace` overwrites them. Any other value is rejected. |
| `previewOnly` | bool | no | `false` | When `true`, nothing is written and the per-section counts are returned instead. |

**Response (preview, `previewOnly: true`).**
- `name` — the constellation's name.
- `applied` — always `false` on this path.
- `sections` — one entry per section, with `entityType`, `newItemCount`, `conflictCount`, `unchangedCount` and `skippedBuiltInCount`.
- `appSettingsKeys` — the application-settings keys the file carries.

**Response (apply).**
- `name`, `dbPath`, `applied` (`true`).
- `appliedItemCount`, `skippedItemCount`, `appSettingsKeysApplied`.
- `warnings` — the non-fatal per-section errors of the apply.

**Notes and limits.**
- The file is read and validated first, then previewed, then applied. A read or preview error aborts the call before anything is written.
- Entries marked as built-in in the import file are always skipped. A custom entry whose id collides with an installed built-in is different: `Replace` can overwrite that row, while `SkipExisting` preserves it. Preview carefully before replacing.
- An unknown section type is reported as an error rather than silently ignored.
- Use `previewOnly` first when importing into a database you care about: it tells you exactly how many items are new, conflicting or unchanged.

## 10.5 Agent wiring

### `install_agent_hooks`

**Purpose.** Install the aicb symbol guard into this project for an agent harness, so that a C#-symbol question is **refused** on a text search and redirected to the tool that answers it.

**When to use it.** When your client offers it, or when you want the guard without re-running the full `aicb init`.

| Parameter | Type | Required | Default | Meaning |
|---|---|---|---|---|
| `sessionId` | string | yes | — | A session id, or the absolute path to a `.sln`/`.slnx`/`.slnf` file (self-init). |
| `harness` | string? | no | `null` | Which harness to install for: `claude-code`, `codex` or `opencode`. Omit to install for the harness the calling client belongs to. |
| `force` | bool | no | `false` | Overwrite an existing guard script and rewrite an existing wiring entry. |

**Response.**
- `harness` — the harness id; `harnessName` — its display name (`Claude Code`, `Codex CLI`, `OpenCode`).
- `projectDirectory` — the directory the artefacts were written into.
- `succeeded` — `false` when any artefact was refused.
- `artefacts` — one entry per file touched or declined, each with `path`, `outcome` and `detail`. `outcome` is one of `Created`, `Updated`, `Unchanged`, `Refused`.
- `nextStep` — the follow-up instruction (see below).

**Notes and limits.**
- What is written: the guard script and the harness's wiring entry — `.claude/settings.json`, `.codex/hooks.json` or `opencode.json` — and nothing else. No `.mcp.json` and no skills, and only inside the directory of the solution the session refers to. For OpenCode the guard is delivered as a plugin under `.opencode/plugins/` plus the `opencode.json` entry.
- An existing guard or wiring is kept unless `force=true`, so a re-run cannot silently discard your own edits — an edited exemption list is the obvious thing to lose here.
- The tool installs for the calling harness by default. If the client announces no name aicb can map to a harness, or you name an unknown one, the call is refused with the list of known harnesses rather than writing a configuration nothing would read.
- After the call: restart or reconnect the MCP client so it loads the new wiring, then call `refresh_session` so the session stops reporting the guard as missing. The guard runs in the client, which reads its configuration at startup, so it is not active before the reconnect.
- This tool belongs to the always-available navigation core: the offer a session makes to install the guard must be acceptable in the `Default` profile, otherwise accepting it would fail.

## 10.6 Multi-dispatch

`batch` and `measure` run several read-only queries in one round trip. They share one call shape and one registry of allowed tools; the difference is what they do with the answers — `batch` returns them, `measure` returns their size.

### `batch`

**Purpose.** Run several read-only query tools in one round trip instead of calling them as separate turns. All sub-queries reuse one session, so a self-initializing `.sln` path is analyzed only once.

**When to use it.** Whenever several answers about the same symbol are needed at once — for example `find_usages`, `get_type_hierarchy` and `find_tests_for` — or `list_insights` followed by `get_insight`.

| Parameter | Type | Required | Default | Meaning |
|---|---|---|---|---|
| `sessionId` | string | yes | — | The shared session, or an absolute `.sln` path for self-init. Shared by all sub-queries — do not repeat it inside the queries. |
| `queries` | `BatchQuery[]` | yes | — | An array of `{ tool, args }`: `tool` is a read-only tool name, `args` is that tool's own arguments as a JSON object **without** the `sessionId`. `args` may be omitted for a tool that needs no arguments. Maximum 16. |

Example:

```json
{
  "sessionId": "<session id or absolute .sln path>",
  "queries": [
    { "tool": "find_usages", "args": { "symbol": "OrderService" } },
    { "tool": "get_type_hierarchy", "args": { "typeName": "OrderService" } },
    { "tool": "find_tests_for", "args": { "symbol": "OrderService" } }
  ]
}
```

**Response.** `{ results: [ { tool, ok, result | error, note } ], count, okCount }`.
- Each sub-query is isolated: a failing one reports `ok: false` plus an `error`, while the others still return normally. One bad query never fails the batch.
- A JSON-returning tool's result is nested as a JSON object; a Markdown-returning tool's result (for example `get_context` or `explain_symbol`) is the Markdown string.
- `note` carries the sub-query's ignored-arguments disclosure: an argument name the tool does not declare was dropped, and the note names it (up to eight names, then a count) and lists the tool's real parameters. The field is omitted when there is nothing to disclose.

**Notes and limits.**
- A sub-query has exactly two fields, `tool` and `args`; there is no caller-assigned id. Because several sub-queries may name the same tool, error and omission messages carry a short echo of the identifying arguments (for example `symbol=OrderService`) so you can tell which query they refer to. The echo is part of the message text, not a separate field.
- The response budget is about 9,000 tokens. A result larger than that, or one that would push the running total over it, is replaced by `ok: false` with its measured size and a pointer to call that tool directly (slice tools accept a smaller `budget`). The work has already been done; only the response is trimmed. In practice this only affects the slice tools (`get_context`, `explain_symbol`, `pack_for_task`).
- The maximum is 16 sub-queries per call; a larger array fails the whole call with a message telling you to split it. An empty `queries` array fails the whole call as well. A bad `sessionId` fails the whole call once, up front. A cancellation aborts the whole call and is never reported as a sub-query error.
- Sub-queries run sequentially, in the order you list them.
- **Only read-only query tools can be dispatched.** The registry holds 48 tools: `architecture_overview`, `assert_absence`, `call_graph`, `calls_external`, `check_doc_drift`, `check_pattern_drift`, `confidence_map`, `coverage_gaps`, `describe_api_surface`, `detect_circular_dependencies`, `explain_symbol`, `find_binding_usages`, `find_by_attribute`, `find_by_code_traits`, `find_by_complexity_and_coverage`, `find_by_concurrency_risk`, `find_by_event_subscription`, `find_by_resource_leak`, `find_by_returns_semantic`, `find_by_semantics`, `find_by_side_effects`, `find_dead_code`, `find_god_objects`, `find_implementations`, `find_overrides`, `find_production_dead`, `find_resource_usages`, `find_structural_twins`, `find_symbol`, `find_tests_for`, `find_unresolved_bindings`, `find_usages`, `get_context`, `get_diagnostics`, `get_insight`, `get_type_hierarchy`, `impact_of_change`, `instantiation_sites`, `lifecycle_of`, `list_insight_producers`, `list_insights`, `pack_for_task`, `resolve_injection`, `solution_metrics`, `symbol_metrics`, `symbol_signature`, `trace_flow`, `type_dependency_path`.
- A tool that is read-only and in the registry but outside the **active profile's pool** is refused per item with its own message: the active pool governs `batch` exactly as it governs a direct call. Under the `Default` profile this affects several registry entries, so check `list_skills` for the active pool before assuming a name is callable.
- The refusal message for a name outside the registry names the four kinds of reason a tool can be excluded, and the names in each bracket are **examples, not the whole group** — a tool's absence from them does not mean it writes anything. The kinds are: (1) it mutates session state or writes (`analyze_solution`, `refresh_session`, `apply_solution_config`, `save_session`, `remember_codebase`, `export_markdown`, `install_agent_hooks`) — the security boundary; (2) it needs a second state, another session or a stored snapshot (`semantic_diff`, `diff_review`, `verify_claim`, `compare_with_previous`); (3) `batch` and `measure` themselves (recursion); (4) it is read-only but a poor batch member (`evaluate_change_set`, `init_solution_config`, `prepare_task`, `review_context`) — heavyweight walks, renderers and multi-file payloads whose answers would routinely exceed the response budget.
- The trailing `Available:` line of a refusal lists every tool the dispatch registry knows, which can include tools the active profile does not expose. Treat it as a spelling aid, not as the active pool.
- A tool used only through `batch` still appears in the usage statistics: the batch call records the tools it dispatched, so such a tool is visible even though it has no call row of its own.
- `batch` is part of the navigation core and therefore always available.

### `measure`

**Purpose.** Report how big a read-only query's answer would be — the exact token count — **without** returning the answer.

**When to use it.** Before pulling something expensive: to decide whether a call is worth making, which `budget` to pass a slice tool (`get_context`, `explain_symbol`, `pack_for_task`), or whether to narrow `scope` first.

| Parameter | Type | Required | Default | Meaning |
|---|---|---|---|---|
| `sessionId` | string | yes | — | The shared session, or an absolute `.sln` path for self-init. Shared by all queries. |
| `queries` | `BatchQuery[]` | yes | — | The read-only queries to measure, exactly as for `batch`: `{ tool, args }`, `args` without the `sessionId`. Maximum 16. |

**Response.** `{ measurements: [ ... ], count, okCount, totalTokens }`.
- Each measurement carries `tool`, `ok` and, for a successful query, `tokens`, `chars`, `returned`, `totalFound`, `truncated` and `budgetNote`; a failed query carries `error` instead and no size fields.
- `tokens` is the real tokenizer count (cl100k_base) of the exact text the tool would return.
- `returned`, `totalFound` and `truncated` are passed through when the measured tool answers with a capped envelope, so you also see whether you would be seeing everything. For a tool that answers in Markdown (no envelope) they are omitted rather than reported as zero.
- `budgetNote` carries the slice tools' budget-pruning disclosure verbatim: if it says types were dropped, the answer you are pricing is already cut — an axis you asked for can be missing entirely — and a larger `budget` is what buys it back.
- `totalTokens` is the summed cost of all measured queries.
- `note` carries the same ignored-arguments disclosure as in `batch`.

**Notes and limits.**
- **`measure` does not make the query cheaper to run.** The server does the full work either way; it makes the answer cheap to *inspect* — you pay about 50 tokens instead of the answer. So measure to decide, then call once; do not measure every call by reflex.
- `measure` dispatches the same read-only tools as `batch` and refuses the same ones for the same four reasons; the refusal message names which reason applies.
- The one tool whose "call it directly" advice would be wrong is `export_markdown`: for it, `measure` advises giving the tool an `outputPath` instead. It then renders once, writes the file and returns the exact character count — cheaper than measuring, and you keep the render.
- `measure` calls are recorded as ordinary calls; the tools they priced are not added to the usage report's sub-query tally.
- `measure` is part of the navigation core and therefore always available.

## 10.7 Alphabetical index of all tools

The table lists every tool the server registers, the group it belongs to, and whether the shipped `Default` MCP profile exposes it. A `no` does not mean the tool is unavailable, but the route differs: facet-menu tools are reachable through `Full Select`; `compare_public_api` needs the `api-surface` bundle or `AICB_MCP_TOOLS`; and the nine uncatalogued tools listed above require `AICB_MCP_TOOLS`.

| Tool | Group | In Default profile |
|---|---|---|
| `analyze_solution` | Session and analysis | yes |
| `apply_solution_config` | Solution configuration | yes |
| `architecture_overview` | Orientation and server introspection | yes |
| `assert_absence` | Tests and coverage | yes |
| `batch` | Multi-dispatch | yes |
| `call_graph` | Fan-in, impact and paths | yes |
| `calls_external` | Fact queries | yes |
| `check_doc_drift` | Patterns and documentation drift | no |
| `check_pattern_drift` | Patterns and documentation drift | no |
| `check_solution_config_drift` | Solution configuration | yes |
| `compare_public_api` | Diff, review and change gates | no |
| `compare_with_previous` | Snapshots and comparison | yes |
| `confidence_map` | Fact queries | no |
| `coverage_gaps` | Tests and coverage | yes |
| `describe_api_surface` | Orientation and server introspection | yes |
| `detect_circular_dependencies` | Dead code, cycles and metrics | yes |
| `diff_public_contract` | Snapshots and comparison | no |
| `diff_review` | Diff, review and change gates | no |
| `docs` | Orientation and server introspection | yes |
| `evaluate_change_set` | Diff, review and change gates | yes |
| `explain_symbol` | Symbol lookup and signatures | yes |
| `export_markdown` | Packing and exporting context | yes |
| `find_binding_usages` | Markup (XAML/AXAML) | yes |
| `find_by_attribute` | Fact queries | yes |
| `find_by_code_traits` | Fact queries | no |
| `find_by_complexity_and_coverage` | Tests and coverage | no |
| `find_by_concurrency_risk` | Fact queries | no |
| `find_by_event_subscription` | Fact queries | yes |
| `find_by_resource_leak` | Fact queries | no |
| `find_by_returns_semantic` | Fact queries | no |
| `find_by_semantics` | Fact queries | yes |
| `find_by_side_effects` | Fact queries | yes |
| `find_dead_code` | Dead code, cycles and metrics | yes |
| `find_god_objects` | Dead code, cycles and metrics | no |
| `find_implementations` | Hierarchy, implementations and lifecycle | yes |
| `find_overrides` | Hierarchy, implementations and lifecycle | yes |
| `find_production_dead` | Dead code, cycles and metrics | no |
| `find_resource_usages` | Markup (XAML/AXAML) | yes |
| `find_structural_twins` | Patterns and documentation drift | no |
| `find_symbol` | Symbol lookup and signatures | yes |
| `find_tests_for` | Tests and coverage | yes |
| `find_unresolved_bindings` | Markup (XAML/AXAML) | yes |
| `find_usages` | Fan-in, impact and paths | yes |
| `get_context` | Symbol lookup and signatures | yes |
| `get_diagnostics` | Session and analysis | yes |
| `get_insight` | Insights | yes |
| `get_type_hierarchy` | Hierarchy, implementations and lifecycle | yes |
| `impact_of_change` | Fan-in, impact and paths | yes |
| `import_constellation` | aicb database entities | no |
| `init_solution_config` | Solution configuration | yes |
| `inspect_session` | Session and analysis | no |
| `install_agent_hooks` | Agent wiring | yes |
| `instantiation_sites` | Fan-in, impact and paths | yes |
| `lifecycle_of` | Hierarchy, implementations and lifecycle | no |
| `list_constellations` | aicb database entities | no |
| `list_insight_producers` | Insights | no |
| `list_insights` | Insights | yes |
| `list_mcp_profiles` | Orientation and server introspection | yes |
| `list_remembered` | Cross-process memory | no |
| `list_run_templates` | aicb database entities | no |
| `list_sessions` | Session and analysis | no |
| `list_skills` | Orientation and server introspection | yes |
| `measure` | Multi-dispatch | yes |
| `pack_for_task` | Packing and exporting context | yes |
| `prepare_task` | Packing and exporting context | yes |
| `recall_codebase` | Cross-process memory | no |
| `refresh_remembered` | Cross-process memory | no |
| `refresh_session` | Session and analysis | yes |
| `remember_codebase` | Cross-process memory | no |
| `resolve_injection` | Dependency injection | yes |
| `review_context` | Diff, review and change gates | yes |
| `save_session` | Snapshots and comparison | yes |
| `semantic_diff` | Diff, review and change gates | no |
| `server_info` | Orientation and server introspection | yes |
| `solution_config_status` | Solution configuration | yes |
| `solution_metrics` | Dead code, cycles and metrics | yes |
| `symbol_metrics` | Dead code, cycles and metrics | yes |
| `symbol_signature` | Symbol lookup and signatures | yes |
| `trace_flow` | Fan-in, impact and paths | no |
| `type_dependency_path` | Fan-in, impact and paths | no |
| `usage_report` | Orientation and server introspection | yes |
| `verify_claim` | Diff, review and change gates | yes |

---

[&larr; 9 Tool reference: markup, export, review and insights](09-tool-reference-markup-export-review-and-insights.md) &middot; [Contents](README.md) &middot; [11 Configuration, drift and usage recording &rarr;](11-configuration-drift-and-usage-recording.md)
