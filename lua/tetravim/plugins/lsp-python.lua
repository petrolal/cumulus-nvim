-- TetraVim Python Language Stack -- IntelliJ IDEA Ultimate bundled "Python" parity
--
-- Split-responsibility setup, the same shape JetBrains uses internally:
--   basedpyright -> type checking, completion, hover, go-to-definition
--   ruff         -> diagnostics + `source.fixAll` / `source.organizeImports`
--
-- ruff's hover is disabled on attach so basedpyright is the single hover
-- provider (avoids duplicated float content). Formatting is wired through
-- conform (`ruff_organize_imports` + `ruff_format`) in tools-formatting.lua
-- and linting through nvim-lint (`ruff`) in tools-linting.lua.

return {
  {
    "nvim-treesitter/nvim-treesitter",
    opts = function(_, opts)
      if type(opts.ensure_installed) == "table" then
        vim.list_extend(opts.ensure_installed, { "python", "requirements", "toml" })
      end
    end,
  },

  {
    "neovim/nvim-lspconfig",
    opts = {
      servers = {
        basedpyright = {
          settings = {
            basedpyright = {
              analysis = {
                typeCheckingMode = "standard",
                diagnosticMode = "openFilesOnly",
                autoImportCompletions = true,
                autoSearchPaths = true,
                useLibraryCodeForTypes = true,
                -- Inline type / return / argument-name hints, the way
                -- PyCharm shows them. Generic-type hints stay off -- they're
                -- the noisiest of the set.
                inlayHints = {
                  variableTypes = true,
                  callArgumentNames = true,
                  functionReturnTypes = true,
                  genericTypes = false,
                },
              },
            },
          },
        },
        ruff = {
          on_attach = function(client)
            -- basedpyright owns hover; ruff owns diagnostics + code actions.
            client.server_capabilities.hoverProvider = false
          end,
        },
      },
    },
  },
}
