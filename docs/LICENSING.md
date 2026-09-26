# Licensing in plain words

This page explains the licence without legal language. The binding text is
[`EULA.md`](../EULA.md) (German and English); [`LICENSE.txt`](../LICENSE.txt) is the
short summary. The full versioned EULA and that summary ship with every distribution.

## Free — no strings attached

- **You as a person**, for private use, hobby or learning.
- **Schools, universities and other accredited educational institutions**, for
  teaching, learning and non-commercial research.
- **Any organization below all three thresholds:**
  - fewer than **100 employees**,
  - less than **EUR 10 million** annual turnover,
  - fewer than **21 developers**.

  A subsidiary counts together with enterprises under common direct or indirect
  control. A minority participation without control does not by itself join two
  organizations.

Employees are counted by headcount. A developer is a natural person who writes,
modifies or reviews source code for the organization; an automated system or LLM
agent is not an additional developer for this threshold.

## Consultants and freelancers

The thresholds measure **your own** organization. Working for a large client — even
on their premises, even for months — does not change anything. A one-person
consultancy stays free no matter who it works for.

## When a licence is needed

As soon as your organization reaches **one** of the three thresholds, a **90-day
contractual transition period** begins. Use stays free during that period; a
commercial licence is required to continue afterwards. The 90 days are text in the
agreement, not a product feature: AICB starts no timer, sends no threshold or
deadline data, blocks no feature and does not technically stop working when the
period ends. Terms are agreed individually — write to **aicb@dadera.de**.

## What a commercial agreement can include

Commercial licences **start at EUR 10 per licensed developer per month**. The exact
price depends in particular on:

- the number of users covered by the licence;
- the requested support scope and response expectations;
- any agreed priority or delivery commitment for improvement requests.

Support typically compares like this:

| | Free licence | Commercial agreement |
| --- | --- | --- |
| Support channel | GitHub Discussions and Issues | Direct contact plus the public channels |
| Response target | Best effort | ≤ 2 business days |
| Security fixes | Shipped through public releases | Fix target ≤ 10 business days for confirmed vulnerabilities |
| Version maintenance | Current release | Individually agreed maintenance window |
| Improvement requests | Community-driven | Prioritized consideration; agreed priorities are written into the contract |
| Source access | None | Code review under NDA can be agreed |

The table shows typical targets. Depending on the agreement, the commercial
relationship can include product support, defined response or version-maintenance
commitments, and prioritized consideration or implementation of requested
improvements. One example is studying patterns in the customer's codebase and
improving an analyzer or MCP workflow so it handles that class of code more
accurately.

Customer code is never collected or used for improvement automatically. Examining
customer code or derived patterns requires material or access the customer
deliberately provides and a separate agreement on scope, confidentiality and
retention. Source-code review under NDA is a commercial-licence option that gives
the customer audit insight into AICB without releasing the code.

That does not turn AICB into a customer-specific product: accepted improvements are
designed as general capabilities and become part of the general AICB product rather
than a specialized fork tied to one codebase. The exact support level, response
times, maintenance period, priorities and promised deliverables are whatever the
individual written agreement says; payment alone does not silently create an
unstated SLA or implementation guarantee.

## No technical licence enforcement

There is no activation, licence key, licence server, watermarking or phone-home, and
there is no outbound licensing telemetry. Nothing in the software checks the
thresholds or the 90-day period. The MCP server can record tool calls locally for
`usage_report` and the desktop app's MCP Usage view; that local operational log is
not used for licensing and never leaves the machine. Staying within the terms is
your responsibility.

## Donations are separate

If `aicb` helps you, a [sponsorship](https://github.com/sponsors/gregordadera) is
welcome. It is a thank-you, not a licence: a donation never replaces a commercial
licence where one is required, and being below the thresholds never requires a
donation.

## What is not allowed

Redistributing, modifying, repackaging, re-branding or reselling the AICB software
itself; bundling its binaries into another product; offering it as a hosted/shared
service for direct third-party use; and building a competing product from the
software. Reverse engineering is allowed only where mandatory law permits it.

Normal use through the documented interfaces is allowed: connect AICB to MCP
clients, agent harnesses, scripts, build systems and CI/CD. Consultants may use it
internally while serving clients. You keep all rights in your source code and may
use, adapt, version and share AICB-generated context, exports, `.aicb.json` sidecars
and files installed by `aicb init`, subject to rights in the underlying material.
