-- TetraVim JavaScript & TypeScript Language Stack Integration
--
-- Provides JS/TS/JSX/TSX support via typescript-language-server (ts_ls)
-- and Tree-sitter parsers.

return {
  {
    "nvim-treesitter/nvim-treesitter",
    opts = function(_, opts)
      if type(opts.ensure_installed) == "table" then
        vim.list_extend(opts.ensure_installed, { "javascript", "typescript", "tsx" })
      end
    end,
  },

  {
    "neovim/nvim-lspconfig",
    opts = {
      servers = {
        -- ts_ls emits no inlay hints unless each class is opted in
        -- explicitly. Mirror the VS Code defaults: parameter-name hints only
        -- where the name isn't obvious from a literal, plus return / param /
        -- property-type hints. Variable-type hints stay off (noisiest).
        -- `importModuleSpecifier = "shortest"` makes auto-import prefer the
        -- package's public entry point over a deep relative path.
        ts_ls = (function()
          local inlay_hints = {
            includeInlayParameterNameHints = "literals",
            includeInlayParameterNameHintsWhenArgumentMatchesName = false,
            includeInlayFunctionParameterTypeHints = true,
            includeInlayVariableTypeHints = false,
            includeInlayPropertyDeclarationTypeHints = true,
            includeInlayFunctionLikeReturnTypeHints = true,
          }
          return {
            settings = {
              typescript = {
                inlayHints = inlay_hints,
                preferences = { importModuleSpecifier = "shortest" },
              },
              javascript = {
                inlayHints = inlay_hints,
                preferences = { importModuleSpecifier = "shortest" },
              },
            },
          }
        end)(),
      },
    },
  },
}
