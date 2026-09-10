-- TetraVim Scala LSP + DAP Integration (scalameta/nvim-metals) -- SPEC-1.1
--
-- Metals self-registers its own DAP adapter/configurations the same way
-- jdtls does (see ftplugin/java.lua's jdtls.setup_dap call): once attached,
-- calling metals.setup_dap() populates dap.configurations.scala with no
-- manual launch JSON required from the user.

return {
  {
    "scalameta/nvim-metals",
    ft = { "scala", "sbt" },
    dependencies = {
      "nvim-lua/plenary.nvim",
      "mfussenegger/nvim-dap",
    },
    opts = function()
      local metals_config = require("metals").bare_config()

      -- Shared cmp-nvim-lsp completion capabilities (same table lsp-core.lua
      -- and ftplugin/java.lua use) so Metals returns snippet completions and
      -- resolvable documentation for the popup.
      metals_config.capabilities = require("tetravim.util.lsp_capabilities").make()

      -- Surface the implicits / inferred types Metals can compute -- this is
      -- the Scala equivalent of jdtls parameter-name inlay hints, and the
      -- super-method lens is genuinely useful in deep trait hierarchies. The
      -- excluded packages keep completion / search from drowning in the
      -- akka-javadsl shims that a Scala project never calls.
      metals_config.settings = {
        showImplicitArguments = true,
        showImplicitConversionsAndClasses = true,
        showInferredType = true,
        superMethodLensesEnabled = true,
        excludedPackages = { "akka.actor.typed.javadsl", "com.github.swagger.akka.javadsl" },
      }

      metals_config.on_attach = function(client, bufnr)
        -- Mirrors jdtls.setup_dap({ hotcodereplace = "auto" }) in
        -- ftplugin/java.lua: registers dap.adapters.scala and
        -- dap.configurations.scala from Metals' own DAP discovery, so no
        -- manual launch JSON is ever required (AC-1).
        require("metals").setup_dap()

        -- Same per-client IntelliSense wiring every lsp-core.lua server gets
        -- (inlay hints / document highlight / <C-k> signature help). Metals
        -- attaches through its own path, so call it here explicitly.
        pcall(function()
          require("tetravim.util.lsp_attach").on_attach(client, bufnr)
        end)
      end

      -- Bounded auto-restart (max 3 / 180s) if the Metals BSP process exits
      -- unexpectedly, matching the jdtls handling in ftplugin/java.lua.
      metals_config.on_exit = require("tetravim.util.lsp_resilience").make_on_exit("metals", function()
        vim.schedule(function()
          pcall(function()
            require("metals").initialize_or_attach(metals_config)
          end)
        end)
      end)

      return metals_config
    end,
    config = function(self, metals_config)
      local metals_group = vim.api.nvim_create_augroup("tetravim_nvim_metals", { clear = true })
      vim.api.nvim_create_autocmd("FileType", {
        group = metals_group,
        pattern = self.ft,
        callback = function()
          require("metals").initialize_or_attach(metals_config)
        end,
      })
    end,
  },
}
