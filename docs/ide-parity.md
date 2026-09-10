# IntelliJ IDEA Ultimate → tetravim.nvim parity map

What IDEA Ultimate supports **out of the box (no extra plugin)**, and how
tetravim.nvim covers it with native Neovim LSP / Tree-sitter / Mason tooling.

Legend: ✅ full LSP + Tree-sitter · 🟡 Tree-sitter / syntax only (no OSS server)
· ➖ not covered (no OSS equivalent) · 🔷 handled by an existing spec

_Last reconciled with the code: 2026-09-10 (`lsp-kotlin.lua`, `lsp-quarkus.lua`, `util/endpoints_panel.lua`, `util/k8s.lua`, `util/docker.lua`, `util/profiling.lua`, `syntax/freemarker.vim`, `syntax/velocity.vim`, `ftplugin/{freemarker,velocity,jsp}.lua`)._

## Languages

| IDEA bundles | tetravim | Spec file | Server / tool |
| --- | --- | --- | --- |
| Java | 🔷 | `lsp-java.lua`, `ftplugin/java.lua` | `jdtls` (+ java-debug, java-test) |
| Kotlin | 🔷 | `lsp-kotlin.lua` | JetBrains `kotlin_lsp` (intellij-server / IDEA engine) when installed, else `kotlin_language_server` |
| Groovy | 🔷 | `lsp-groovy.lua` | `groovyls` |
| Scala | 🔷 | `lsp-scala.lua` | `nvim-metals` |
| JavaScript / TypeScript / JSX / TSX | 🔷 | `lsp-typescript.lua` | `ts_ls` |
| Python | ✅ | `lsp-python.lua` | `basedpyright` + `ruff` |
| SQL | ✅ | `lsp-sql.lua` (+ `tools-dadbod.lua`) | `sqlls` + vim-dadbod |
| HTML / XHTML | 🔷 | `lsp-html.lua` | `html`, `superhtml` |
| CSS / SCSS / LESS / Sass | 🔷 | `lsp-css.lua` | `cssls` |
| JSON / JSON5 | 🔷 | `lsp-devops.lua` | `jsonls` (+ SchemaStore) |
| YAML (+ GitHub Actions / GitLab CI) | 🔷 | `lsp-yaml-ci.lua` | `yamlls`, `gh-actions-language-server` |
| XML / XSD / XSLT / DTD | 🔷 | `lsp-devops.lua` | `lemminx` |
| TOML | 🔷 | `lsp-toml.lua` | `taplo` |
| Markdown | ✅ | `lsp-markdown.lua`, `editor-markdown.lua` | `marksman` + render-markdown + preview |
| Shell script | 🔷 | `lsp-devops.lua` | `bashls`, `shellcheck`, `shfmt` |
| Properties | 🔷 | (jdtls / built-in ft) | — |
| RegExp | 🟡 | built-in | Neovim highlighting; no LSP exists |
| EditorConfig | 🟡 | built-in ft | no OSS LSP |
| Protocol Buffers / gRPC | 🔷 | `lsp-proto.lua`, `grpcui.lua` | `protols`, `buf`, `grpcurl` |
| Terraform / HCL | 🔷 | `cloud-terraform.lua` | `terraformls`, `tflint` |
| Dockerfile | 🔷 | `cloud-containers-k8s.lua` | `dockerfile-language-server`, `hadolint` |
| Kubernetes / Helm | 🔷 | `cloud-containers-k8s.lua` | `helm-ls` |
| Ansible | 🔷 | `cloud-cloudformation-ansible.lua` | `ansible-language-server`, `ansible-lint` |
| Lua (IDE config) | 🔷 | `lsp-lua.lua` | `lua_ls` |
| Deno | ✅ | `lsp-deno.lua` | `denols` (runtime-provided; deno.json-gated) |
| Prisma | ✅ | `lsp-prisma.lua` | `prismals` |

### Not bundled by IDEA Ultimate either (need a JetBrains plugin) — out of scope here

Go, Rust, PHP, Ruby, C/C++, Dart, GraphQL, Perl, Elixir, Clojure, Haskell.

## Frameworks

