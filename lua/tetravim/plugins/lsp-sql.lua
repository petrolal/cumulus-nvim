-- TetraVim SQL Language Stack -- IntelliJ IDEA Ultimate bundled database-tools parity
--
-- Two layers, matching what IDEA's "Database" plugin gives you:
--   query execution / schema browsing -> vim-dadbod (see tools-dadbod.lua)
--   language intelligence             -> sqlls (sql-language-server: completion,
--                                        hover, go-to-def)
--
-- Tree-sitter `sql` provides syntax highlighting and is also probed by
-- `:checkhealth tetravim` (Embedded Database Explorer section).

return {
  {
    "nvim-treesitter/nvim-treesitter",
    opts = function(_, opts)
      if type(opts.ensure_installed) == "table" then
        vim.list_extend(opts.ensure_installed, { "sql" })
      end
    end,
  },

  {
    "neovim/nvim-lspconfig",
    opts = {
      servers = {
        sqlls = {
          filetypes = { "sql", "mysql", "plsql" },
        },
      },
    },
  },
}
