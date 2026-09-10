-- TetraVim Web-Tooling Language Servers
-- IntelliJ IDEA Ultimate parity for the cross-cutting web helpers that are
-- "always on" in the IDE rather than tied to one language:
--   eslint      -> project-config-driven JS/TS diagnostics + fix-all
--   tailwindcss -> class-name completion, hover previews, lint
--   emmet       -> abbreviation expansion for every HTML-ish buffer
--
-- These attach on top of ts_ls / html / cssls / the framework servers; they
-- do not replace them.

return {
  {
    "neovim/nvim-lspconfig",
    opts = {
      servers = {
        eslint = {
          settings = {
            workingDirectories = { mode = "auto" },
          },
          on_attach = function(_, bufnr)
            -- `:LspEslintFixAll` on write, mirroring IDEA's "Run eslint --fix
            -- on save". Guarded per-buffer; no global autocmd.
            vim.api.nvim_create_autocmd("BufWritePre", {
              buffer = bufnr,
              command = "silent! LspEslintFixAll",
            })
          end,
        },
        tailwindcss = {},
        emmet_language_server = {
          filetypes = {
            "html",
            "css",
            "scss",
            "less",
            "sass",
            "javascriptreact",
            "typescriptreact",
            "vue",
            "svelte",
            "astro",
            "htmldjango",
            "eruby",
            "pug",
            "freemarker",
            "velocity",
            "jsp",
          },
        },
      },
    },
  },
}
