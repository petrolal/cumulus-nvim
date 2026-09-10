-- TetraVim Git tool window (IDEA "Git" / "Commit" / "Log" panels)
--
-- gitsigns (tools-gitsigns.lua) covers the gutter + hunk staging; diffview
-- (tools-diffview.lua) covers the file-diff / merge views. neogit is the
-- missing piece: a full-screen porcelain for staging, committing, branching,
-- rebasing, stashing and log browsing without dropping to a shell. It reuses
-- the already-present diffview.nvim for its diff panes.

return {
  {
    "NeogitOrg/neogit",
    cmd = "Neogit",
    dependencies = {
      "nvim-lua/plenary.nvim",
      "sindrets/diffview.nvim",
    },
    opts = {
      integrations = { diffview = true },
      graph_style = "unicode",
    },
    -- <leader>gg is LazyGit (editor-snacks.lua) and <leader>gl is Snacks'
    -- git_log; Neogit takes the free <leader>gn ("git / neogit") plus the
    -- free capitalised <leader>gC for a direct commit. Log / pull / push /
    -- branch / stash / rebase are all one keystroke away inside the panel.
    keys = {
      { "<leader>gn", "<cmd>Neogit<cr>", desc = "Neogit (Git Panel)" },
      { "<leader>gC", "<cmd>Neogit commit<cr>", desc = "Neogit Commit" },
    },
  },
}
