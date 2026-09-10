-- TetraVim Markdown Language Server -- IntelliJ IDEA bundled Markdown parity
--
-- editor-markdown.lua already handles rendering (render-markdown.nvim).
-- This adds the language-server half:
-- marksman gives cross-file heading/link completion, go-to-definition on
-- `[wiki]` and `[](relative.md)` links, rename-heading, and broken-link
-- diagnostics -- the editing intelligence IDEA's Markdown plugin provides.
--
-- Tree-sitter markdown/markdown_inline parsers are already in the
-- core-treesitter.lua base list.
--
-- ltex-ls adds the second half IDEA ships via the Grazie plugin: natural
-- language grammar / spelling / style checking (LanguageTool under the hood)
-- for prose in Markdown, LaTeX, reStructuredText, plain text and git commit
-- messages. It is a JVM server fetched by Mason (tools-mason.lua); lsp-core
-- only enables servers whose command is executable, so a machine without it
-- installed simply skips it. Corrections surface as code actions on the
-- global <leader>ca -- no dedicated keymap needed.

return {
  {
    "neovim/nvim-lspconfig",
    opts = function(_, opts)
      opts.servers = opts.servers or {}
      opts.servers.marksman = {
        filetypes = { "markdown", "markdown.mdx" },
      }
      -- ltex-ls is a JVM server and its default `cmd` is `ltex-ls`. If Mason
      -- has not fetched it yet, registering it would make every Markdown
      -- buffer spawn-fail loudly with ENOENT -- so only wire it when the
      -- binary is actually on PATH. Once :MasonToolsInstall pulls it in, a
      -- restart picks it up.
      if vim.fn.executable("ltex-ls") == 1 or vim.fn.executable("ltex-ls-plus") == 1 then
        opts.servers.ltex = {
          filetypes = {
            "markdown",
            "markdown.mdx",
            "tex",
            "plaintex",
            "rst",
            "text",
            "gitcommit",
          },
          settings = {
            ltex = {
              -- Keep the download small and startup fast: en-US only. Add
              -- more via a project-local .ltex config.
              language = "en-US",
              diagnosticSeverity = "hint",
              additionalRules = {
                enablePickyRules = false,
              },
            },
          },
        }
      end
      return opts
    end,
  },
}
