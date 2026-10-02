# AICB Roslyn MCP

Roslyn-based code intelligence for C#/.NET, for coding agents. This plugin connects the
AIContextBuilder (AICB) MCP server to Claude Code and adds four Agent Skills. Claude then
answers questions about a C# solution from the compiler's symbol graph instead of text
search: who calls a method, what a change breaks, where an interface is implemented,
which tests cover a symbol, what dependency injection resolves, plus side effects, dead
code and dependency cycles. It can also pack the relevant code into token-budgeted
Markdown context.

AICB does not edit your code. It tells the agent what a change will touch before the edit.

## Requirements

Install the AICB .NET tool once per machine. The plugin starts it; it does not contain it.

```
dotnet tool install -g aicb-roslyn-mcp
```

- The tool needs the .NET 8 SDK. Without .NET 8 it runs on the next newer .NET on the
  machine and needs that version's SDK, so just the .NET 10 SDK works.
- On Windows, the [installer](https://github.com/gregordadera/aicb-roslyn-mcp/releases/latest)
  contains the same server and CLI. Install one form per machine, and keep its option
  that adds `aicb` to the PATH.
- `aicb --version` prints the installed version. Update with
  `dotnet tool update -g aicb-roslyn-mcp`.
- Windows, Linux or macOS.
- Claude Code, or a Cowork session that runs on your own computer. Chat on claude.ai
  loads the skills but does not start local MCP servers.

## What the plugin runs and fetches

When the plugin loads, Claude Code starts one local process:

```
aicb mcp
```

- That is the tool you installed. The plugin contains no program and downloads nothing.
- If `aicb` is not installed or not on the PATH, the server shows as failed in `/mcp`.
  Install the tool, then reconnect the server there or restart Claude Code.
- The server speaks MCP over stdio and opens no port.
- It reads the solution you point it at. Opening a solution runs its MSBuild logic, and
  building its compilation runs the source generators its projects reference, as in an IDE
  or `dotnet build`. Analyze only solutions you trust.
- It does not modify the source code it analyzes. A small number of explicitly named tools
  can write configuration or an export; their tool descriptions say so.

## Data

- The CLI and MCP server have no outbound network capability. There is no outbound
  telemetry, analytics, update check, account or license server.
- The MCP server records its own tool calls in a local SQLite database for the
  `usage_report` tool. That log never leaves the machine.
- The plugin itself causes no network access. The one download is the install command
  above, which you run yourself: the .NET SDK fetches the package (about 32 MB) from
  nuget.org.

Details: [Data, storage and privacy](https://github.com/gregordadera/aicb-roslyn-mcp/blob/main/docs/manual/general/10-data-storage-and-privacy.md)
and [SECURITY.md](https://github.com/gregordadera/aicb-roslyn-mcp/blob/main/SECURITY.md).

## Use it

Ask in a repository that contains a C# solution. Name the solution if the folder holds
more than one:

- "Who calls `OrderService.Submit`, and what breaks if I add a parameter?"
- "Where is `IPriceCalculator` implemented, and which tests cover it?"
- "What does dependency injection resolve for `IEmailSender`?"
- "Find dead code and dependency cycles in `Shop.sln`."

Every analysis tool accepts the absolute `.sln`, `.slnx` or `.slnf` path directly, so
there is no separate analyze step. To check the connection, ask Claude to call
`server_info`. The default profile exposes 54 tools; the
[tool reference](https://github.com/gregordadera/aicb-roslyn-mcp/blob/main/docs/TOOLS.md)
lists them, and the [MCP server manual](https://github.com/gregordadera/aicb-roslyn-mcp/blob/main/docs/manual/mcp/README.md)
covers sessions, profiles and every parameter.

## Skills in this plugin

- `aicb-csharp-context` routes semantic C# questions to the right tool.
- `aicb-code-review` checks a completed change for correctness.
- `aicb-code-simplifier` looks for unnecessary complexity.
- `aicb-usage-check` reports what the server was actually reached for.

## If you already use `aicb init`

`aicb init` writes a project `.mcp.json` with the same command, `aicb mcp`. Claude Code
treats the plugin's server as a duplicate of that entry and connects once, so a project
set up with `aicb init` and this plugin work side by side. `aicb init` can also install a
symbol guard for the project; the plugin does not.

## License

AICB is closed-source software under the AIContextBuilder End-User License Agreement.
Use is free for private, hobby and educational use by natural persons, for accredited
educational institutions, and for organizations that reach none of these thresholds:
100 employees, EUR 10 million annual turnover, 21 developers. See `LICENSE` in this
folder, the [plain-language guide](https://github.com/gregordadera/aicb-roslyn-mcp/blob/main/docs/LICENSING.md)
and the full bilingual [EULA](https://github.com/gregordadera/aicb-roslyn-mcp/blob/main/EULA.md).

## Support

Questions and feature requests: [GitHub Discussions](https://github.com/gregordadera/aicb-roslyn-mcp/discussions).
Bugs: [GitHub Issues](https://github.com/gregordadera/aicb-roslyn-mcp/issues), with the
output of `aicb --version` and `server_info`. Security issues: privately, as described in
[SECURITY.md](https://github.com/gregordadera/aicb-roslyn-mcp/blob/main/SECURITY.md).
Contact: `aicb@dadera.de`.
