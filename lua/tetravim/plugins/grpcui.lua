-- TetraVim gRPC UI plugin (letieu/grpcui.nvim)
return {
  {
    "letieu/grpcui.nvim",
    dependencies = { "ibhagwan/fzf-lua" },
    ft = { "proto", "http" },
    config = function()
      require("grpcui").setup({
        -- optional: customize JSON LSP if desired
        -- jsonls_cmd = { "vscode-json-languageserver", "--stdio" },
      })

      -- Workaround for letieu/grpcui.nvim (upstream 16955a3, unfixed):
      -- `UI.init_ui()` passes `columns / 2` straight through as a split
      -- window width. On a terminal with an odd `columns` that is a
      -- non-integer, and `nvim_open_win` aborts the whole :GrpcUi open with
      --   E5108: Invalid 'width': Number is not integral
      -- `init.lua` reads `UI.init_ui` off the module table at call time, so
      -- swapping the field here takes effect. `init_ui` is fully synchronous
      -- (returns buffers, wins, tab_id), so the nvim_open_win shim only needs
      -- to live for that one call.
      local grpcui_ui = require("grpcui.ui")
      local orig_init_ui = grpcui_ui.init_ui
      grpcui_ui.init_ui = function(...)
        local orig_open_win = vim.api.nvim_open_win
        vim.api.nvim_open_win = function(buf, enter, cfg)
          if type(cfg) == "table" then
            if type(cfg.width) == "number" then
              cfg.width = math.floor(cfg.width)
            end
            if type(cfg.height) == "number" then
              cfg.height = math.floor(cfg.height)
            end
          end
          return orig_open_win(buf, enter, cfg)
        end
        local ok, buffers, wins, tab_id = pcall(orig_init_ui, ...)
        vim.api.nvim_open_win = orig_open_win
        if not ok then
          error(buffers, 0)
        end
        return buffers, wins, tab_id
      end
    end,
  },
}
