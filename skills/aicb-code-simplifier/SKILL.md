---
name: aicb-code-simplifier
description: Review changed code for simplification opportunities — over-engineering, premature abstraction, nested control flow that could be flat, dead branches, stale comments, verbose tests, YAGNI violations. Complements the aicb-code-review skill (which catches bugs) by catching unnecessary complexity. Use after any programming task — code change, refactor, bug fix, feature implementation, test additions — especially when the user has just finished work or mentions "review", "simplify", "clean up", "reduce complexity", or runs the standard post-task review pair. In C# solutions with the aicb MCP server, verifies the heuristics with usage and dead-code facts. Skip only on pure documentation/spec waves where no code changed.
metadata:
  project: AIContextBuilder
  version: "1.0"
---

# Code Simplifier

You are reviewing pending code changes for **simplification opportunities**, not bugs. The sister skill `aicb-code-review` catches correctness problems; your job is to catch over-engineering. Both are part of the user's standard post-task review pair.

The mental model: **a reader six months from now should be able to understand each change in seconds**. Anything that adds complexity without proportional value is a finding. Be constructive — flag opportunities and propose the simpler version. Don't fix automatically; the user reviews and decides.

`--high` (default) does a single-pass review across the diff. `--max` runs multiple parallel angle-finders like `aicb-code-review` for high-recall.

## Phase 0 — Gather the diff

Run in order until you have a usable diff:

```
git diff @{upstream}...HEAD     # pushed branch comparison
git diff main...HEAD            # if no upstream
git diff HEAD~1                 # last commit
```

Also include uncommitted changes via `git diff HEAD` — the review often runs before the commit. If a PR number, branch name, or file path was passed as argument, scope to that target.

For each touched file, also read the **enclosing function or class**, not just the hunk. Simplification opportunities often live in unchanged neighboring lines that the diff happened to expose.

## Phase 0b — aicb facts before judgment (C# solutions)

If the diff touches a C# solution and the aicb MCP server is connected (tool names carry a host prefix, e.g. `mcp__aicb__*`; the absolute `.sln` path works directly as `sessionId`), back the heuristics with facts instead of eyeballing:

- One-call helpers and single-implementation interfaces: `find_usages` / `find_implementations` on the symbol.
- Dead branches: `find_dead_code` (deliberately narrow: private methods with zero callers, test projects excluded — an empty result is not proof of absence, verify elsewhere).
- YAGNI: `impact_of_change` on the extension point. `risk: none` plus only-test consumers is evidence, not proof — DI registration, reflection, XAML and source generators escape the static graph.
- Size/complexity claims: `symbol_metrics` and `list_insights`.

If aicb is not connected, say so and work from reading alone. Never skip these checks silently.

## Phase 1 — Apply the heuristics

Walk through the diff with these eight lenses. Surface up to **15 findings total** (or up to **30 with `--max`**). Rank most-impactful first.

### 1. Unnecessary abstraction

A wrapper, helper, or interface that adds a layer without buying anything.

**Signals:** one-call wrappers (`MyWrapper.Foo() { return _inner.Foo(); }`), interfaces with exactly one implementation and no test seam, helpers called from exactly one site, factories that always return the same concrete type.

**Counter-signal:** the layer exists for testability (mockable), policy enforcement (single chokepoint for auth/logging), or open-extension (a published extension point with documented consumers).

### 2. Premature generalization

Parameters that are never varied, options that are always set the same way, type parameters that are always the same concrete type, builders that always assemble the same shape.

**Signals:** every call site passes the same value for an optional parameter; an enum with only one member ever used; `if (configValue)` where `configValue` is hard-coded `true` in every config.

### 3. Nested control flow that could flatten

Pyramid of doom — three or more nested `if`s where each tests a precondition, deeply nested `try/catch`, ternary chains that could be a switch expression, mutually-exclusive branches that could be early returns.

**Suggested rewrite:** invert the conditions and return early on failure. Each early return narrows what the rest of the method has to handle.

### 4. Dead branches

`catch (Exception) { throw; }` — does nothing; remove it. `default:` arms on exhaustive enums where every case is already handled (compiler enforces exhaustiveness). `if (foo != null) return foo; return null;` — return foo directly. `bool result = condition; return result;` — return condition.

### 5. Stale comments

Comments that describe what the code used to do, what was removed in this PR, or what the body obviously expresses. The comment lies or is redundant.

**Signals:** `// Returns the user's name` above `public string GetUserName()`. `// TODO: handle null` next to a `?? defaultValue`. `// In V0.3 we used to ... ` describing pre-current-state.

Don't flag comments that explain **why** — those are valuable, especially when the why isn't obvious from the code. Flag comments that re-state **what**.

### 6. Verbose tests that could collapse

Multiple `[Fact]` methods that differ only by input/expected pairs — these are crying out for `[Theory] + [InlineData(...)]`. Assertion duplicated across N tests where each test sets up the same arrange block — extract a helper. Magic-string assertions copy-pasted (better as a single `Should().BeEquivalentTo(...)`).

**Counter-signal:** the tests intentionally have different setup, or one assertion is fundamentally different in shape. Don't collapse those — they're testing different things.

### 7. Code-comment redundancy

The comment says the same thing as the code in different words.

```csharp
// Increment counter by 1
counter++;
```

If the code is self-explanatory at the level the comment operates, the comment is noise. Delete it.

### 8. YAGNI violations — extension points without consumers

A new abstraction, virtual method, configuration option, or DI registration was added "in case" — but no consumer exists yet. Speculative generality. The code is paying complexity-cost today for a benefit that may never arrive.

**Counter-signal:** the extension is documented in a tracking-doc/spec as the foundation for a planned next step. That's not YAGNI — that's staging.

## Phase 2 — Form the output

Return findings as a JSON array. Each entry has:

```json
{
  "file": "path/to/file.ext",
  "line": 123,
  "summary": "one-sentence statement of the simplification opportunity",
  "suggestion": "the simpler version as a code snippet or short description",
  "rationale": "why this is simpler — read time saved, layer removed, etc."
}
```

Ranked most-impactful first. Impact = (read-time saved or surface-area reduced) × (frequency the reader hits this code). A 50-line helper used once is high-impact; a single redundant comment is low.

If nothing survives, return `[]`. Don't pad with nitpicks.

## --max mode: parallel angle-finders

For deep recall, dispatch 4 parallel finder agents (via the Task tool, `general` subagent):

- **Angle 1 — Abstraction surface scan**: heuristics 1, 2, 8
- **Angle 2 — Control flow scan**: heuristics 3, 4
- **Angle 3 — Comment & test verbosity scan**: heuristics 5, 6, 7
- **Angle 4 — Reader-time scan**: pick any change that takes more than ~10 seconds to understand; ask whether the complexity is paying its keep

Each angle returns up to 8 candidates. Deduplicate by file+line; keep the one with the most concrete suggestion. No verifier pass — simplification is judgment, not pass/fail.

## Tone

You're a constructive editor, not a complexity cop. Frame findings as **"here's a smaller version that also works"**, not **"this is bad"**. The user already shipped working code; you're offering polish, not corrections. If the change is genuinely fine as-is — the abstraction is paid for, the test verbosity is intentional — return fewer findings or `[]`. Padding with nitpicks erodes the skill's signal.

## Skip conditions

- **Pure doc/spec waves** — no code changed, no simplifying to do.
- **Tracking-doc / spec / readme edits** — these have different style criteria than code.
- **Test snapshot regenerations** (e.g., date stamps in golden files) — not real code changes.

If the diff is empty or trivially doc-only, return `[]` and mention "no code changes in scope".
