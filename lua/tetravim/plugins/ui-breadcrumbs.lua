-- TetraVim Winbar Breadcrumbs (IntelliJ "navigation bar" parity)
--
-- dropbar.nvim paints a clickable path + code-symbol trail in the winbar,
-- fed by tree-sitter and LSP document symbols. It sets `winbar` itself for
-- every window its `bar.enable` predicate accepts, so there is no lualine
-- wiring to do.
--
--   <leader>cb  interactive symbol picker at the cursor
--   [;  / ];    jump to / descend into the enclosing context

return {
  {
    "Bekaboo/dropbar.nvim",
    event = { "BufReadPost", "BufNewFile" },
    opts = {
      bar = {
        -- Winbar only in real file windows -- keep it off the dashboard,
        -- oil, DAP UI, pickers, help and quickfix.
        enable = function(buf, win, _)
          if not buf or not win or not vim.api.nvim_buf_is_valid(buf) or not vim.api.nvim_win_is_valid(win) then
            return false
          end
          local bt = vim.bo[buf].buftype
          if bt ~= "" and bt ~= "acwrite" then
            return false
          end
          if vim.api.nvim_buf_get_name(buf) == "" then
            return false
          end
          local excluded = {
            oil = true,
            ["snacks_dashboard"] = true,
            ["snacks_picker_list"] = true,
            ["snacks_layout_box"] = true,
            help = true,
            qf = true,
            man = true,
            gitcommit = true,
            TelescopePrompt = true,
            ["dap-repl"] = true,
            dapui_watches = true,
            dapui_stacks = true,
            dapui_breakpoints = true,
            dapui_scopes = true,
            dapui_console = true,
          }
          return not excluded[vim.bo[buf].filetype]
        end,
      },
      icons = {
        ui = { bar = { separator = "  ", extends = "…" } },
      },
      menu = {
        -- Match the global `winborder = "rounded"` chrome.
        win_configs = { border = "rounded" },
      },
    },
    config = function(_, opts)
      require("dropbar").setup(opts)

      local api = require("dropbar.api")
      vim.keymap.set("n", "<leader>cb", function()
        api.pick()
      end, { desc = "Breadcrumbs Picker" })
      vim.keymap.set("n", "[;", function()
        api.goto_context_start()
      end, { desc = "Go to Context Start" })
      vim.keymap.set("n", "];", function()
        api.select_next_context()
      end, { desc = "Select Next Context" })
    end,
  },
}
