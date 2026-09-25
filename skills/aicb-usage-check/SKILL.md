---
name: aicb-usage-check
description: Check at the end of a task whether the aicb MCP server was actually useful — what the agent reached for, what it never touched, where calls failed, and what it paid in latency. Reads the server's own recorded telemetry via usage_report. Use when the user asks "was aicb useful?", "did aicb help", "usage check", "hat aicb was gebracht", "Nutzungsauswertung", or wants to know which tools are going unused. Also when picking a leaner MCP profile, or when tool calls have been failing and you want the error classes. Not a code review and not a benchmark — it reports what was called, not whether the answers were right.
metadata:
  project: AIContextBuilder
  version: "1.0"
---

# Usage check — was aicb worth it?

One question, one call: **what did this server actually get used for?** The answer comes from
`usage_report`, which reads the tool-call rows the server itself wrote into its config database.
It is not your transcript and not a guess — it is the server's own record, and it spans every
client that used the same database, not only this conversation.

Run it at the **end** of a piece of work, not during. Mid-task the numbers are half a story, and
the interesting question — *what did I not reach for that would have fitted?* — only has an answer
once the work is done.

## The call

```
usage_report(sinceDays: 7, topTools: 20)
```

Both arguments are optional: omit `sinceDays` for the whole log (it is clamped to 1–3650),
`topTools` defaults to 30 (clamped to 1–200). **No session and no `.sln` path** — this tool takes
neither, so it answers on a server that has never analyzed anything.

If the answer carries `available: false`, the server is running without a config database and
records nothing. That is a real state, not an error: say so and stop, rather than reporting zeros
as if they were measurements.

## Read the scope before the numbers

**This is the step that decides whether your report is true.** The recorder sits on the
`tools/call` pipeline only, and the response repeats the boundary in `recordedVia` because your
client may be holding a cached copy of this tool's description.

- A sub-query inside `batch` or `measure` writes **no row of its own**. Recent-enough parent rows
  carry a per-tool tally in `subQueries` — read it, or an agent that works through `batch` looks
  idle.
- A one-shot `aicb call` invocation records **nothing at all**.
- Therefore **every count is a lower bound**, and a tool at zero was *not called through this
  door* — which is not the same as unused, and nothing like dead surface.

Say this in your report. A usage number presented without its denominator and its door is the
kind of confident wrong answer this whole product exists to avoid.

## What to look at, in this order

**1. Coverage — the adoption question.** `poolCoverage` gives `poolSize`, `poolToolsFired` and
`poolToolsNeverCalled`. This is the finding most reports miss: a pool of 54 with 27 fired means
half the offered surface went untouched. Cross the never-called list against what the work
actually involved, and name the two or three that *would have fitted* — a markup question answered
by grep while `find_binding_usages` sat unused, a "who creates this?" answered by reading files
while `instantiation_sites` was one call away. Everything else on that list is noise: most tools
are irrelevant to most tasks, and saying so is part of an honest report.

**2. Errors — and which kind.** `errorRatePct` alone means little; `errorClasses` is the histogram
that gives it meaning.

- `McpException` is a **guided refusal** — the tool said no on purpose (expired session, unknown
  token, a claim it will not make). A high rate here is the server working.
- Any other exception type is a **defect suspicion** worth chasing.
- `argumentBindingErrors` sits beside the histogram and cannot be derived from it: it counts the
  calls where the *caller* named an argument the tool does not have, so the call never reached the
  tool. Neither a defect nor a refusal — it means the tool's argument surface confused somebody,
  and if that somebody was you, name which tool.

**3. Cost — percentiles, not averages.** Latency here is right-skewed: one cold `analyze_solution`
drags `avgDurationMs` far above anything you experienced. Read `p50DurationMs` and
`p90DurationMs`, and treat `maxDurationMs` as the worst case rather than the typical one. Same for
`avgResultChars` versus `p50ResultChars` — result size is what the answers cost you in context.

**4. Who else is in these numbers.** `clients`, `clientEras` and `serverVersions` show every
harness that wrote to this database. If two clients appear, the totals are **not** your session:
either narrow with `sinceDays` and say what the window covers, or report the number as shared and
stop attributing it to this conversation.

## The judgement

Three questions, answered from the evidence above rather than from impression:

1. **Did the work reach for it at all?** Total calls against the size of the task. A wave with two
   calls used a search engine with extra steps.
2. **Did it answer?** Error rate read through `errorClasses`, plus whether the tools that fired
   were the ones the work needed.
3. **What was left on the table?** The two or three never-called tools that fitted — this is the
   part the user can act on.

Then say plainly whether it was worth it. "Useful" is a verdict, and a verdict with no downside
named is an advertisement. If grep would have been faster for part of the work, say which part.

## Output format

Short. A paragraph of verdict, then:

```
Window      : <sinceDays or "whole log">, <totalCalls> calls, <distinctSessions> sessions
Clients     : <clients>   (say if more than this session)
Reached for : <top 3-5 tools with call counts>
Via batch   : <top subQueries, or "none">
Errors      : <n> (<classes>; guided vs. suspicious)
Cost        : p50 <ms> / p90 <ms>, p50 <chars> result
Unused      : <n> of <poolSize> never called top-level — of those, <the ones that fitted>
```

Close with the one change worth making: a tool to reach for next time, a leaner profile, or
nothing.

## Limits — state them, do not work around them

- **It reports calls, not correctness.** Nothing here says an answer was right. A tool with 100
  calls and no errors may have been confidently wrong every time.
- **It cannot see a transcript.** Reasoning, reading and grepping leave no row, so "aicb was 80 %
  of the work" is not a claim this data supports.
- **It is cross-client by design.** That is its strength over any transcript-based view — it sees
  a foreign harness at all — and the reason its totals are not yours.
- **A zero is never proof.** See the scope section; repeat it in the report rather than trusting
  the reader to remember.
