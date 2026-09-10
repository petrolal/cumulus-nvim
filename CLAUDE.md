# CLAUDE.md

This file provides guidance to Claude Code (claude.ai/code) when working with code in this repository.

## What this is

`tetravim.nvim` is a Neovim **distribution** (not a plugin) targeting JVM backend
work (Java, Kotlin, Scala, Gradle/Maven) and cloud-native/DevOps development. It is
pure native Neovim — standard LSPs, Tree-sitter, Mason, `nvim-dap`, Lua utilities.
There is no companion backend/engine/bridge. Requires **Neovim ≥ 0.11** (uses
`vim.lsp.config`/`vim.lsp.enable`, `vim.diagnostic.jump`, `winborder`; `init.lua`
hard-fails on anything older).

The repo is meant to be cloned to `~/.config/nvim` (or symlinked there for
development).

## Commands

```bash
# Full dependency install (Neovim, npm/go/python tools, Mason, Tree-sitter, scanners).
# Single root script -- there is no scripts/ dir anymore.
bash bootstrap.sh

# Native non-interactive setup & provisioning (Lazy sync, Mason tools, JVM LSP jars,
# TS parsers, health snapshot). This is what CI's "smoke" job runs.
nvim --headless -u init.lua -c "lua require('tetravim.core.setup').run()" -c "qa!"

# Full plenary busted suite
nvim --headless -u init.lua -c "Lazy! load plenary.nvim" \
  -c "PlenaryBustedDirectory lua/tetravim/tests/" -c "qa"

# Single test file
nvim --headless -u init.lua -c "Lazy! load plenary.nvim" \
  -c "PlenaryBustedFile lua/tetravim/tests/theme_integration_spec.lua" -c "qa"

# Format Lua (stylua.toml: 2-space indent, 120 column). CI runs `stylua --check .`
stylua .

# In-editor health
nvim +"checkhealth tetravim"
```

CI (`.github/workflows/ci.yml`) runs three jobs on push/PR: **lint** (`stylua
--check` + `bash -n bootstrap.sh`), **test** (busted suite on nvim stable — gate —
and nightly — advisory), **smoke** (`tetravim.core.setup.run()` + health JSON).
The busted job gates on the printed summary text, not the exit code.

## Architecture

### Load order

`init.lua` → `vim.loader.enable()` → `tetravim.util.notify` → `tetravim.core`
(`core/init.lua` loads `options`, `keymaps`, `autocmds`, `diagnostics`, `notify`,
`health`) → `tetravim.core.lazy` (bootstraps lazy.nvim, then
`{ import = "tetravim.plugins" }`).

`core/lazy.lua` auto-imports **every** file in `lua/tetravim/plugins/`; each such
file returns a lazy.nvim spec (single spec table or a list of them). `defaults.lazy
= false` — plugins load eagerly unless a spec opts into `event`/`ft`/`keys`.

### Directory map

| Path                    | Role                                                                                                                                                                                                                                                                                                 |
| ----------------------- | ---------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------- |
| `lua/tetravim/core/`    | Editor bootstrap: `options`, global `keymaps`, `autocmds`, `diagnostics`, `health`, `devops` keymap engine, `lang-keymaps`, `setup` (headless provisioning pipeline)                                                                                                                                   |
| `lua/tetravim/plugins/` | One lazy.nvim spec file per concern. Prefixes: `lsp-*`, `tools-*`, `editor-*`, `ui-*`, `cloud-*`, `core-*`, `lang-*`                                                                                                                                                                                   |
| `lua/tetravim/util/`    | Pure Lua logic modules (`jvm`, `spring`, `spring-picker`, `refactor`, `refactor-treesitter`, `extract`, `filetemplate`, `db`, `http`, `grpc`, `openapi`, `cve`, `sonar`, `forge`, `lsp_async`, `lsp_resilience`, `lsp_capabilities`, `lsp_attach`, `format`, `lint`, `git`, `build`, `coverage`, `session`, `term`, `split`, …). Keymaps call into these; business logic lives here, not in the keymap files |
| `lua/tetravim/theme/`   | `tetris.lua` = canonical palette + highlight table; `init.lua` = loader/persistence shim                                                                                                                                                                                                              |
| `colors/tetravim.lua`   | `:colorscheme tetravim` entry point                                                                                                                                                                                                                                                                  |
| `lua/tetravim/tests/`   | `*_spec.lua` plenary busted specs                                                                                                                                                                                                                                                                    |
| `ftplugin/*.lua`        | Per-filetype auto-launchers (notably `java.lua` starting `nvim-jdtls`)                                                                                                                                                                                                                                |
| `docs/`                 | `README.md` (project knowledge, points back here), `ide-parity.md`                                                                                                                                                                                                                                    |

