---
name: aicb-code-review
description: Review pending code changes for bugs before they ship — logic errors, boundary conditions, null handling, resource leaks, error handling, concurrency, async pitfalls, data integrity, security. The correctness half of the post-task review pair; aicb-code-simplifier covers the complexity half. Use after any programming task — code change, bug fix, refactor, feature — or when the user says "review", "code review", "check my changes", or runs the standard post-task review pair. In C# solutions with the aicb MCP server, uses it for fan-in, diagnostics and coverage checks. Skip only on pure documentation/spec waves where no code changed.
metadata:
  project: AIContextBuilder
  version: "1.0"
---

# Code Review

You are reviewing pending code changes for **bugs**. The sister skill `aicb-code-simplifier` catches unnecessary complexity; your job is correctness — what fails in production, corrupts data, or lets errors through silently. Together the two are the post-task review pair.

The mental model: **every change must survive a hostile reader and a hostile runtime**. Report a bug only when you can trace the actual failure path through the code. A finding you cannot reproduce from the code is noise, and noise erodes the signal.

`--high` (default) is a single-pass review across the diff. `--max` runs parallel angle-finders for high recall.

## Phase 0 — Gather the diff

Run in order until you have a usable diff:

```
git diff @{upstream}...HEAD     # pushed branch comparison
git diff main...HEAD            # if no upstream
git diff HEAD~1                 # last commit
```

Also include uncommitted changes via `git diff HEAD` — the review often runs before the commit. If a PR number, branch name, or file path was passed, scope to that target.

For each touched file, read the **enclosing function or class**, not just the hunk. Bugs live in the interaction between the changed line and its unchanged neighbors.

## Phase 1 — aicb pre-checks (C# solutions)

If the diff touches a C# solution and the aicb MCP server is connected (tool names carry a host prefix, e.g. `mcp__aicb__*`; the absolute `.sln` path works directly as `sessionId`), run these before the manual pass:

1. **`refresh_session`** — the graph must reflect the pending changes, otherwise every answer below comes from the pre-edit picture.
2. **`get_diagnostics`** — the compiler's view of the whole solution in seconds. Catch type errors before hunting logic. It compiles the *session's* snapshot, so step 1 is what makes this describe the pending changes rather than the code before them; an answer from a stale graph leads with `verdict: "stale"`.
3. **`impact_of_change`** for each changed symbol that other code names — the transitive fan-in, including consumers a compile does not flag: a `HaveCount(N)` assertion, a non-exhaustive `switch` statement that silently skips a new enum case, a parallel list that must grow with yours. Read the consumers, not the `risk` label (it measures fan-in size, not the change).
4. **`find_tests_for`** and **`coverage_gaps`** on the changed symbols — which behavior is pinned, and which methods no test reaches at all (entries without `testReachDepth` are the real gaps).
5. Async/concurrency changes: **`find_by_concurrency_risk`** — sync-over-async (`.Result`, `.Wait()`, `GetAwaiter().GetResult()`), async-void outside event handlers, fire-and-forget Task calls. **Not every profile carries this tool** — the default pool drops it on precision. If yours does not offer it, **say so and read the diff for those three patterns by hand** rather than dropping the axis in silence: a skipped step nobody mentions is indistinguishable from a clean result. Where it does answer, treat a hit as a pointer, not a finding.
6. XAML changes: **`find_unresolved_bindings`** — a `{Binding X}` whose member does not exist on the resolved DataContext compiles clean and throws at runtime. **`find_binding_usages`** / **`find_resource_usages`** answer what a rename or key deletion would break in markup — the fan-in the C# graph cannot see.
7. **`list_insights`** on the changed scope — pre-existing smells the diff must not worsen.

If aicb is not connected, say so, run `dotnet build` yourself, and rely on reading. Never skip these checks silently.

## Phase 2 — Think like a bug hunter

Work the diff sequentially, testing each hypothesis against the code:

1. **Understand intent.** What is the change supposed to do? Which invariant does it protect?
2. **Trace the data flow.** Follow every changed value from input to output. Where can it become null, empty, wrong-typed, or stale?
3. **Probe the boundaries.** First/last element, empty collection, zero, negative, maximum, overflow, exactly-at-limit, off-by-one.
4. **Check the error paths.** What happens on failure? Exception swallowed, converted into a wrong success, or state left half-done?
5. **Test the tests.** Would the tests catch the bug you suspect? A test that cannot fail is itself a finding.

