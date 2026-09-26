[AICB – General Documentation](README.md) &middot; chapter 2 of 12

# 2 License, installation and updates

AIContextBuilder is closed source: you install a released build, and there is no source code to compile. This chapter covers the license terms, the channels the product ships through, what your machine needs before it can analyze anything, how to install and update each form, and how to uninstall it and remove every file it has written.

## 2.1 The license

AIContextBuilder is licensed under the AIContextBuilder End-User License Agreement (EULA). The full bilingual agreement `EULA.md` and its non-binding orientation summary `LICENSE.txt` are shipped with every distribution form and packed into the NuGet package. The public current text is https://github.com/gregordadera/AICB/blob/main/EULA.md; the immutable reference for version 0.4 is https://github.com/gregordadera/AICB/blob/eula-v0.4/EULA.md. The German version is binding for natural persons habitually resident in Germany and organizations with their registered office or principal place of business in Germany; the English version is binding for other licensees unless an individual agreement selects the German version.

### Free use below three thresholds

Use is free of charge for as long as your organization reaches **none** of these thresholds:

| Threshold | Value |
|---|---|
| Employees | 100 |
| Annual turnover | EUR 10,000,000 |
| Developers | 21 |

Reaching or exceeding even one of them starts the commercial-license transition described below. "Organization" means you together with enterprises under common direct or indirect control: a subsidiary is counted together with its group. The control tests in Article 3(3) of EU Recommendation 2003/361/EC determine linked enterprises. A minority participation without control does not by itself join two organizations, and the thresholds in that recommendation do not apply; only the three values above are authoritative.

How the terms are counted:

| Term | Counted as |
|---|---|
| Employees | all persons working for the organization, regardless of the form or extent of their engagement; counted as headcount, not as full-time equivalents |
| Developers | every natural person who, in the course of their work for the organization, writes, modifies or reviews source code, regardless of job title, form or extent of engagement. People who only plan, coordinate or test software without reference to source code are not counted. Automated systems and LLM agents are not natural persons and do not count as additional developers |
| Annual turnover | the consolidated turnover of the organization in its most recently completed financial year; foreign currencies are converted at the European Central Bank reference rate on the balance sheet date. For organizations without turnover in the commercial-law sense, this condition is disregarded |
| Assessment date | the end of each financial year, and any other point at which documented facts show that a threshold has been reached or exceeded |

Always free of charge, regardless of the thresholds:

- **Natural persons** using the software privately, as a hobby, or for education.
- **Accredited educational institutions** for teaching, learning and non-commercial research. Commercial activities of the institution, in particular contract research, fall under the normal rules.
- **Work for clients:** the thresholds measure your organization only. The size of your clients does not matter, including when you work on their premises.
- **Public bodies** fall under the normal thresholds; there is deliberately no separate clause for them.

### When a commercial license is required

If your organization reaches or exceeds one threshold, a **90-day contractual transition period** begins. Use stays free of charge during that period; a written commercial license is required to continue afterwards. Commercial licences start at EUR 10 per licensed developer per month; terms are agreed individually, and price and scope can depend on licensed users, requested support and response scope, and agreed priority or delivery commitments for improvement requests. A commercial agreement may include support with defined response and security-fix targets (for example, answers within two business days and fixes for confirmed vulnerabilities within ten business days), version maintenance, prioritized general product improvements and source-code review under NDA; payment alone creates no unstated SLA or implementation promise. Contact **aicb@dadera.de**.

The 90 days are contractual text only. The software starts no timer, transmits no threshold or deadline data, blocks no feature and does not technically stop when the period ends. There is no license server, activation token, watermarking or outbound licensing telemetry. The MCP server can record tool calls locally for `usage_report` and the desktop app's MCP Usage view; these data are not used for licensing and never leave the machine. Compliance is your responsibility.

Customer code is never collected or used for product improvement automatically. Any examination requires material or access deliberately provided by the customer and a separate agreement on scope, confidentiality and retention. Accepted improvements are developed as general AICB capabilities rather than as a customer-specific fork unless an individual agreement says otherwise.

### Donations

Donations are voluntary and welcome, for example via https://github.com/sponsors/gregordadera, but they are a separate matter. A donation does not replace a commercial license where one is required, no matter its size, and it does not create a claim to support, updates or bug fixes.

### Restrictions

You may not:

