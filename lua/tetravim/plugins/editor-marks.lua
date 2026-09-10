-- TetraVim Marks & Bookmarks -- IntelliJ IDEA "Bookmarks" parity
--
-- IDEA's Bookmarks let you drop a named/mnemonic marker on a line and jump
-- back to it from anywhere, with a tool-window list. Vim's built-in marks do
-- the jumping but show nothing in the gutter and have no list UI. marks.nvim
-- adds the sign-column indicator, preview, next/prev motion, and a quickfix
-- list -- plus a separate "bookmark group" layer (bookmark0..bookmark9) that
-- maps onto IDEA's numbered mnemonic bookmarks.
--
-- Default keymaps stay on the familiar `m` prefix (mx sets/toggles mark x,
-- dmx deletes it, m] / m[ move between marks). The <leader>m group below is
-- just the list / bulk-delete surface.

return {
  {
    "chentoast/marks.nvim",
    event = { "BufReadPost", "BufNewFile" },
    keys = {
      { "<leader>ml", "<cmd>MarksListBuf<cr>", desc = "List Marks (Buffer)" },
      { "<leader>mL", "<cmd>MarksListAll<cr>", desc = "List Marks (All Buffers)" },
      { "<leader>mq", "<cmd>MarksQFListAll<cr>", desc = "Marks -> Quickfix" },
      { "<leader>mx", "<cmd>delmarks a-z<cr>", desc = "Delete All Lowercase Marks (Buffer)" },
      { "<leader>mX", "<cmd>delmarks!<cr>", desc = "Delete All Marks (Buffer)" },
      { "<leader>mb", "<cmd>BookmarksListAll<cr>", desc = "List Bookmarks (All Buffers)" },
      { "<leader>mB", "<cmd>BookmarksQFListAll<cr>", desc = "Bookmarks -> Quickfix" },
      {
        "<leader>sm",
        function()
          -- Reuse the quickfix list marks.nvim builds, then let trouble or
          -- the native quickfix window render it -- consistent with how the
          -- rest of the distro surfaces lists.
          vim.cmd("MarksQFListAll")
          if pcall(require, "trouble") then
            vim.cmd("Trouble qflist toggle")
          else
            vim.cmd("copen")
          end
        end,
        desc = "Search Marks",
      },
    },
    opts = {
      -- a-z lowercase + A-Z global. Skip the builtin 0-9 (jumplist history)
      -- and punctuation marks so the gutter only shows marks the user set.
      builtin_marks = { ".", "<", ">", "^" },
      default_mappings = true,
      cyclic = true,
      force_write_shada = false,
      refresh_interval = 250,
      sign_priority = { lower = 10, upper = 15, builtin = 8, bookmark = 20 },
      excluded_filetypes = {
        "help",
        "qf",
        "NvimTree",
        "neo-tree",
        "TelescopePrompt",
        "lazy",
        "mason",
        "Outline",
        "trouble",
        "undotree",
        "gitcommit",
      },
      bookmark_0 = { sign = "⚑", virt_text = "bookmark" },
      mappings = {
        -- IDEA "Toggle Bookmark" ~= mm; keep the plugin defaults for the rest.
        delete_line = "dm-",
        delete_buf = "dm<space>",
      },
    },
  },
}
