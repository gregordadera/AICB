# Getting started

This page takes you from nothing to a coding agent that asks `aicb` instead of
grepping — in about five minutes. The full reference manuals are in English.

## 1. Pick your form

| You want … | Install | Runs on |
|---|---|---|
| your coding agent (Claude Code, Codex, Cursor, …) to understand your C# code | the `aicb` .NET tool from [nuget.org](https://www.nuget.org/packages/AIContextBuilder) | Windows, Linux, macOS |
| to decide by hand what a model gets to see, and look at the result | the desktop app from [GitHub Releases](https://github.com/gregordadera/AICB/releases) | Windows |

Both share one analysis engine. The desktop download also contains the CLI, so on
Windows one download covers both.

## 2. Prerequisites

- **To analyze a solution you need MSBuild on the machine** — a .NET SDK or Visual
  Studio. This applies to every form: opening a solution runs its MSBuild design-time
  build, and without MSBuild nothing can be loaded.
- **The .NET tool additionally needs the .NET 8 SDK** (it is what installs and runs a
  .NET tool).
- The desktop app and the ZIP bring their own .NET runtime; nothing else to install.

## 3. Install

**Pick one per machine.** On Windows with the desktop app, install only the desktop
app: it contains the MCP server and CLI too, and one update brings both to the same
version. Everywhere else (Linux, macOS, CI, no desktop app), install only the .NET
tool. With both installed, the installer's `aicb` is the one that runs and
`dotnet tool update` updates a copy nothing starts - so the installer offers to remove
an existing .NET tool (preselected), and `aicb init` warns when it finds two.

### The .NET tool (MCP server + CLI)

```sh
dotnet tool install -g AIContextBuilder
aicb --version
```

Update later with `dotnet tool update -g AIContextBuilder`. The package page is
[nuget.org/packages/AIContextBuilder](https://www.nuget.org/packages/AIContextBuilder).

Without access to nuget.org (an offline or locked-down machine), the same package is
attached to every [release](https://github.com/gregordadera/AICB/releases/latest):
put the `.nupkg` into an otherwise empty folder and add
`--add-source ./that-folder` to the install command.

### The desktop app (Windows)

From the [latest release](https://github.com/gregordadera/AICB/releases/latest):

- **`AIContextBuilder-Setup-<version>.exe`** — installer. Needs administrator rights.
  The option to put `aicb` on `PATH` is preselected; keep it if you want to use the
  bundled CLI as your MCP server. Consoles, editors and agents that were already open
  see the new `PATH` only after a restart.
- **`AIContextBuilder-<version>-win-x64.zip`** — portable. Unzip anywhere, no
  administrator rights: `gui\aicb-ui.exe` is the desktop app, `cli\aicb.exe` the CLI.
  Uninstall = delete the folder.

The files are **not code-signed yet**. Windows SmartScreen therefore shows *"Windows
protected your PC"*; choose *More info → Run anyway*. The release notes list a
SHA-256 checksum for every file, so you can verify what you downloaded:

```powershell
Get-FileHash .\AIContextBuilder-Setup-<version>.exe -Algorithm SHA256
```

## 4. Wire it into your project

From your project directory:

```sh
aicb init
```

This writes an `.mcp.json` entry and the
[`aicb-csharp-context`](../skills/aicb-csharp-context/SKILL.md) agent skill, and
reports what it did per file. It never overwrites (`--force` does), so running it
again is safe.

**Know this before it happens:** if your project has a folder for an agent harness
aicb knows (`.claude/`, `.codex/`, `.opencode/`), `aicb init` also installs the
**symbol guard** there. The guard *refuses* a C# symbol search by grep or file read and
points the agent at the aicb tool that answers it properly. That is what makes the
tools actually get used — and it is the one part of the install that changes what
your agent may do. To skip it: `aicb init --hooks none`. To remove an installed guard,
delete the aicb entry from `.claude/settings.json`, `.codex/hooks.json` or
`opencode.json`.

### Doing it by hand

The server is started as `aicb mcp` over stdio. For clients that read `.mcp.json`
(Claude Code, among others):

```json
{
  "mcpServers": {
    "aicb": { "command": "aicb", "args": ["mcp"] }
  }
}
```

If you use the ZIP without `PATH`, put the absolute path of `cli\aicb.exe` into
`command`. **OpenCode does not read `.mcp.json`** — add the same command (`aicb`,
argument `mcp`) to its own `opencode.json` as described in OpenCode's MCP
documentation.

## 5. Check the connection

MCP clients read their server list **at start**. After `aicb init` (or any change to
the configuration), restart the client, then ask your agent:

> Call the MCP tool `server_info` and show me the answer.

`server_info` needs no solution and no MSBuild; if it answers with a version, the
wiring is done.

## 6. Ask your first question

Every tool accepts the **absolute path of your `.sln`** directly as its session — no
separate "analyze" step:

> Who uses `OrderService.Validate`? Use `C:\repo\MyApp\MyApp.sln` as the session.

The first call analyzes the solution, which takes from seconds to a few minutes
depending on its size; later calls reuse the warm session.

| Ask your agent … | Tool it reaches for |
|---|---|
| Who calls X? | `find_usages` |
| What breaks if I change X? | `impact_of_change` |
| Which tests cover X? | `find_tests_for` |
| Where is this interface implemented? | `find_implementations` |
| What is X and what depends on it? | `explain_symbol` |
| What has side effects / touches the database? | `find_by_side_effects` |
| What is dead? | `find_dead_code` |
| Which compiler errors do I have right now? | `get_diagnostics` |

After editing code: `refresh_session` first, **then** `get_diagnostics` — diagnostics
are computed from the session's snapshot, not from the files on disk.

The server documents itself: the `docs` tool is its built-in manual, `list_skills` the
map of all tools. A generated reference of the default tool set is in
[`TOOLS.md`](TOOLS.md).

## 7. The desktop app in one minute

1. Start *AI Context Builder*. The start page offers the bundled sample solution
   `ColorMixer.SelectionLab` — a good first run.
2. Open a solution in **Workspace** (`+` or *Open*; `.sln`, `.slnx` and `.slnf` work) and
   let the analysis finish.
3. In the **Context Builder**, tick the types and methods the model should see, choose
   a detail level per node and watch the token estimate.
4. **Create MD** renders the context document. Copy it, save it, or send it to a model
   you configured under *Settings → Model Profiles* — the only moment anything leaves
   your machine.

## 8. Where your data lives

- Settings and the database: `%APPDATA%\AIContextBuilder` on Windows. Install, update
  and uninstall leave it alone — it is your work, not installation state.
- **The desktop app and the MCP server share one database.** A newer version migrates
  it on first start; an older version then refuses to write to it rather than damage
  it. Do not run a newer and an older copy side by side on the same database.

## 9. If something does not work

| Symptom | What to do |
|---|---|
| `MSBuild not found` | Install a .NET SDK (https://dotnet.microsoft.com/download) or Visual Studio, then restart. |
| The aicb tools do not appear in your agent | Restart the client — it reads its server list only at start. Then `server_info`. |
| `Tool '<name>' is not in the active profile` | The default pool is a lean core. `list_mcp_profiles` shows the pools; `aicb mcp --mcp-profile mcp-profile/full` serves all tools. |
| The first question takes long or reports "gave up waiting" | The first analysis is still running. Wait and ask again, or analyze a smaller solution filter (`.slnf`). |
| Freshly written code is reported `not_found` | The session has not seen it yet. `refresh_session`, then ask again. Answers carry a `staleness` note — read it. |
| `Connection closed` | Restart the client so it restarts the server. |

Still stuck? Open an [issue](https://github.com/gregordadera/AICB/issues) with
`aicb --version`, the `server_info` answer and — for the desktop app —
`%APPDATA%\AIContextBuilder\aicb.log`. If GitHub does not offer a **New issue**
button, use [Discussions](https://github.com/gregordadera/AICB/discussions).
Never attach your source code.
