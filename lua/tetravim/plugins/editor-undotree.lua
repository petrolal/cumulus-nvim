-- TetraVim Undo History Visualiser -- IntelliJ IDEA "Local History" parity
--
-- IDEA's Local History keeps a timeline of every edit independent of VCS.
-- Neovim's persistent undo already stores the full undo *tree* on disk
-- (undofile); undotree draws it as a navigable timeline with per-state diffs
-- and time-travel, which is the same recovery workflow.
--
-- Persistent undo itself is configured in core/options.lua -- this spec only
-- adds the viewer in pure Lua with diff previews.

return {
  {
    "jiaoshijie/undotree",
    dependencies = { "nvim-lua/plenary.nvim" },
    keys = {
      {
        "<leader>uu",
        function()
          require("undotree").toggle()
        end,
        desc = "Toggle Undo History",
      },
    },
    opts = {
      float_diff = true,
      layout = "left_bottom",
      position = "left",
      ignore_filetype = {
        "Undotree",
        "UndotreeDiff",
        "qf",
        "TelescopePrompt",
        "spectre_panel",
        "tsplayground",
      },
      window = {
        winblend = 10,
      },
      -- Upstream flipped this map to [action] = lhs (see `:h undotree-configuration`).
      keymaps = {
        move_next = "j",
        move_prev = "k",
        move_change_next = "J",
        move_change_prev = "K",
        action_enter = "<cr>",
        enter_diffbuf = "p",
        quit = "q",
      },
    },
  },
}