- reverse-engineer, decompile or disassemble the software, except where mandatory applicable law expressly permits it (for interoperability, German Copyright Act sections 69d and 69e);
- remove, alter or obscure copyright notices, trademarks or version information;
- redistribute, rent, lease, resell or otherwise make the software available to third parties;
- modify or translate the software, or create derivative works from it;
- bundle or embed the AICB binaries into another product, or offer them as a hosted/shared service for direct third-party use;
- present or distribute the software under your own name or brand, or as your own work (re-branding);
- build competing products on the basis of the software.

Backups for your own use are permitted. Connecting AICB to MCP clients, agent harnesses, scripts, build systems and CI/CD through its documented interfaces is also permitted, as is internal use by consultants serving clients. You retain all rights in your source code and may use, adapt, version and share generated context, exports, `.aicb.json` sidecars and files installed by `aicb init`, subject to rights in their underlying material and third-party content.

"**AIContextBuilder**" and "**AIContextBuilder for .NET**" are product names used by Gregor Dadera; no registration is claimed. Factual references (for example "created with AIContextBuilder") are fine; re-branding or implying a partnership is not.

### Warranty, liability and applicable law

The software is provided "as is", without warranty. Liability is unlimited for intent, gross negligence, and injury to life, body or health; for ordinary negligence it is limited to the breach of essential contractual duties and capped at typical, foreseeable damage; otherwise it is excluded. Liability under the German Product Liability Act remains unaffected. German law applies, excluding the UN Sales Convention (CISG). For merchants and legal entities the exclusive place of jurisdiction is the domicile of the licensor; for consumers the statutory rules apply. By downloading, installing or using the software you accept the EULA.

## 2.2 Distribution channels

AIContextBuilder comes in three forms, all built from the same analysis engine:

| Form | Contains | Platforms | Where to get it |
|---|---|---|---|
| **.NET tool** (NuGet package `AIContextBuilder`) | CLI and MCP server | Windows, Linux, macOS | nuget.org, installed with `dotnet tool install -g AIContextBuilder` |
| **Windows installer** | Desktop app, CLI and MCP server | Windows 10 or later, 64-bit | GitHub Releases: `AIContextBuilder-Setup-<version>.exe` |
| **Portable ZIP** | The same payload, no installation | Windows 10 or later, 64-bit | GitHub Releases: `AIContextBuilder-<version>-win-x64.zip` |

All downloads are at https://github.com/gregordadera/AICB/releases.

The desktop app is Windows-only. On Linux and macOS you get the CLI and the MCP server through the .NET tool; there is no GUI build for those platforms. The Windows builds are 64-bit; the installer also runs on ARM64 Windows through x64 emulation.

Note: The public repository carries the documentation, the license and the releases, not the source code.

## 2.3 Prerequisites

| Requirement | Applies to | Why |
|---|---|---|
| **MSBuild** (a .NET SDK or a Visual Studio installation) | every form | Roslyn loads a solution through MSBuild; without it no solution can be analyzed |
| **.NET 8 SDK** | the .NET tool | needed to install and run the tool; the same SDK also provides MSBuild |
| **Windows 10 or later, 64-bit** | installer and ZIP | the desktop app is a WPF application |
| **Administrator rights** | the installer | it installs under `Program Files` and maintains the machine-wide `PATH` |
| none | the ZIP | unpack and run |

Both Windows forms are self-contained: they carry their own .NET runtime, so no .NET installation is required to start them. This does not remove the MSBuild requirement. Opening a solution runs MSBuild's design-time build, exactly as Visual Studio or `dotnet build` does.

Note: If MSBuild cannot be found, `aicb analyze` exits with code 5. The MCP server (`aicb mcp`) and `aicb call` print a warning and start anyway, because their session-less tools keep working. The desktop app checks for MSBuild before anything else, shows `MSBuild not found` and exits.

Note: The analysis runs with server garbage collection limited to four heaps. On a machine with little memory you can override this with the environment variable `DOTNET_gcServer=0`, which takes precedence over the shipped setting.

## 2.4 Installing the .NET tool (CLI and MCP server)

1. Install the .NET 8 SDK if you do not have it.
2. Run:

```sh
dotnet tool install -g AIContextBuilder
```

3. Confirm the installation:

```sh
aicb --version
```

The tool is installed for your user account, normally under `%USERPROFILE%\.dotnet\tools`, and `aicb` is available on your user `PATH`. The MCP server is not a separate program: `aicb mcp` is a verb of this same command, and `aicb init` wires it into a project.

