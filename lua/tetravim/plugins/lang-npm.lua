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
-- All keymaps are buffer-local and only bound in a `package.json` buffer, so
-- they never leak into other JSON files. Namespace: <leader>cn ("code /
-- node deps"). Degrades to nothing if no package manager binary is present.

return {
  {
    "vuki656/package-info.nvim",
    dependencies = { "MunifTanjim/nui.nvim" },
    event = { "BufRead package.json" },
    config = function()
      require("package-info").setup({
        colors = {
          up_to_date = "#3C4048",
          outdated = "#d19a66",
        },
        icons = {
          enable = true,
          style = { up_to_date = "|  ", outdated = "|  " },
        },
        autostart = true,
        hide_up_to_date = false,
        hide_unstable_versions = false,
        -- Auto-detect: falls back to npm if pnpm/yarn aren't found.
        package_manager = (vim.fn.executable("pnpm") == 1 and "pnpm")
          or (vim.fn.executable("yarn") == 1 and "yarn")
          or "npm",
      })

      local function bind_keys(bufnr)
        if not bufnr or not vim.api.nvim_buf_is_valid(bufnr) then
          return
        end
        local pi = require("package-info")
        local ok_wk, wk = pcall(require, "which-key")
        if ok_wk then
          wk.add({ { "<leader>cp", group = "node/npm deps", icon = "󰎙 ", buffer = bufnr } })
        end
        local map = function(lhs, fn, desc)
          vim.keymap.set("n", lhs, fn, { buffer = bufnr, desc = desc, silent = true })
        end
        map("<leader>cpt", pi.toggle, "Toggle Dependency Versions")
        map("<leader>cps", pi.show, "Show Dependency Versions")
        map("<leader>cph", pi.hide, "Hide Dependency Versions")
        map("<leader>cpu", pi.update, "Update Dependency On Line")
        map("<leader>cpd", pi.delete, "Delete Dependency On Line")
        map("<leader>cpi", pi.install, "Install New Dependency")
        map("<leader>cpc", pi.change_version, "Change Dependency Version")
      end

      -- Attach immediately to current buffer if package.json
      local cur_buf = vim.api.nvim_get_current_buf()
      if vim.fs.basename(vim.api.nvim_buf_get_name(cur_buf)) == "package.json" then
        bind_keys(cur_buf)
      end

      vim.api.nvim_create_autocmd({ "BufRead", "BufNewFile" }, {
        group = vim.api.nvim_create_augroup("tetravim_package_info_keys", { clear = true }),
        pattern = "package.json",
        callback = function(args)
          bind_keys(args.buf)
        end,
      })
    end,
  },
}
