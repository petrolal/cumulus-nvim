-- TetraVim WhichKey Keybinding Helper Integration (Story 8.4, Story 10.1, Story 12.3, Story 20.1, Story 21.2, Story 23.2, Story 24.2 & Story 34.1)

return {
  {
    "folke/which-key.nvim",
    event = "VeryLazy",
    opts = function(_, opts)
      opts.preset = "helix"
      opts.spec = opts.spec or {}
      vim.list_extend(opts.spec, {
        { "<leader>c", group = "code/lsp", icon = "󰅍 " },
        { "<leader>f", group = "file/find", icon = "󰈞 " },
        { "<leader>s", group = "search", icon = "󰍉 " },
        { "<leader>b", group = "buffer", icon = "󰓩 " },
        { "<leader>w", group = "windows", icon = "󰖲 " },
        { "<leader>l", group = "lazy/mason/lsp", icon = "󰒓 " },
        { "<leader>g", group = "git control", icon = "󰊢 " },
        { "<leader>gh", group = "git hunks", icon = "󰊢 " },
        -- <leader>gc children (gco/gcq/gch/gcH/gcf) are global. The <leader>gx
        -- / <leader>gX conflict-pick groups are registered buffer-locally for
        -- diffview buffers only -- see lua/tetravim/plugins/tools-diffview.lua.
        { "<leader>gc", group = "conflict/compare", icon = " " },
        { "<leader>gr", group = "git review", icon = "󰊢 " },
        -- <leader>o (devops/infra) and its five subgroups come from
        -- devops.whichkey_spec() lower down -- the single source of truth.
        { "<leader>d", group = "debug/dap", icon = "󰃤 " },
        -- API & data-service clients. These were three separate Shift-prefixed
        -- top-level groups (<leader>D / <leader>H / <leader>G) that collided
        -- with <leader>d and <leader>g; folded under one lowercase <leader>a.
        { "<leader>a", group = "api/data", icon = "󰖟 " },
        { "<leader>ae", desc = "Endpoints Panel", icon = "󰛳 " },
        { "<leader>ad", group = "database", icon = "󰆼 " },
        { "<leader>ah", group = "http", icon = "󰖟 " },
        { "<leader>ag", group = "grpc/proto", icon = "󱅥 " },
        { "<leader>t", group = "test runner", icon = "󰙨 " },
        { "<leader>x", group = "quality/security", icon = "󰒃 " },
        { "<leader>xd", group = "diagnostics", icon = "󰒡 " },
        { "<leader>xl", group = "lint", icon = "󰉢 " },
        { "<leader>xs", group = "sonar", icon = "󰒃 " },
        { "<leader>xv", group = "cve/vulns", icon = "󰒃 " },
        { "<leader>u", group = "ui/toggles", icon = "󰔡 " },
        { "<leader>r", group = "run/tasks", icon = "󱓞 " },
        { "<leader>m", group = "marks/bookmarks", icon = "󰃀 " },
        { "<leader>q", group = "quit/session", icon = "󰗼 " },
      })

      -- Per-key `desc` + category icon for the <leader>c ("code/lsp") popup.
      -- These entries only annotate keys defined elsewhere (core/keymaps.lua,
      -- editor-outline.lua, editor-docgen.lua, util/extract.lua); which-key
      -- orders them with its default sort (alphanum within the group). The
      -- "-- Actions / Refactor / ..." banners below are reading aids for this
      -- source list, not a runtime grouping.
      vim.list_extend(opts.spec, {
        -- Actions --------------------------------------------------------
        { "<leader>ca", desc = "Code Action", icon = "󰌵 " },
        { "<leader>cA", desc = "Source Action", icon = "󰌵 " },
        { "<leader>co", desc = "Organize Imports", icon = "󰗧 " },
        -- Refactor -----------------------------------------------------
        { "<leader>cr", desc = "Rename Symbol", icon = "󰑕 " },
        { "<leader>cR", desc = "Rename File", icon = "󰑕 " },
        -- Docs -------------------------------------------------------
        { "<leader>cg", desc = "Generate Doc (function)", icon = "󰈙 " },
        { "<leader>cG", desc = "Generate Doc (class/type)", icon = "󰈙 " },
        -- Format ---------------------------------------------------
        { "<leader>cf", desc = "Format", icon = "󰉢 " },
        { "<leader>cF", desc = "Format Injected Langs", icon = "󰉢 " },
        -- Diagnostics ------------------------------------------------
        { "<leader>cd", desc = "Line Diagnostics", icon = "󰒡 " },
        -- CodeLens -------------------------------------------------
        { "<leader>cc", desc = "Run Codelens", icon = "󰊕 " },
        { "<leader>cC", desc = "Refresh & Display Codelens", icon = "󰊕 " },
        -- Navigate / Info ------------------------------------------
        { "<leader>cs", desc = "Symbols Outline (Structure)", icon = "󰙅 " },
        { "<leader>cl", desc = "Lsp Info", icon = "󰋽 " },
        -- Hierarchy ----------------------------------------------
        { "<leader>ch", group = "hierarchy", icon = "󰘐 " },
        { "<leader>chi", desc = "Incoming Calls", icon = "󰘐 " },
        { "<leader>cho", desc = "Outgoing Calls", icon = "󰘐 " },
        { "<leader>chs", desc = "Type Hierarchy (Subtypes)", icon = "󰙅 " },
        { "<leader>chS", desc = "Type Hierarchy (Supertypes)", icon = "󰙅 " },
        -- Generate / advanced refactor -------------------------
        { "<leader>cn", desc = "Generate...", icon = "󰛨 " },
        { "<leader>ck", desc = "Change Signature / Rewrite", icon = "󰑕 " },
        { "<leader>cy", desc = "Safe Delete / Inline", icon = "󰅖 " },
        { "<leader>ct", desc = "LSP References / Defs (Trouble)", icon = "󰋽 " },
      })

      -- Per-language <leader>c* subgroups (Maven/Gradle, Terraform,
      -- Ansible, Docker (<leader>cD to avoid the global <leader>cd
      -- Line Diagnostics keymap), Helm...). These are registered with buffer = true,
      -- so which-key only surfaces them while the current buffer's
      -- filetype actually owns matching buffer-local keymaps -- see
      -- lua/tetravim/core/lang-keymaps.lua.
      vim.list_extend(opts.spec, require("tetravim.core.lang-keymaps").whichkey_spec())

      -- DevOps & Infrastructure Tooling Suite (<leader>o). The group and its
      -- five subgroups come from devops.whichkey_spec() -- the module that also
      -- owns the keymaps -- so the list lives in exactly one place.
      vim.list_extend(opts.spec, require("tetravim.core.devops").whichkey_spec())

      -- JVM platform (<leader>j) groups, likewise sourced from the module that
      -- owns the keymaps. jvm.setup_keymaps() no longer calls wk.add itself.
      vim.list_extend(opts.spec, require("tetravim.util.jvm").whichkey_spec())
      return opts
    end,
  },
}