Update later with:

```sh
dotnet tool update -g AIContextBuilder
```

Remove it with:

```sh
dotnet tool uninstall -g AIContextBuilder
```

## 2.5 Installing the desktop app on Windows

### The installer

1. Download `AIContextBuilder-Setup-<version>.exe` from the release page.
2. Run it. Windows asks for administrator rights, because the setup installs under `Program Files` and maintains the machine-wide `PATH`.
3. Pick the language (German is preselected, English is available) and, if you want, a different install folder. The default is `C:\Program Files\AIContextBuilder`.
4. Read and accept the license text to continue.
5. On the options page:
   - `Add the "aicb" command-line tool to PATH (required for the MCP connection used by AI agents)` — selected by default. Keep it if an MCP client should be able to start `aicb` by name; clear it if you prefer to leave the `PATH` untouched. The entry is machine-wide, for all users.
   - An optional desktop icon — not selected by default. A Start menu entry `AI Context Builder` is always created.
   - If a global .NET tool is already installed, an extra group appears: `AICB is already installed as a .NET tool (NuGet):`, with the option `Remove the .NET tool - the MCP server then comes from this installation and is updated with the desktop app (recommended)`, selected by default. See "One installation per machine" below.
6. Finish the setup; you can launch the app directly from the last page.

The setup installs both executables, `gui\aicb-ui.exe` (the desktop app) and `cli\aicb.exe` (the CLI and MCP server), the full agreement `EULA.md`, its summary `LICENSE.txt`, and `THIRD-PARTY-NOTICES.txt` into the install folder.

Note: A change to the `PATH` reaches only processes started afterwards. Consoles, editors and AI agents that are already open find the `aicb` command only after a restart; the installer's last page says so.

Note: If the .NET tool cannot be removed because it is still running as an agent's MCP server, the setup reports this and offers `Retry` after you close the agent. If you cancel, it prints the command to run later.

### The portable ZIP

1. Download `AIContextBuilder-<version>-win-x64.zip` and extract it. Extracting with "Extract Here" produces one versioned folder, `AIContextBuilder-<version>-win-x64`.
2. Start the desktop app by double-clicking `gui\aicb-ui.exe`. No installation and no administrator rights are required.
3. For an MCP client, use `cli\aicb.exe`. It is **not** on `PATH`; only the installer adds it. Give the full path, with doubled backslashes in JSON:

```json
{
  "mcpServers": {
    "aicb": {
      "command": "C:\\path\\to\\this\\folder\\cli\\aicb.exe",
      "args": ["mcp"]
    }
  }
}
```

The extracted folder also contains `LIESMICH.txt` (a bilingual readme with the same notes), `EULA.md`, `LICENSE.txt` and `THIRD-PARTY-NOTICES.txt`. To remove the portable copy, delete the folder; your data stays (see below).

