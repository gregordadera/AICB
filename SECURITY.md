# Security

## Reporting a vulnerability

Please report security issues **privately**, not as a public issue:

- Email **aicb@dadera.de** with a description and, if possible, a reproduction, or
- Use GitHub's **"Report a vulnerability"** (private security advisory) on the
  repository's *Security* tab.

You'll get an acknowledgement, and a fix or mitigation will be coordinated before
any public disclosure.

## Threat model

`aicb` opens a C#/.NET solution with Roslyn and answers code-navigation questions
about it. The security-relevant question is therefore: **what does opening or
analyzing a solution actually execute?**

### What `aicb` does *not* do

- **The CLI and the MCP server never modify the code they analyse.** There are no
  refactoring or apply tools, and nothing any tool writes is anything Roslyn reads.
  What they *do* write is named in each tool's own description:
  `apply_solution_config` writes a `<Solution>.aicb.json` sidecar next to the `.sln`,
  `install_agent_hooks` installs the symbol guard into your agent harness's
  configuration on request, and `export_markdown` writes the file you point
  `outputPath` at. **The desktop app is the deliberate exception:** its Details tab
  is an editor, and a file you change there is written back when you press Save.
- **It does not load or run your solution's third-party Roslyn analyzers.**
  `get_diagnostics` returns **compiler** diagnostics only — it calls
  `Compilation.GetDiagnostics()`, which by Roslyn's design does not invoke
  `DiagnosticAnalyzer`s. `aicb` never calls `CompilationWithAnalyzers` /
  `WithAnalyzers`, and never enumerates a project's `AnalyzerReferences` (the step
  that would load an analyzer assembly).
- **It does not run your solution's source generators.** `aicb` constructs no
  generator driver and never requests source-generated documents. Where it reports
  source-generated members (e.g. `[ObservableProperty]` / `[RelayCommand]`), it
  re-derives their names from the attributes in the parsed syntax — it does not
  execute the generator.
- **It spawns three processes, none of which your code can steer.** Measured over
  every production method in the solution, `aicb` reaches `Process.Start` from
  exactly three places, and each takes a fixed command line:
  - **`vswhere.exe`** at startup, to find an MSBuild the locator does not know.
    Its argument line is a compile-time constant; nothing from your solution
    enters it.
  - **`apicompat`**, only through the opt-in `compare_public_api` tool (not in the
    default pool). It takes **you**-supplied assembly paths — never paths derived
    from the analyzed solution — and compares assembly *metadata* rather than
    loading and running the assemblies.
  - **`git rev-list`**, from `server_info`, to report how far this binary lags
    your checkout. **This one does use a solution-derived path** — as the child's
    *working directory*, so that the question is asked about your repository. The
    commit it names comes from this assembly's own build attribute and is rejected
    unless it is hexadecimal.

  What makes the set safe is not the choice of programs but how they are invoked:
  all three build their command lines through `ProcessStartInfo.ArgumentList` or a
  constant, never through a shell, and never by concatenating a string. No file
  name, namespace or symbol in your solution can therefore become an argument, a
  flag, or a second command.

  Scope note: this is the `aicb` CLI and MCP server. The WPF application ships
  four further launch sites (opening the licence file, the sponsor link, Explorer
  on a selected solution, and a gallery-tool restart) — user-initiated shell
  opens, outside this threat model.

### The one caveat you must know

> **Opening a solution runs its MSBuild build logic — only analyze solutions you
> trust.**

To resolve references and determine what to compile, `aicb` loads projects through
`MSBuildWorkspace`, which performs MSBuild's **design-time build**. That evaluates
and runs the project's *own* MSBuild logic — its `.csproj`, `Directory.Build.props`
/ `.targets`, SDK and NuGet-restored imports, and any custom targets or inline
tasks (`UsingTask` / `Exec`). A deliberately malicious project could therefore run
code at solution-open time.

This is **not specific to `aicb`.** It is inherent to every MSBuild-based tool —
Visual Studio, the C# Dev Kit / C# language server, OmniSharp, and other
Roslyn/MSBuild analyzers all open projects the same way. The trust boundary is the
same as *"clone this repository and run `dotnet build`"* or *"open it in Visual
Studio"*: opening an untrusted project can execute code. `aicb` uses a plain
`MSBuildWorkspace` and neither reduces nor amplifies this baseline.

**Recommendation:** treat pointing `aicb` at a solution as equivalent to building
it. Only analyze solutions from sources you trust.
