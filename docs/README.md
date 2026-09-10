# TetraVim Project Knowledge & Documentation

Welcome to the **TetraVim** documentation repository.

> **Note:** This distribution was originally scaffolded with a BMAD planning tree
> (`_bmad-output/*`). That tree has since been removed from the repo — code
> comments citing `Story X.Y` / `SPEC-N.M` / `Epic N` are kept only as historical
> tags. For the current architecture, see [`../CLAUDE.md`](../CLAUDE.md).

## Architecture Overview

`tetravim.nvim` is an enterprise-ready Neovim distribution for JVM backend engineering (Java, Kotlin, Scala). It is **pure native Neovim** — standard LSPs (`nvim-jdtls`, Kotlin Language Server, `nvim-metals`), Tree-sitter, Mason tools, and Lua utilities. There is no `tetravim-engine`, no Scala backend, and no bridge.

### Key Modules

- **Core**: `lua/tetravim/core/` (Options, keymaps, autocmds, devops, lazy bootstrap)
- **Plugins**: `lua/tetravim/plugins/` (Lazy.nvim plugin specifications)
- **JVM Utilities**: `lua/tetravim/util/jvm/jvm.lua`, `lua/tetravim/util/jvm/spring.lua`, `lua/tetravim/util/jvm/spring_picker.lua`, `lua/tetravim/util/edit/refactor.lua`, `lua/tetravim/util/edit/extract.lua`, `lua/tetravim/util/clients/db.lua`, `lua/tetravim/util/clients/http.lua`, `lua/tetravim/util/clients/openapi.lua`, `lua/tetravim/util/git.lua`, `lua/tetravim/util/cloud/forge.lua`, `lua/tetravim/util/quality/sonar.lua`, `lua/tetravim/util/quality/cve.lua`

## Enterprise Operability (Epic 5)

### Asynchronous LSP & Resilience (Story 5.1)

- Project-wide LSP operations (e.g. the safe-rename reference scan) fan out through `tetravim.util.lsp.async.request_all_async`, which dispatches to every attached client and calls back on `vim.schedule` once the last response lands — the UI thread never blocks waiting on a server.
- JDTLS is launched with a bounded JVM heap (`-Xmx2g` / `-Xms512m`, via `tetravim.util.lsp.resilience.apply_memory_limit`) so indexing a large monorepo cannot OOM the host.
- If a language-server process crashes it is auto-restarted, bounded to 3 restarts per 180s. Exhausting that budget stops the retry loop and surfaces one error pointing at `:LspLog`. A clean re-attach resets the window.
- `:checkhealth tetravim` → "Asynchronous LSP & Resilience (Story 5.1)".

### Headless Setup & Telemetry (Story 5.2)

TetraVim provisions non-interactively (Codespaces / Coder / CI images) via its native setup module — no UI, no TTY. It runs five steps: `Lazy! sync`, `MasonToolsInstall`, Quarkus/MicroProfile LSP jar fetching, Tree-sitter parser install, and a machine-readable health snapshot. Setting `TETRAVIM_HEADLESS=1` bridges to `g:tetravim_headless`.

```sh
nvim --headless -u init.lua -c "lua require('tetravim.core.setup').run()" -c "qa!"
```
*(Or inside Neovim: `:TetraVimSetup`)*

The healthcheck is also available as machine-readable JSON for compliance gating — `:CheckHealthJson`, or `require('tetravim.core.health_json').json()` — emitting one JSON object with `neovim_version`, `lsp_clients`, `plugin_count`, `pending_async_tasks`, and `telemetry_enabled`.

Telemetry is opt-in and local-only. Toggle it with:

- `:TetraVimTelemetryEnable` – enable telemetry logging to `telemetry.log` in your config directory.
- `:TetraVimTelemetryDisable` – disable telemetry.

Each line is one JSON object (`timestamp`, `level`, `msg`, `source`). TetraVim's primary notifier (`tetravim.util.ui`) delegates to `tetravim.util.notify`, so subsystem notifications routed through it are captured while telemetry is enabled. Nothing is written while the flag is unset, `telemetry.log` is git-ignored, and it rolls over to a single `.1` backup once it passes ~1 MiB.

## Code Quality & Security (Epic 6)

The `<leader>x` group ("quality/security") wires two capabilities for JVM projects. Run `:WhichKey <leader>x` for the full, current keymap list.

### SonarQube / SonarLint (Story 6.1)

The `sonarlint-language-server` Mason package (with its bundled analyzer jars) attaches to Java/Kotlin/Scala buffers via `sonarlint.nvim`, surfacing Sonar rule violations as LSP diagnostics. When a `sonar-project.properties` file is found (searched upward from the buffer), its settings (`sonar.projectKey`, quality-profile hints) are forwarded to the language server. Scala rules require SonarQube connected mode.

The `<leader>x` group is organised by feature type, and within each type the
lowercase key acts on the current buffer while the `p`/uppercase key acts on the
whole project:

| Type | Buffer | Project |
| --- | --- | --- |
| Diagnostics | `<leader>xdb` line float | `<leader>xdp` all diagnostics → quickfix |
| Lint | `<leader>xlb` check · `<leader>xlf` autofix (writes file) | `<leader>xlp` check · `<leader>xlF` autofix |
| Sonar | `<leader>xsb` rule description under cursor | `<leader>xsp` whole-codebase scan |
| CVE | `<leader>xvb` scan open build file · `<leader>xvc` clear | `<leader>xvp` scan whole project |

`<leader>xsp` auto-selects `sonar-scanner` connected mode when a `sonar-project.properties` declares `sonar.host.url` and the CLI is installed, otherwise a server-free SonarLint sweep of every Java/Kotlin/Scala source into the quickfix list.

### Vulnerability / CVE Scanning (Story 6.2)

`<leader>xvb` runs `osv-scanner` (OSV.dev advisory feeds) asynchronously against the open `pom.xml` / `*.gradle` build script and publishes WARN diagnostics on each vulnerable dependency line, with a remediation hint naming the advisory ids and the version(s) to upgrade to. `<leader>xvp` runs `osv-scanner -r` over the whole project tree and renders the findings in a persistent split. `<leader>xvc` clears the CVE diagnostics for the buffer.

Both tools are optional: `:checkhealth tetravim` reports their availability, `bootstrap.sh` offers to install `osv-scanner`, and every code path degrades to a single notification when a binary or plugin is missing.

## Core Documentation References

- **Agent Guidelines & Policy**: [`AGENTS.md`](../AGENTS.md)
- **Installation Guide**: [`INSTALL.md`](../INSTALL.md)
- **Quickstart & Commands**: [`README.md`](../README.md)
- **Architecture & Conventions**: [`CLAUDE.md`](../CLAUDE.md)
- **In-editor health**: `:checkhealth tetravim`

The former `_bmad-output/planning-artifacts/*` specs (architecture spine, features
spec, epics/stories, sprint status) are no longer part of the repo.
