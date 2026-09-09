-- TetraVim Mason Package Management (AR2, Epic 3, Epic 11, Epic 12, Epic 39, Epic 40)

-- NOTE: plain mason.nvim's setup() has no "ensure_installed" option -- that
-- field is only understood by the separate mason-tool-installer.nvim
-- plugin. Without it, this list was silently ignored and none of these
-- tools (including cfn-lint / ansible-lint) were ever actually installed,
-- causing nvim-lint to fail when it tried to run them.
local ensure_installed = {
  "terraform-ls",
  "tflint",
  "ansible-language-server",
  "ansible-lint",
  "cfn-lint",
  "yaml-language-server",
  -- CI/CD YAML (Epic 39): GitHub Actions LSP + workflow linter, generic YAML
  -- linter pointed at .gitlab-ci.yml.
  "gh-actions-language-server",
  "actionlint",
  "yamllint",
  "dockerfile-language-server",
  "hadolint",
  "helm-ls",
  "json-lsp",
  "lemminx",
  "bash-language-server",
  "shellcheck",
  "shfmt",
  "google-java-format",
  "jdtls",
  "java-debug-adapter",
  "java-test",
  -- Spring Boot Language Server (application.properties / application.yml
  -- completion + Spring symbol navigation) -- see lsp-spring-boot.lua.
  "vscode-spring-boot-tools",
  "kotlin-language-server",
  "kotlin-debug-adapter",
  "ktlint",
  "groovy-language-server",
  "npm-groovy-lint",
  "superhtml",
  "html-lsp",
  "css-lsp",
  "typescript-language-server",
  "lua-language-server",
  "taplo",
  "checkstyle",
  "buf",
  "protols",
  "sonarlint-language-server",

  -- IntelliJ IDEA Ultimate language/framework parity (see docs/ide-parity.md).
  -- Python (bundled "Python" plugin): type checker + linter/formatter LSP.
  "basedpyright",
  "ruff",
  -- SQL (bundled Database tools): language intelligence layer over vim-dadbod.
  "sqlls",
  -- Web framework servers (bundled Vue / Svelte / Astro / Angular plugins).
  "vue-language-server",
  "svelte-language-server",
  "astro-language-server",
  "angular-language-server",
  -- Cross-cutting web tooling that is always-on in IDEA.
  "eslint-lsp",
  "tailwindcss-language-server",
  "emmet-language-server",
  "prettier",
  -- Prisma ORM (bundled plugin).
  "prisma-language-server",
  -- Markdown editing intelligence (bundled Markdown plugin).
  "marksman",
  -- Natural-language grammar / spelling / style for prose in Markdown, LaTeX,
  -- rST, plain text and commit messages (IDEA ships this via Grazie).
  "ltex-ls",
  -- Jinja2 / Django template format + lint (bundled template-engine support).
  "djlint",
}
-- NOTE: Deno's LSP is the `deno` runtime itself -- there is no Mason package.
-- lsp-deno.lua registers denols only when `deno` is already on $PATH.

return {
  {
    "williamboman/mason.nvim",
    lazy = false,
    opts = {},
  },
  {
    "WhoIsSethDaniel/mason-tool-installer.nvim",
    -- NOTE: must load eagerly, not on an event like BufReadPre/BufNewFile.
    -- mason-tool-installer's actual auto-install trigger isn't its opts --
    -- it's a `VimEnter` autocmd registered by its own
    -- `plugin/mason-tool-installer.lua`, which only gets sourced once
    -- lazy.nvim loads the plugin. VimEnter fires exactly once, at Neovim
    -- startup; if this plugin were still event-gated on the first buffer
    -- read, that read can easily happen at or after VimEnter (e.g. `nvim .`
    -- with no file arg), so the plugin loads too late for its own VimEnter
    -- hook to ever fire -- `ensure_installed` (jdtls, kotlin-language-server,
    -- groovy-language-server, etc.) then silently never gets auto-installed,
    -- and every LSP relying on it shows "No active clients" forever until
    -- someone thinks to run `:MasonToolsInstall` by hand.
    lazy = false,
    dependencies = { "williamboman/mason.nvim" },
    opts = {
      ensure_installed = ensure_installed,
      auto_update = true,
      run_on_start = true,
    },
  },
}