### Keymap system

Four registration channels, deliberately layered so `<leader>` groups only show
keys relevant to the current buffer:

1. **Global** — `core/keymaps.lua` (`<leader>c` code/LSP, `<leader>w` windows,
   `<leader>a` API/data clients — `<leader>ah` HTTP, `<leader>ag` gRPC, `<leader>ad`
   database — `<leader>x` quality/security, file ops).
2. **JVM platform** — `<leader>j`, registered unconditionally via
   `require("tetravim.util.jvm").setup_keymaps()`.
3. **DevOps/infra** — `<leader>o`, registered globally via
   `require("tetravim.core.devops").setup_keymaps()`; which-key groups come from
   `devops.whichkey_spec()`.
4. **Language-scoped** — `core/lang-keymaps.lua`. Each language stack calls
   `M.register{ filetypes=…, group=…, keys=… }`; a `FileType` autocmd installs the
   keys **buffer-local** only for matching filetypes, so `<leader>c` never mixes
   e.g. Maven keys into a Terraform buffer. Java/Kotlin build stacks are gated
   behind `util/build-sync-state` until the first Maven/Gradle dependency sync
   completes.

### LSP

`plugins/lsp-core.lua` collects `opts.servers` contributed by every `lsp-*.lua` /
`cloud-*.lua` spec and enables each with `vim.lsp.config()` + `vim.lsp.enable()`.
Java is special-cased through `nvim-jdtls` in `ftplugin/java.lua` (bundles
java-debug/java-test, Spring DAP, workspace under `stdpath("cache")/jdtls/`); Scala
uses `nvim-metals`; Kotlin uses `kotlin_language_server`.

JVM framework config intelligence (`application.properties` / `application.yml` /
`microprofile-config.properties` completion, `@ConfigurationProperties` /
`@ConfigProperty` metadata, Spring symbol nav, Qute templates):

- **Spring Boot** — `plugins/lsp-spring-boot.lua` drives `JavaHello/spring-boot.nvim`
  over the VMware Spring Boot LS (Mason package `vscode-spring-boot-tools`, in
  `tools-mason.lua` `ensure_installed`). Value data comes from
  `spring-configuration-metadata.json` the LS harvests from the project + its jars,
  not SchemaStore.
- **Quarkus / MicroProfile** — `plugins/lsp-quarkus.lua` drives
  `JavaHello/quarkus.nvim` + `JavaHello/microprofile.nvim` (lsp4mp + Qute LS). These
  ship only inside Red Hat's `vscode-quarkus` / `vscode-microprofile` `.vsix`
  bundles — **not in Mason** — so `:TetraVimFetchJvmLspJars`
  (`util/jvm_frameworks.fetch_jars()`) downloads them from Open VSX into
  `$TETRAVIM_JVM_LSP_DIR` (default `stdpath("data")/tetravim/jvm-lsp`, layout
  `quarkus/{server,jars}` + `microprofile/{server,jars}`). The spec loads but stays
  **dormant** (no server spawned) until those jars exist; each server is a separate
  ~1 GiB JVM on top of jdtls, so activation is opt-in. The provisioning pipeline
  (`bootstrap.sh`, `tetravim.core.setup`) calls `jvm_frameworks.fetch_jars()`
  headlessly best-effort.
