-- TetraVim Problems panel (IDEA "Problems" tool window)
--
-- A docked, navigable list of every diagnostic in the workspace / buffer plus
-- the LSP location lists (references / definitions) and quickfix. Complements
-- editor-outline.lua (Structure) and todo-comments (<leader>xt). Keys live in
-- the <leader>x ("quality/security") group next to the raw diagnostic dumps.

return {
  {
    "folke/trouble.nvim",
    cmd = "Trouble",
    opts = {
      focus = true,
      warn_no_results = false,
      open_no_results = true,
    },
    keys = {
      { "<leader>xx", "<cmd>Trouble diagnostics toggle<cr>", desc = "Problems (Workspace Diagnostics)" },
      {
        "<leader>xX",
        "<cmd>Trouble diagnostics toggle filter.buf=0<cr>",
        desc = "Problems (Buffer Diagnostics)",
      },
      { "<leader>xq", "<cmd>Trouble qflist toggle<cr>", desc = "Quickfix List (Trouble)" },
      { "<leader>xL", "<cmd>Trouble loclist toggle<cr>", desc = "Location List (Trouble)" },
      { "<leader>ct", "<cmd>Trouble lsp toggle focus=false win.position=right<cr>", desc = "LSP References / Defs" },
    },
  },
}
