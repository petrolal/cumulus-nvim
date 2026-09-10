-- TetraVim package.json Dependency Lens -- IntelliJ IDEA "Package.json" /
-- npm dependency inlay parity.
--
-- IDEA (with the JavaScript plugin) annotates each dependency line in
-- package.json with its installed vs. latest version and offers a one-click
-- upgrade. package-info.nvim reproduces that: virtual-text version hints on
-- every dependency line, colour-coded (up-to-date / minor-behind / major-
-- behind), plus change-version / update / delete actions driven by the
-- detected package manager (npm | pnpm | yarn).
--
-- All keymaps operate when inside a `package.json` buffer. Namespace:
-- <leader>cp ("code / package / npm deps"). Degrades cleanly if no package
-- manager binary is present.

return {
  {
    "vuki656/package-info.nvim",
    dependencies = { "MunifTanjim/nui.nvim" },
    event = { "BufReadPost", "BufNewFile" },
    keys = {
      {
        "<leader>cpt",
        function()
          if vim.fs.basename(vim.api.nvim_buf_get_name(0)) ~= "package.json" then
            require("tetravim.util.ui").notify_warn("Open package.json first -- <leader>cpt operates on package.json")
            return
          end
          require("package-info").toggle()
        end,
        desc = "Toggle Dependency Versions",
      },
      {
        "<leader>cps",
        function()
          if vim.fs.basename(vim.api.nvim_buf_get_name(0)) ~= "package.json" then
            require("tetravim.util.ui").notify_warn("Open package.json first -- <leader>cps operates on package.json")
            return
          end
          require("package-info").show()
        end,
        desc = "Show Dependency Versions",
      },
      {
        "<leader>cph",
        function()
          if vim.fs.basename(vim.api.nvim_buf_get_name(0)) ~= "package.json" then
            require("tetravim.util.ui").notify_warn("Open package.json first -- <leader>cph operates on package.json")
            return
          end
          require("package-info").hide()
        end,
        desc = "Hide Dependency Versions",
      },
      {
        "<leader>cpu",
        function()
          if vim.fs.basename(vim.api.nvim_buf_get_name(0)) ~= "package.json" then
            require("tetravim.util.ui").notify_warn("Open package.json first -- <leader>cpu operates on package.json")
            return
          end
          require("package-info").update()
        end,
        desc = "Update Dependency On Line",
      },
      {
        "<leader>cpd",
        function()
          if vim.fs.basename(vim.api.nvim_buf_get_name(0)) ~= "package.json" then
            require("tetravim.util.ui").notify_warn("Open package.json first -- <leader>cpd operates on package.json")
            return
          end
          require("package-info").delete()
        end,
        desc = "Delete Dependency On Line",
      },
      {
        "<leader>cpi",
        function()
          if vim.fs.basename(vim.api.nvim_buf_get_name(0)) ~= "package.json" then
            require("tetravim.util.ui").notify_warn("Open package.json first -- <leader>cpi operates on package.json")
            return
          end
          require("package-info").install()
        end,
        desc = "Install New Dependency",
      },
      {
        "<leader>cpc",
        function()
          if vim.fs.basename(vim.api.nvim_buf_get_name(0)) ~= "package.json" then
            require("tetravim.util.ui").notify_warn("Open package.json first -- <leader>cpc operates on package.json")
            return
          end
          require("package-info").change_version()
        end,
        desc = "Change Dependency Version",
      },
    },
    opts = {
      highlights = {
        up_to_date = {
          fg = "#3C4048",
        },
        outdated = {
          fg = "#d19a66",
        },
      },
      icons = {
        enable = true,
        style = { up_to_date = "|  ", outdated = "|  " },
      },
      autostart = true,
      hide_up_to_date = false,
      hide_unstable_versions = false,
      package_manager = (vim.fn.executable("pnpm") == 1 and "pnpm")
        or (vim.fn.executable("yarn") == 1 and "yarn")
        or "npm",
    },
    config = function(_, opts)
      require("package-info").setup(opts)
    end,
  },
}