- **Micronaut** — intentionally **unsupported**: no viable Neovim language server
  exists. Do not add one.

`util/jvm_frameworks` is the path resolver + readiness probe API used by both
plugin specs, `ftplugin/java.lua` (folds each module's `java_extensions()` into the
jdtls `bundles`) and the `:checkhealth tetravim` "JVM Framework Config LSP"
section. `tests/jvm_frameworks_spec.lua` covers it.

Completion capabilities: `util/lsp_capabilities.make()` is the one source of truth
for the `capabilities` table every server starts with — it folds
`cmp_nvim_lsp.default_capabilities()` onto the 0.11 base and degrades gracefully
when nvim-cmp isn't loaded. `lsp-core.lua` applies it once via
`vim.lsp.config("*", { capabilities })` plus the lspconfig fallback;
`ftplugin/java.lua` and `lsp-scala.lua` inject the same table on their own start
paths. The completion front-end (nvim-cmp + LuaSnip + friendly-snippets +
`cmp-nvim-lsp`/`-buffer`/`-path`/`-cmdline`) lives in
`plugins/editor-completion.lua`; SQL buffers layer `vim-dadbod-completion` on top
buffer-locally via `tools-dadbod.lua`.

Resilience layer:

- `util/lsp_resilience` — bounds the JDTLS JVM heap (`apply_memory_limit`) and
  auto-restarts a crashed server (max 3 restarts / 180s, then stops and points at
  `:LspLog`). `on_attach` calls `reset()` to open a fresh window.
- `util/lsp_async.request_all_async` — fans a request out to all attached clients
  and calls back on `vim.schedule` after the last reply, so project-wide operations
  never block the UI thread.

### Theme

Single canonical palette. `theme/tetris.lua` holds the hex values
(`bg #111216`, `cyan #00F0F0`, `purple #A000F0`, …) and the highlight table;
`theme/init.lua` is a thin loader (`apply()` / `load_saved_theme()` / `setup()`
shim) invoked from `core/options.lua` on startup. A previous multi-provider "cloud
theme switcher" was removed — do not reintroduce provider palette tables.

### Health & headless

- `:checkhealth tetravim` → `lua/tetravim/health.lua` (per-feature dependency
  probes).
- `:CheckHealthJson` / `require("tetravim.core.health").json()` → one-line JSON
  (`neovim_version`, `lsp_clients`, `plugin_count`, `pending_async_tasks`,
  `telemetry_enabled`) for CI gating.
- `TETRAVIM_HEADLESS=1` → `vim.g.tetravim_headless` (bridged in `core/options.lua`).
- Telemetry is opt-in and local-only: `:TetraVimTelemetryEnable` appends JSON lines
  to `telemetry.log` (git-ignored, rolls at ~1 MiB) for notifications routed
  through `tetravim.util.ui` → `tetravim.util.notify`.

## Conventions

- `<leader>` is Space, `<localleader>` is `\` (`core/options.lua`).
- Comments frequently cite `Story X.Y` / `SPEC-N.M` / `Epic N` tags — these are
  historical planning references; the BMAD planning tree they came from
  (`_bmad-output/*`) has been removed. Do not treat missing `_bmad*` paths as a bug.
- Helper output (HTTP/gRPC responses, generated templates) always renders in a
  persistent split via the shared `tetravim_http_open_in_split` helper, never a
  floating window.
- New user-facing logic: put the implementation in a `util/` module and keep the
  keymap file a thin dispatcher; guard every optional binary/plugin with a
  `pcall`/`executable` check that degrades to a single `ui.notify_*` call.
- Every feature that touches an external tool should add a probe to
  `lua/tetravim/health.lua`.