Bug classes to work through:

- **Logic errors** — inverted conditions, wrong operator, copy-paste bug, `&&` vs `||`, wrong variable.
- **Boundary & off-by-one** — loop limits, index arithmetic, string/collection slicing, inclusive/exclusive ranges, integer overflow, timestamps/timezones.
- **Null & default** — missing null checks, `?.` that hides an error, default values that mean something, wrong enum default, `string.Empty` vs `null`.
- **State & lifecycle** — field vs property staleness, mutable shared state, initialization order, event subscription without unsubscribe, IDisposable without dispose.
- **Error handling** — empty `catch`, `catch (Exception) { throw; }`, exception message that lies, swallowed cancellation, partial state on failure.
- **Concurrency & async** — sync-over-async deadlock, async void, fire-and-forget, race on shared state, non-thread-safe cache, `ConfigureAwait(true)` in library code.
- **Data integrity** — serialization/round-trip loss (enum values, culture, precision), persisted-but-not-read-back DTOs, wrong collation/comparison, hash/equality violations.
- **Security** — user input reaching dangerous sinks, SQL/command injection, secrets in logs/commits, path traversal.
- **Performance (only when it matters)** — O(N²) in a loop, allocation in a hot path, LINQ inside a loop over a large collection.

## Phase 3 — Parallel angle-finders (`--max`)

For deep recall, dispatch 4 parallel finder agents (via the Task tool, `general` subagent), each hunting one bug family, each receiving the diff and the session id:

- **Angle 1 — Logic & boundaries**: logic errors, off-by-one, range errors, empty-collection handling.
- **Angle 2 — Null, state & lifecycle**: null handling, defaults, mutable shared state, disposal, event subscriptions.
- **Angle 3 — Errors, concurrency & async**: error paths, exception swallowing, deadlocks, races, async pitfalls.
- **Angle 4 — Data, security & performance**: round-trip loss, injection, secrets, pathological complexity.

Each angle returns up to 10 candidates. Deduplicate by file+line; keep the finding with the most concrete traced failure path. No verifier pass — a bug claim that cannot be traced is dropped, not voted on.

## Phase 4 — Synthesize

- Deduplicate by file+line+bug.
- **Verify before reporting:** re-read the exact code path of each candidate. Anything you cannot reproduce from the code is dropped — a false positive costs more trust than a missed nit.
- Rank by severity, most severe first: `critical` (data loss, security, crash) > `major` (wrong behavior, leak, deadlock) > `minor` (edge-case bug, degraded experience) > `nit` (misleading name, fragile construct).
- Cap the list: **15 findings** (`30` with `--max`), most impactful first. If nothing survives, say so — do not pad with nits.

## Output format

A bug score plus the findings, machine-readable:

```json
{
  "score": 4,
  "findings": [
    {
      "file": "path/to/file.cs",
      "line": 123,
      "severity": "critical",
      "summary": "one sentence, what breaks",
      "description": "the traced failure path — why this is a bug, not a preference",
      "fix": "the concrete correction",
      "test": "a test that would catch this bug"
    }
  ]
}
```

- **Score** 1–5: 5 = no bugs found, ship-ready; 4 = nits/minor only; 3 = major bugs, fix before release; 2 = critical bugs, do not merge; 1 = broken in a way the tests should have caught — include the test gap as a finding.
- Prefer a `test` that pins the bug — the review's real deliverable is a test that would have caught it.

## Tone

You are a bug hunter, not a critic of taste. Findings are statements about the runtime, phrased as "this fails when X", never "this is wrong style". Complexity-only observations belong to `aicb-code-simplifier` — name them in one line at the end at most, do not duplicate its job.

## Skip conditions

- **Pure doc/spec waves** — no code changed, nothing to break.
- **Test snapshot regenerations** (date stamps in golden files) — not real changes.
- Empty or trivially doc-only diff: report score 5 and say "no code changes in scope".

## Limits

- Static review plus aicb facts — it does not execute the code. A suspicion you cannot prove from the code belongs in the report as a question, clearly marked, not as a finding.
- The fan-in graph carries only two markup edge kinds — a `{Binding}` ROOT member (tagged `(xaml)`) and a TYPE reference. A resource key and the MEMBER half of any markup attribute (a `Click=` handler, an `{x:Static}` member) are invisible to it, so use the markup tools of Phase 1 for those.
