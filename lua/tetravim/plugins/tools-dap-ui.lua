-- TetraVim DAP UI & Virtual Text Specs (Story 6.1)
-- Extended with stacktrace drill-down (SPEC-010)

return {
  {
    "rcarriga/nvim-dap-ui",
    event = "VeryLazy",
    dependencies = {
      "mfussenegger/nvim-dap",
      "nvim-neotest/nvim-nio",
      "theHamsta/nvim-dap-virtual-text",
    },
    opts = {},
    config = function(_, opts)
      local dap = require("dap")
      local dapui = require("dapui")

      dapui.setup(opts)
      require("nvim-dap-virtual-text").setup({})

      dap.listeners.after.event_initialized["dapui_config"] = function()
        dapui.open()
      end
      dap.listeners.before.event_terminated["dapui_config"] = function()
        dapui.close()
      end
      dap.listeners.before.event_exited["dapui_config"] = function()
        dapui.close()
      end

      -- Setup stacktrace drill-down in DAP REPL & console buffers (SPEC-010)
      local function setup_stacktrace_keymaps()
        local group = vim.api.nvim_create_augroup("tetravim_dap_stacktrace", { clear = true })
        vim.api.nvim_create_autocmd("FileType", {
          group = group,
          pattern = "dap-repl",
          callback = function()
            local opts_keymap = { noremap = true, silent = true, buffer = true }
            vim.keymap.set("n", "gf", function()
              require("tetravim.util.jvm.dap_stacktrace").drill_down_at_line()
            end, vim.tbl_extend("force", opts_keymap, { desc = "Drill Down Stacktrace Symbol" }))

            vim.keymap.set("n", "<CR>", function()
              require("tetravim.util.jvm.dap_stacktrace").drill_down_at_line()
            end, vim.tbl_extend("force", opts_keymap, { desc = "Drill Down Stacktrace Symbol" }))
          end,
        })
      end

      setup_stacktrace_keymaps()
    end,
  },
}