| IDEA bundles | tetravim | Notes |
| --- | --- | --- |
| Spring / Spring Boot / Data / Security / Batch | 🔷 | `jdtls` + Spring Boot LS (`lsp-spring-boot.lua`, `spring-boot.nvim` / `vscode-spring-boot-tools`): `application.*` completion, and `tetravim.util.spring_lsp` drives endpoint/bean pickers off the STS4 `workspace/symbol` model when attached, falling back to the `tetravim.util.spring*` ripgrep + Tree-sitter scan otherwise; DAP via `ftplugin/java.lua` |
| Jakarta EE / Java EE, Hibernate/JPA | 🔷 | `jdtls` semantic model |
| Quarkus / MicroProfile | 🔷 | `lsp-quarkus.lua` → `quarkus.nvim` + `microprofile.nvim` (lsp4mp + Qute). Dormant until `:TetraVimFetchJvmLspJars` fetches the Red Hat `.vsix` bundles (not in Mason); each server is a separate ~1 GiB JVM, so activation is opt-in via `<leader>jsq` (`tetravim.util.jvm_lsp_toggle`: persisted flag + `MemAvailable` guard, `< 3 GiB` free RAM refuses auto-activate). `:checkhealth tetravim` reports the flag and live per-server `VmRSS` |
| Micronaut | ➖ | intentionally unsupported — no viable Neovim language server exists |
| Ktor / Helidon | 🔷 | `jdtls` / Kotlin LSP semantic model — no framework-specific server |
| JUnit / TestNG (JVM test UI) | 🔷 | `tools-test.lua`: Java → `neotest-java`, Scala → `neotest-scala`; Kotlin/Groovy → `tetravim.util.jvm_test` (in-repo Gradle/Maven runner, nearest test via Tree-sitter, JUnit XML parsed to a pass/fail summary + quickfix) |
| Node.js / React | 🔷 | `ts_ls` |
| Angular | ✅ | `lsp-web-frameworks.lua` → `angularls` |
| Vue | ✅ | `lsp-web-frameworks.lua` → `vue_ls` (Volar, hybrid off) |
| Svelte | ✅ | `lsp-web-frameworks.lua` → `svelte` |
| Astro | ✅ | `lsp-web-frameworks.lua` → `astro` |
| ESLint (always-on) | ✅ | `lsp-web-tooling.lua` → `eslint` (+ fix-all on save) |
| Tailwind CSS | ✅ | `lsp-web-tooling.lua` → `tailwindcss` |

## Template engines

| IDEA bundles | tetravim | Coverage |
| --- | --- | --- |
| Emmet (all HTML-ish buffers) | ✅ | `lsp-web-tooling.lua` → `emmet_language_server` |
| Handlebars / Mustache | 🟡 | built-in ft + Tree-sitter + emmet |
| Pug / Jade | 🟡 | `lang-templates.lua` → Tree-sitter `pug` + emmet |
| EJS / ERB | 🟡 | `.ejs`→`eruby` ft + Tree-sitter `embedded_template` + emmet |
| Jinja2 / Django | ✅ | `lang-templates.lua` → `htmldjango` ft + `djlint` (format + lint) + emmet |
| Thymeleaf | 🔷 | plain `.html`: `html` LSP + emmet |
| FreeMarker (`.ftl`, `.ftlh`, `.ftlx`) | 🟡 | `lang-templates.lua` ft + `syntax/freemarker.vim` (HTML base + `<#…>`/`<@…>` directives, `${…}`/`#{…}` interpolations, `<#-- -->` comments) + `ftplugin/freemarker.lua` (2-space, `<#-- %s -->` commentstring, matchit block pairs) + emmet. No OSS server/parser exists |
| Velocity (`.vm`) | 🟡 | `lang-templates.lua` ft + `syntax/velocity.vim` (HTML base + `#…` directives, `$…` references, `##`/`#* *#` comments) + `ftplugin/velocity.lua` (2-space, `## %s` commentstring, matchit block pairs) + emmet. No OSS server/parser exists |
| JSP / JSTL | 🟡 | built-in `jsp` syntax (HTML + embedded Java) + `ftplugin/jsp.lua` (2-space, `<%-- %s --%>` commentstring, matchit scriptlet/JSTL pairs) + emmet. No OSS server or parser |

## Databases (query tooling)

vim-dadbod (`tools-dadbod.lua`) + `sqlls` cover connection management, schema
browsing, query execution and completion for the JDBC-style dialects IDEA's
Database plugin targets (PostgreSQL, MySQL/MariaDB, Oracle, SQL Server, SQLite,
H2, …). Datasource auto-discovery from Spring `application.*` is
`tetravim.util.db`.

## DevOps / API

