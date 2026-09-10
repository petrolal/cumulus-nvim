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
        { "<leader>cb", desc = "Breadcrumbs Picker", icon = "󰘐 " },
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
        { "<leader>cp", group = "node/npm deps", icon = "󰎙 " },
        { "<leader>cpt", desc = "Toggle Dependency Versions", icon = "󰎙 " },
        { "<leader>cps", desc = "Show Dependency Versions", icon = "󰎙 " },
        { "<leader>cph", desc = "Hide Dependency Versions", icon = "󰎙 " },
        { "<leader>cpu", desc = "Update Dependency On Line", icon = "󰎙 " },
        { "<leader>cpd", desc = "Delete Dependency On Line", icon = "󰎙 " },
        { "<leader>cpi", desc = "Install New Dependency", icon = "󰎙 " },
        { "<leader>cpc", desc = "Change Dependency Version", icon = "󰎙 " },
      })

      -- Root Shortcuts
      vim.list_extend(opts.spec, {
        { "<leader>e", desc = "File Explorer (oil)", icon = "󰙅 " },
        { "<leader>z", desc = "Toggle Zen Mode", icon = "󰔡 " },
        { "<leader>.", desc = "Toggle Scratch Buffer", icon = "󰝒 " },
        { "<leader>n", desc = "New File from Template", icon = "󰝒 " },
      })

      -- File / Find (<leader>f)
      vim.list_extend(opts.spec, {
        { "<leader>ff", desc = "Find Files", icon = "󰈞 " },
        { "<leader>fg", desc = "Find Git Files", icon = "󰊢 " },
        { "<leader>fr", desc = "Recent Files", icon = "󰋚 " },
        { "<leader>fb", desc = "Find Buffers", icon = "󰓩 " },
        { "<leader>fs", desc = "Save Current File", icon = "󰆓 " },
        { "<leader>fa", desc = "Save All Files", icon = "󰆓 " },
        { "<leader>fS", desc = "Save As...", icon = "󰆓 " },
        { "<leader>fn", desc = "New File from Template", icon = "󰝒 " },
      })

      -- Search (<leader>s)
      vim.list_extend(opts.spec, {
        { "<leader>sg", desc = "Grep (Root Dir)", icon = "󰍉 " },
        { "<leader>sw", desc = "Search Word Under Cursor", icon = "󰍉 " },
        { "<leader>sd", desc = "Search Diagnostics", icon = "󰒡 " },
        { "<leader>ss", desc = "Search LSP Symbols", icon = "󰙅 " },
        { "<leader>sh", desc = "Help Pages", icon = "󰋽 " },
        { "<leader>sk", desc = "Keymaps", icon = "󰌌 " },
        { "<leader>sn", desc = "Notification History", icon = "󰂚 " },
        { "<leader>sr", desc = "Search & Replace (Project)", icon = "󰛔 " },
        { "<leader>sR", desc = "Search & Replace Word", icon = "󰛔 " },
        { "<leader>sF", desc = "Search & Replace (Current File)", icon = "󰛔 " },
        { "<leader>sm", desc = "Search Marks", icon = "󰃀 " },
        { "<leader>st", desc = "Search TODOs", icon = "󰄲 " },
      })

      -- Buffer (<leader>b)
      vim.list_extend(opts.spec, {
        { "<leader>bd", desc = "Delete Buffer", icon = "󰅖 " },
        { "<leader>bD", desc = "Delete Buffer and Window", icon = "󰅖 " },
        { "<leader>bo", desc = "Delete Other Buffers", icon = "󰅖 " },
        { "<leader>bi", desc = "Delete Invisible Buffers", icon = "󰅖 " },
        { "<leader>bp", desc = "Previous Buffer", icon = "󰒮 " },
        { "<leader>bn", desc = "Next Buffer", icon = "󰒭 " },
        { "<leader>bb", desc = "Switch to Other Buffer", icon = "󰓩 " },
      })

      -- Windows (<leader>w)
      vim.list_extend(opts.spec, {
        { "<leader>ww", desc = "Cycle Windows", icon = "󰖲 " },
        { "<leader>wh", desc = "Focus Left Window", icon = "󰖲 " },
        { "<leader>wj", desc = "Focus Lower Window", icon = "󰖲 " },
        { "<leader>wk", desc = "Focus Upper Window", icon = "󰖲 " },
        { "<leader>wl", desc = "Focus Right Window", icon = "󰖲 " },
        { "<leader>ws", desc = "Split Window Horizontally", icon = "󰤼 " },
        { "<leader>wv", desc = "Split Window Vertically", icon = "󰤻 " },
        { "<leader>wd", desc = "Close Window", icon = "󰅖 " },
      })

      -- Plugin & Tool Management (<leader>l)
      vim.list_extend(opts.spec, {
        { "<leader>ll", desc = "Lazy Plugin Manager", icon = "󰒓 " },
        { "<leader>lm", desc = "Mason Tool Manager", icon = "󰒓 " },
        { "<leader>lc", desc = "Checkhealth System", icon = "󰒓 " },
      })

      -- Git (<leader>g)
      vim.list_extend(opts.spec, {
        { "<leader>gg", desc = "LazyGit", icon = "󰊢 " },
        { "<leader>gl", desc = "Git Log", icon = "󰊢 " },
        { "<leader>gL", desc = "Git Log (Current File)", icon = "󰊢 " },
        { "<leader>gs", desc = "Git Status", icon = "󰊢 " },
        { "<leader>gS", desc = "Git Stash", icon = "󰊢 " },
        { "<leader>gb", desc = "Blame Line", icon = "󰊢 " },
        { "<leader>gB", desc = "Blame Buffer Toggle", icon = "󰊢 " },
        { "<leader>gd", desc = "Git Diff This", icon = "󰊢 " },
        { "<leader>gn", desc = "Neogit (Git Panel)", icon = "󰊢 " },
        { "<leader>gC", desc = "Neogit Commit", icon = "󰊢 " },
        { "<leader>ghs", desc = "Stage Hunk", icon = "󰊢 " },
        { "<leader>ghr", desc = "Reset Hunk", icon = "󰊢 " },
        { "<leader>ghu", desc = "Undo Stage Hunk", icon = "󰊢 " },
        { "<leader>ghp", desc = "Preview Hunk", icon = "󰊢 " },
        { "<leader>gco", desc = "Open Merge Tool / Diff", icon = " " },
        { "<leader>gcq", desc = "Close Diffview Tab", icon = " " },
        { "<leader>gch", desc = "File Diff History", icon = " " },
        { "<leader>gcH", desc = "Range Diff History", icon = " " },
        { "<leader>gcf", desc = "Toggle File Panel", icon = " " },
        { "<leader>grp", desc = "List & Review PRs", icon = "󰊢 " },
        { "<leader>grc", desc = "Checkout PR Branch", icon = "󰊢 " },
        { "<leader>grC", desc = "Add PR Comment", icon = "󰊢 " },
      })

      -- Debugging / DAP (<leader>d)
      vim.list_extend(opts.spec, {
        { "<leader>db", desc = "Toggle Breakpoint", icon = "󰃤 " },
        { "<leader>dc", desc = "Continue / Start Debugging", icon = "󰃤 " },
        { "<leader>di", desc = "Step Into", icon = "󰃤 " },
        { "<leader>do", desc = "Step Over", icon = "󰃤 " },
        { "<leader>dO", desc = "Step Out", icon = "󰃤 " },
        { "<leader>dr", desc = "Open REPL", icon = "󰃤 " },
        { "<leader>du", desc = "Toggle DAP UI", icon = "󰃤 " },
        { "<leader>dt", desc = "Terminate Debugging", icon = "󰃤 " },
        { "<leader>dC", desc = "Conditional Breakpoint", icon = "󰃤 " },
        { "<leader>dL", desc = "Logpoint", icon = "󰃤 " },
        { "<leader>dE", desc = "Set Exception Breakpoints", icon = "󰃤 " },
        { "<leader>dv", desc = "Evaluate Variable", icon = "󰃤 " },
      })

      -- API & Data Clients (<leader>a)
      vim.list_extend(opts.spec, {
        { "<leader>ae", desc = "Endpoints Panel", icon = "󰛳 " },
        { "<leader>adu", desc = "Toggle Database UI", icon = "󰆼 " },
        { "<leader>adf", desc = "Find DB Buffer", icon = "󰆼 " },
        { "<leader>ada", desc = "Add DB Connection", icon = "󰆼 " },
        { "<leader>ahr", desc = "Run HTTP Request", icon = "󰖟 " },
        { "<leader>aho", desc = "Generate .http from OpenAPI", icon = "󰖟 " },
        { "<leader>ahj", desc = "jq-Filter JSON Response", icon = "󰖟 " },
        { "<leader>agg", desc = "gRPC UI", icon = "󱅥 " },
        { "<leader>agl", desc = "List Services & Methods", icon = "󱅥 " },
        { "<leader>agm", desc = "Describe Symbol", icon = "󱅥 " },
        { "<leader>agi", desc = "Generate Request Skeleton", icon = "󱅥 " },
        { "<leader>agf", desc = "Format .proto Buffer", icon = "󱅥 " },
      })

      -- Test Runner (<leader>t)
      vim.list_extend(opts.spec, {
        { "<leader>tr", desc = "Run Nearest Test", icon = "󰙨 " },
        { "<leader>tf", desc = "Run Test File", icon = "󰙨 " },
        { "<leader>ts", desc = "Toggle Test Summary", icon = "󰙨 " },
        { "<leader>to", desc = "Toggle Test Output Panel", icon = "󰙨 " },
        { "<leader>td", desc = "Debug Nearest Test (DAP)", icon = "󰙨 " },
      })

      -- Quality & Security (<leader>x)
      vim.list_extend(opts.spec, {
        { "<leader>xx", desc = "Problems (Workspace Diagnostics)", icon = "󰒡 " },
        { "<leader>xX", desc = "Problems (Buffer Diagnostics)", icon = "󰒡 " },
        { "<leader>xq", desc = "Quickfix List (Trouble)", icon = "󰒡 " },
        { "<leader>xL", desc = "Location List (Trouble)", icon = "󰒡 " },
        { "<leader>xt", desc = "TODO List (Trouble)", icon = "󰄲 " },
        { "<leader>xdb", desc = "Line Diagnostics (Float)", icon = "󰒡 " },
        { "<leader>xdp", desc = "All Project (Quickfix)", icon = "󰒡 " },
        { "<leader>xlb", desc = "Check Buffer", icon = "󰉢 " },
        { "<leader>xlp", desc = "Check All Code (Project)", icon = "󰉢 " },
        { "<leader>xlf", desc = "Fix Buffer (writes file)", icon = "󰉢 " },
        { "<leader>xlF", desc = "Fix All Code (Project)", icon = "󰉢 " },
        { "<leader>xsb", desc = "Rule Description (Buffer)", icon = "󰒃 " },
        { "<leader>xsp", desc = "Scan Whole Project", icon = "󰒃 " },
        { "<leader>xvb", desc = "Scan Build File (Buffer)", icon = "󰒃 " },
        { "<leader>xvp", desc = "Scan Whole Project", icon = "󰒃 " },
        { "<leader>xvc", desc = "Clear Scan Diagnostics", icon = "󰒃 " },
      })

      -- UI & Toggles (<leader>u)
      vim.list_extend(opts.spec, {
        { "<leader>uf", desc = "Autoformat (Buffer)", icon = "󰉢 " },
        { "<leader>uF", desc = "Autoformat (Global)", icon = "󰉢 " },
        { "<leader>ul", desc = "Autolint (Buffer)", icon = "󰉢 " },
        { "<leader>uL", desc = "Autolint (Global)", icon = "󰉢 " },
        { "<leader>ut", desc = "Transparency", icon = "󰔡 " },
        { "<leader>uh", desc = "Inlay Hints", icon = "󰔡 " },
        { "<leader>uv", desc = "Diagnostic Virtual Lines", icon = "󰒡 " },
        { "<leader>un", desc = "Dismiss All Notifications", icon = "󰂚 " },
        { "<leader>uu", desc = "Toggle Undo History", icon = "󰋚 " },
        { "<leader>um", desc = "Toggle Markdown Preview", icon = "󰍔 " },
      })

      -- Run & Tasks (<leader>r)
      vim.list_extend(opts.spec, {
        { "<leader>rr", desc = "Run Task (pick template)", icon = "󱓞 " },
        { "<leader>rt", desc = "Toggle Task List", icon = "󱓞 " },
        { "<leader>ra", desc = "Task Quick Action", icon = "󱓞 " },
        { "<leader>rb", desc = "Build a New Task", icon = "󱓞 " },
        { "<leader>ri", desc = "Overseer Info / Diagnostics", icon = "󱓞 " },
        { "<leader>rl", desc = "Re-run Last Task", icon = "󱓞 " },
      })

      -- Marks & Bookmarks (<leader>m)
      vim.list_extend(opts.spec, {
        { "<leader>ml", desc = "List Marks (Buffer)", icon = "󰃀 " },
        { "<leader>mL", desc = "List Marks (All Buffers)", icon = "󰃀 " },
        { "<leader>mq", desc = "Marks -> Quickfix", icon = "󰃀 " },
        { "<leader>mx", desc = "Delete All Lowercase Marks", icon = "󰃀 " },
        { "<leader>mX", desc = "Delete All Marks", icon = "󰃀 " },
        { "<leader>mb", desc = "List Bookmarks (Buffer)", icon = "󰃀 " },
        { "<leader>mB", desc = "List Bookmarks (All Buffers)", icon = "󰃀 " },
      })

      -- Quit & Session (<leader>q)
      vim.list_extend(opts.spec, {
        { "<leader>qq", desc = "Quit Neovim (Confirm)", icon = "󰗼 " },
        { "<leader>qQ", desc = "Force Quit Neovim (No Save)", icon = "󰗼 " },
        { "<leader>qs", desc = "Restore Session", icon = "󰦛 " },
        { "<leader>ql", desc = "Restore Last Session", icon = "󰦛 " },
        { "<leader>qd", desc = "Don't Save Current Session", icon = "󰦛 " },
      })

      -- Bracket navigation groups
      vim.list_extend(opts.spec, {
        { "[", group = "prev", icon = "󰒮 " },
        { "]", group = "next", icon = "󰒭 " },
        { "g", group = "goto/lsp", icon = "󰘐 " },
      })

      -- Per-language <leader>c* subgroups (Maven/Gradle, Terraform,
      -- Ansible, Docker (<leader>cD to avoid the global <leader>cd
      -- Line Diagnostics keymap), Helm...). These are registered with buffer = true,
      -- so which-key only surfaces them while the current buffer's
      -- filetype actually owns matching buffer-local keymaps -- see
      -- lua/tetravim/core/lang_keymaps.lua.
      vim.list_extend(opts.spec, require("tetravim.core.lang_keymaps").whichkey_spec())

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
