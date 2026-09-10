-- TetraVim Groovy Full Stack Integration (Story 40.1)

-- Jenkinsfile has no file extension, so Neovim's built-in filetype
-- detection never maps it to "groovy" on its own.
vim.filetype.add({
  filename = {
    Jenkinsfile = "groovy",
  },
})

return {
  {
    "nvim-treesitter/nvim-treesitter",
    opts = function(_, opts)
      if type(opts.ensure_installed) == "table" then
        vim.list_extend(opts.ensure_installed, { "groovy" })
      end
    end,
  },

  {
    "neovim/nvim-lspconfig",
    opts = {
      servers = {
        -- groovyls has no inlay-hint / code-lens support and no sound
        -- classpath resolver, so there are no meaningful `settings` to add
        -- here -- it stays default. The generic on_exit auto-restart from
        -- lsp-core.lua and the shared lsp_attach wiring (document highlight /
        -- signature help, both capability-gated) still apply.
        groovyls = {},
      },
    },
  },
}