| IDEA bundles | tetravim |
| --- | --- |
| HTTP Client (`.http`) | 🔷 `tools-http.lua` (kulala) |
| OpenAPI / Swagger | 🔷 `tetravim.util.openapi` (`.http` generation); `tetravim.util.endpoints_panel` folds JSON specs into the Endpoints panel |
| Endpoints tool window | 🔷 `tetravim.util.endpoints_panel` (`<leader>ae`) — docked list of every Spring MVC mapping + JSON OpenAPI operation, `<CR>` jump / `r` refresh / `g` → `.http` |
| Docker / Compose | 🔷 `cloud-containers-k8s.lua` (LSP/lint) + `tetravim.util.docker` runtime dashboard (`<leader>odd`) — container/image list, logs, start/stop/restart, exec shell, remove, `docker compose up -d` / `down` |
| Kubernetes / Helm | 🔷 `cloud-containers-k8s.lua` (LSP) + `tetravim.util.k8s` cluster explorer (`<leader>oke`) — Deployments/Pods/Services per context+namespace, describe/yaml, logs, exec shell, delete, namespace/context switch |
| Terraform | 🔷 `cloud-terraform.lua` |
| Database tools | 🔷 `tools-dadbod.lua` + `lsp-sql.lua` |

## Editor / IDE tool windows

The panels and actions IDEA exposes around the editor itself — not a language
server, a workflow.

| IDEA feature | tetravim | Keys |
| --- | --- | --- |
| Run Anything / Run Configurations (arbitrary commands, `tasks.json`, npm scripts) | 🔷 `tools-tasks.lua` → overseer.nvim | `<leader>r` |
| TODO tool window | 🔷 `editor-todo-comments.lua` → todo-comments.nvim | `]t` / `[t`, `<leader>xt`, `<leader>st` |
| Structure tool window (docked symbol tree) | 🔷 `editor-outline.lua` → outline.nvim | `<leader>cs` |
| Replace in Path (interactive project-wide replace) | 🔷 `editor-search-replace.lua` → grug-far.nvim | `<leader>sr` / `<leader>sR` / `<leader>sF` |
| Local History | 🔷 `editor-undotree.lua` → undotree + persistent `undofile` | `<leader>uu` |
| Bookmarks (mnemonic, gutter, list) | 🔷 `editor-marks.lua` → marks.nvim | `m*`, `<leader>m`, `<leader>sm` |
| Grazie (grammar / spell / style for prose) | 🔷 `lsp-markdown.lua` → `ltex-ls` | via `<leader>ca` |
| Bundled decompiler (source-less library `.class`) | 🔷 `lsp-java.lua` + `ftplugin/java.lua` → `dgileadi/vscode-java-decompiler` jars in the jdtls bundle list | `gd` |
| npm dependency version inlays in `package.json` | 🔷 `lang-npm.lua` → package-info.nvim | `<leader>cp*` (in `package.json`) |
| Run with Coverage | 🔷 native `tetravim.util.coverage` (JaCoCo XML overlay) | `<leader>jc*` |
| Profiler tool window (interactive flamegraph / call tree) | 🔷 `tetravim.util.profiling` → `jps` process picker + timed `asprof -o collapsed` capture, parsed into a foldable call tree in `tetravim.util.panel` (`<CR>`/`o` expand, `E`/`C` expand/collapse-all, `g` raw stacks, `r` re-capture). External HTML flamegraph path stays on `<leader>jps`/`jpx`/`jpv` | `<leader>jpp` |
| Endpoints tool window (project HTTP endpoint list) | 🔷 `tetravim.util.endpoints_panel` → `tetravim.util.panel` in the shared split (Spring `workspace/symbol` model + JSON OpenAPI specs) | `<leader>ae` |
| Kubernetes tool window (cluster resource tree) | 🔷 `tetravim.util.k8s` → `tetravim.util.panel`; `kubectl`-driven Deployments/Pods/Services for the active context+namespace, describe / yaml / logs / exec / delete / ns+ctx switch | `<leader>oke` |
| Services / Docker tool window (container + image runtime) | 🔷 `tetravim.util.docker` → `tetravim.util.panel`; `docker`-driven container/image list, inspect / logs / start-stop-restart / exec / rm / `docker compose up -d`+`down` | `<leader>odd` |

`nvim-coverage` was deliberately **not** added: the distro already ships a
native JaCoCo coverage engine (`lua/tetravim/util/coverage.lua`, wired to
`<leader>jc*`). To gain lcov/cobertura support for Python/JS later, extend that
module's parser rather than layering a second, competing plugin.

## Install

All servers/tools are in `tools-mason.lua`'s `ensure_installed` and are fetched
by `mason-tool-installer` on first `VimEnter`. Force a sync with
`:MasonToolsInstall`. `deno` is the one exception — install the Deno runtime
separately and `lsp-deno.lua` picks it up automatically.

Verify with `:checkhealth tetravim` → *IDE-Parity Language Servers* section.