Note: An installed copy and an unpacked copy share the data folder `%APPDATA%\AIContextBuilder\` and therefore the same database. If the unpacked copy is newer than the installed one, it migrates the database to its schema, and that migration is one-way: the installed copy will afterwards refuse to start and report that the database was written by a newer version. That is a safeguard, not a defect. Two ways out: bring the installed copy to the same version, or point `Settings > Storage` at a different database file (which starts you with an empty one there).

## 2.6 One installation per machine

Both the .NET tool and the installer put an `aicb` command on `PATH`, and the two copies can drift apart:

- The installer writes the **machine-wide** `PATH`; the .NET tool installs into your **user** profile.
- Windows builds the `PATH` of a new process from the machine part first, then the user part. With both installed, the installer's copy is therefore the one that runs, for every console and every MCP client.
- `dotnet tool update` would then update a copy that nothing starts, without any error.

Install one of them per machine:

| Situation | Install |
|---|---|
| Windows, and you want the desktop app | the installer only; it contains the same MCP server and CLI, so one update brings app and server to the same version |
| Everything else (Linux, macOS, CI, or no desktop app) | the .NET tool only |

The installer detects an existing .NET tool and offers to remove it (selected by default). It removes it in the account of the signed-in user, not in the administrator account the setup runs as.

For the opposite order, installer first and `dotnet tool install` later, `aicb init` warns when it finds more than one `aicb` on `PATH`, lists which copy runs and which one is ignored, and names the fix: with the desktop app, keep the installer and run `dotnet tool uninstall -g AIContextBuilder`; without it, uninstall `AI Context Builder` in Windows Settings > Apps.

## 2.7 The Windows SmartScreen warning

The installer and the files in the ZIP are not code-signed. On first start Windows may therefore show "Windows protected your PC". To continue:

1. Choose `More info`.
2. Choose `Run anyway`.

This is expected and applies to the installer as well as to `gui\aicb-ui.exe` and `cli\aicb.exe` from the ZIP. The same note is in the `LIESMICH.txt` that ships with the ZIP.

## 2.8 Verifying your download

The release notes for each version list the SHA-256 checksum of every published file. After downloading, compare the file against that value, for example in PowerShell:

```powershell
Get-FileHash .\AIContextBuilder-Setup-<version>.exe -Algorithm SHA256
```

or on Linux and macOS:

```sh
sha256sum AIContextBuilder-<version>-win-x64.zip
```

## 2.9 Updating

There is no automatic update: the product does not check for updates, and it does not install anything by itself. How you update depends on the form you installed:

| Form | How to update |
|---|---|
| .NET tool | `dotnet tool update -g AIContextBuilder` |
| Installer | download the newer `AIContextBuilder-Setup-<version>.exe` from the release page and run it |
| Portable ZIP | download the newer ZIP and replace the extracted folder |

The installer recognizes an existing installation (it uses the same application identity) and updates it in place; it asks you to close a running instance before it replaces files. If you chose a different install folder in an earlier run, the setup removes the previous `PATH` entry, so `aicb` does not keep resolving to the old copy.

To find out which version you have:

- CLI: `aicb --version`
- Desktop app: `Settings > About` shows the version in the header.

Your data is not part of an update: it lives in `%APPDATA%\AIContextBuilder\` and survives installation, update and uninstall.

Note: A newer version migrates the database schema to its own shape, and that migration is one-way. This matters only if you keep two copies of different versions that share the data folder, for example an installed copy and an unpacked ZIP. In that case, do not start the newer copy last. A copy whose database was migrated by a newer version refuses to start and reports that the database was written by a newer version of AIContextBuilder. Bring the older copy to the same version, or point `Settings > Storage` at a different database file.

## 2.10 Uninstalling

| Form | How to uninstall | What remains |
|---|---|---|
| .NET tool | `dotnet tool uninstall -g AIContextBuilder` | your data in `%APPDATA%\AIContextBuilder\` |
| Installer | Windows Settings > Apps > `AI Context Builder` > Uninstall | your data; the uninstaller removes the `PATH` entry it added |
| Portable ZIP | delete the extracted folder | your data |

Note: Uninstalling never deletes your data. That is deliberate: the folder holds your database, and the product has no way to restore it. To remove it too, see the next section.

## 2.11 Removing all data

### What the product offers

Only two functions delete recorded data in bulk, and both are in the desktop app:

| Function | Where | What it does |
|---|---|---|
| `Clear` (dialog `Clear Usage Data`) | `MCP Usage` page | Deletes the recorded MCP tool calls. Two scopes: `Clear everything`, or `Clear calls older than` a date you pick. Before anything is deleted, an export is written; canceling the file picker aborts the whole operation. A second confirmation names how many calls will be deleted and warns that the notes written on those calls are deleted with them and are not part of the export |
| `Clear API Key` | `Settings > Model Profiles` | Removes the stored API key of the selected model profile from the Windows Credential Manager. Later runs against that profile fail until you enter a new key |

The desktop app also offers narrower delete actions for individual sessions, snapshots, MCP-usage notes or imported usage snapshots, and user-created master-data entries.

There is no global "delete all my data" button. No CLI verb deletes anything; the seven verbs are `init`, `analyze`, `export`, `import`, `list`, `mcp` and `call`. The MCP tool `usage_report` is read-only. If you use only the CLI or the MCP server, the only in-product way to remove the usage records is to delete the database file, which also carries every session, snapshot and profile.

### The complete removal list

To remove everything AIContextBuilder has written on a machine:

1. **`%APPDATA%\AIContextBuilder\`** — delete the whole folder. It contains:
   - `user-data\aicb.acb` — the SQLite database: solutions, sessions, snapshots, profiles, and the MCP usage records;
   - `app-settings.json` — bootstrap settings (storage paths, recent lists);
   - `aicb.mcp.json` — optional MCP server configuration, if you created one;
   - `backups\*.zip` — automatic backups, if you enabled them (they are off by default);
   - `aicb.log` and `aicb.log.1` to `aicb.log.3` — the desktop app's warning and error log;
   - `load-perf.log` — solution-load timings, if enabled;
   - possibly `templates.json` and `node-overrides.json` from earlier versions; the data they held now lives in the database.
2. **Windows Credential Manager** — remove every entry whose name starts with `AIContextBuilder.` (your model-profile API keys, for example `AIContextBuilder.ApiKey:<profile>`). These entries live outside the data folder and are not removed by deleting it.
3. **A storage location you changed yourself** — if you set a different `Base path` or database path in `Settings > Storage`, the database and the backups live there. Note that `app-settings.json` always stays in `%APPDATA%\AIContextBuilder\`, whatever `Base path` says, so a moved storage location means two folders to clean up.
4. **Per analyzed solution:** `<SolutionName>.aicb.json` next to the `.sln`. It is deliberately committed to your repository and shared with everyone working on that solution, so removing it changes the configuration for the whole team. An interrupted write can leave a `<SolutionName>.aicb.json.tmp` beside it.
5. **Per project wired by `aicb init` or the `install_agent_hooks` tool** — these entries are merged into files that belong to you, so edit them instead of deleting the files:
   - the `aicb` entry in the project's `.mcp.json`;
   - the skill files under `.claude/skills/` (`aicb-csharp-context`, and with `--skills=all` also `aicb-code-review`, `aicb-code-simplifier` and `aicb-usage-check`);
   - Claude Code: `.claude/hooks/aicb-symbol-guard.mjs` and the aicb entry in `.claude/settings.json`;
   - Codex: `.codex/hooks/aicb-symbol-guard.mjs` and the aicb entry in `.codex/hooks.json`;
   - OpenCode: `.opencode/plugins/aicb-symbol-guard.ts`, `.opencode/plugins/guard-wiring.mjs`, `.opencode/plugins/aicb-symbol-guard.mjs` and the aicb entry in `opencode.json`.
6. **Files you exported yourself** — context documents written with `aicb analyze`, `aicb export` or `export_markdown`, usage reports as JSON, session exports, run templates and constellations.
7. **`%TEMP%\acb-*`** — temporary working folders. They are removed when the command that created them ends; after a crash one may remain.

Note: On Linux and macOS the `%APPDATA%` token resolves to the platform's application-data folder rather than to a Windows path.

### What the logs contain

- `aicb.log` — warnings and errors from the desktop app only, with timestamp, level, category and message. It rotates at 1 MiB and keeps three archives (`aicb.log.1` to `aicb.log.3`); it can be copied while the app is running. The CLI and the MCP server do not write it.
- `load-perf.log` — solution-load phase timings from the desktop app only: phase names, milliseconds and a context label. It does not rotate and grows with every solution load. You can switch it off in `Settings > General` with `Record solution-load performance timings`.
- The CLI and the MCP server write no log file; their diagnostics go to standard error.

Note: The MCP server records one row per tool call in the local database: timestamp, tool name, success, duration, client name and version, and a truncated error text. Nothing is transmitted; the rows stay on your machine and are what the `MCP Usage` page shows and its `Clear` button deletes.

## 2.12 Support and security reports

Questions, bug reports and feature requests go to GitHub Issues at https://github.com/gregordadera/AICB/issues. Please include the version (`aicb --version`, or `Settings > About` in the desktop app) and, for MCP problems, the output of the `server_info` tool.

Report security issues privately, not as a public issue: by email to **aicb@dadera.de**, or through GitHub's `Report a vulnerability` on the repository's *Security* tab. You will get an acknowledgement, and a fix or mitigation will be coordinated before any public disclosure. There is no supported-versions table and no response-time commitment.

Note: Opening a solution runs its MSBuild build logic, the same thing that happens when you open it in Visual Studio or run `dotnet build`. Only analyze solutions you trust. The full threat model is in `SECURITY.md` in the public repository.

## 2.13 Building from source

AIContextBuilder is closed source, and the public repository contains the documentation, the license and the releases, not the source code. Building from source is therefore not a way to install the product. Use the .NET tool, the Windows installer or the portable ZIP described above.

---

[&larr; 1 Introduction](01-introduction.md) &middot; [Contents](README.md) &middot; [3 Core concepts &rarr;](03-core-concepts.md)
