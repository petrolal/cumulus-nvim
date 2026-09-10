local ui = require("tetravim.util.ui")

local banner = [[
  ╭────────────────────────────────────────────────╮  
  │                                                │  
  │   ████████      ██                   ██ ██     │  
  │      ██   ___  █████ _ __ ____  _  _ ██ ██     │  
  │      ██  / -_)  ██  | '__/ _  || |/ /   ██ ██  │  
  │      ██  \___|  \__ | |  \__,_| \__/ ██ ██     │  
  │                                                │  
  ╰────────────────────────────────────────────────╯  
               JVM & CLOUD-NATIVE ECOSYSTEM           
]]

-- Dashboard git-sha reader + footer section builder, and the snacks.nvim
-- runtime patches / <leader>u state toggles, live in util/ so this spec stays a
-- declarative list of opts/keys.
local dashboard = require("tetravim.util.dashboard")
local snacks_ext = require("tetravim.util.snacks_ext")

return {
  {
    "folke/snacks.nvim",
    priority = 1000,
    -- NOTE: must load eagerly because the dashboard renders at VimEnter on a bare `nvim` invocation
    lazy = false,
    opts = function(_, opts)
      opts.styles = opts.styles or {}
      opts.styles.notification = vim.tbl_deep_extend("force", opts.styles.notification or {}, {
        title = " ☁ ",
      })
      opts.styles.notification_history = vim.tbl_deep_extend("force", opts.styles.notification_history or {}, {
        title = " ☁ Notifications ",
      })

      opts.picker = vim.tbl_deep_extend("force", opts.picker or {}, {
        enabled = true,
        ui_select = true,
        prompt = " ☁ >",
        sources = {
          lsp_implementations = {
            include_current = true,
          },
        },
      })

      opts.notifier = opts.notifier or {}
      opts.notifier.enabled = true
      opts.notifier.timeout = 3000

      opts.image = opts.image or {}
      opts.image.enabled = true
      opts.image.doc = { inline = true }

      -- Disable code insight (Tree-sitter, LSP, folds, syntax) for very large
      -- buffers -- the native equivalent of IntelliJ's "file too large" guard.
      opts.bigfile = vim.tbl_deep_extend("force", opts.bigfile or {}, { enabled = true })

      -- Animations are the classic latency complaint over SSH / tmux / mosh,
      -- and this distro is explicitly "used on real work" -- often remote.
      -- Keep the visuals, drop the motion when we detect a remote session.
      local remote = (vim.env.SSH_TTY or vim.env.SSH_CONNECTION) ~= nil

      -- Indent guides + an animated highlight of the scope the cursor is
      -- currently inside, so nesting is readable at a glance.
      opts.indent = vim.tbl_deep_extend("force", opts.indent or {}, {
        enabled = true,
        char = "│",
        only_scope = false,
        only_current = false,
        scope = {
          enabled = true,
          char = "│",
          underline = false,
          hl = "SnacksIndentScope",
        },
        animate = {
          enabled = not remote,
          duration = { step = 15, total = 300 },
        },
      })

      -- Smooth cursor-relative scrolling and a rounded `vim.ui.input` prompt
      -- that matches the rest of the floating-window chrome.
      opts.scroll = vim.tbl_deep_extend("force", opts.scroll or {}, { enabled = not remote })
      opts.input = vim.tbl_deep_extend("force", opts.input or {}, { enabled = true })

      opts.dashboard = opts.dashboard or {}
      local opened_dir = false
      for _, arg in
        ipairs(vim.fn.argv() --[[@as string[] ]])
      do
        if vim.fn.isdirectory(arg) == 1 then
          opened_dir = true
          break
        end
      end
      opts.dashboard.enabled = not opened_dir
      opts.dashboard.sections = {
        { section = "header", padding = 2, align = "center" },
        { section = "keys", gap = 1, padding = 2 },
        { section = "startup", padding = 2, align = "center" },
        dashboard.footer_section,
      }
      opts.dashboard.preset = opts.dashboard.preset or {}
      opts.dashboard.preset.header = banner
      opts.dashboard.preset.keys = {
        {
          icon = "󰈞 ",
          key = "f",
          desc = "Find File",
          action = function()
            Snacks.picker.files()
          end,
        },
        { icon = "󰝒 ", key = "n", desc = "New File", action = ":ene | startinsert" },
        {
          icon = "✨ ",
          key = "p",
          desc = "New Project Wizard",
          action = function()
            require("tetravim.util.project_wizard").create_project()
          end,
        },
        {
          icon = "󰋚 ",
          key = "r",
          desc = "Recent Files",
          action = function()
            Snacks.picker.recent()
          end,
        },
        {
          icon = "󰍉 ",
          key = "g",
          desc = "Find Text (Grep)",
          action = function()
            Snacks.picker.grep()
          end,
        },
        {
          icon = "󱥸 ",
          key = "t",
          desc = "Terraform Workspace",
          action = function()
            Snacks.picker.files({ cwd = vim.fn.getcwd() })
          end,
        },
        {
          icon = "󰡨 ",
          key = "d",
          desc = "LazyDocker Terminal",
          action = function()
            Snacks.terminal("lazydocker")
          end,
        },
        {
          icon = "󰊢 ",
          key = "v",
          desc = "LazyGit Control",
          action = function()
            Snacks.terminal("lazygit")
          end,
        },
        {
          icon = "󰒓 ",
          key = "c",
          desc = "Config",
          action = function()
            Snacks.picker.files({ cwd = vim.fn.stdpath("config") })
          end,
        },
        {
          icon = "󰦛 ",
          key = "s",
          desc = "Restore Session",
          action = function()
            local ok, persistence = pcall(require, "persistence")
            if ok then
              persistence.load()
            else
              ui.notify_warn("persistence.nvim is not loaded")
            end
          end,
        },
        { icon = "󰏖 ", key = "l", desc = "Lazy", action = ":Lazy" },
        { icon = "󰗼 ", key = "q", desc = "Quit", action = ":confirm qa" },
      }
      return opts
    end,
    config = function(_, opts)
      require("snacks").setup(opts)
      vim.notify = function(msg, level, notify_opts)
        Snacks.notifier.notify(msg, level, notify_opts)
      end

      snacks_ext.suppress_image_health()
      snacks_ext.guard_picker_jump()
      snacks_ext.register_state_toggles()
    end,
    keys = {
      {
        "<leader>ff",
        function()
          Snacks.picker.files()
        end,
        desc = "Find Files",
      },
      {
        "<leader>fg",
        function()
          Snacks.picker.git_files()
        end,
        desc = "Find Git Files",
      },
      {
        "<leader>fr",
        function()
          Snacks.picker.recent()
        end,
        desc = "Recent",
      },
      {
        "<leader>fb",
        function()
          Snacks.picker.buffers()
        end,
        desc = "Buffers",
      },
      {
        "<leader>sg",
        function()
          Snacks.picker.grep()
        end,
        desc = "Grep (Root Dir)",
      },
      {
        "<leader>sw",
        function()
          Snacks.picker.grep_word()
        end,
        desc = "Visual selection or word",
        mode = { "n", "x" },
      },
      {
        "<leader>sd",
        function()
          Snacks.picker.diagnostics()
        end,
        desc = "Search Diagnostics",
      },
      {
        "<leader>ss",
        function()
          Snacks.picker.lsp_symbols()
        end,
        desc = "Search LSP Symbols",
      },
      {
        "<leader>sh",
        function()
          Snacks.picker.help()
        end,
        desc = "Help Pages",
      },
      {
        "<leader>sk",
        function()
          Snacks.picker.keymaps()
        end,
        desc = "Keymaps",
      },
      {
        "gd",
        function()
          if #vim.lsp.get_clients({ bufnr = 0, method = "textDocument/definition" }) > 0 then
            Snacks.picker.lsp_definitions()
          else
            pcall(vim.cmd, "normal! gd")
          end
        end,
        mode = "n",
        desc = "Goto Definition (Smart Fallback)",
      },
      {
        "gD",
        function()
          if #vim.lsp.get_clients({ bufnr = 0, method = "textDocument/declaration" }) > 0 then
            Snacks.picker.lsp_declarations()
          else
            pcall(vim.cmd, "normal! gD")
          end
        end,
        mode = "n",
        desc = "Goto Declaration (Smart Fallback)",
      },
      {
        "gy",
        function()
          if #vim.lsp.get_clients({ bufnr = 0, method = "textDocument/typeDefinition" }) > 0 then
            Snacks.picker.lsp_type_definitions()
          else
            ui.notify_warn("LSP type definition not supported for buffer")
          end
        end,
        mode = "n",
        desc = "Goto Type Definition",
      },
      {
        "gi",
        function()
          if #vim.lsp.get_clients({ bufnr = 0, method = "textDocument/implementation" }) > 0 then
            Snacks.picker.lsp_implementations({ include_current = true })
          else
            pcall(vim.cmd, "normal! gi")
          end
        end,
        mode = "n",
        desc = "Goto Implementation (Smart Fallback)",
      },
      {
        "gr",
        function()
          if #vim.lsp.get_clients({ bufnr = 0, method = "textDocument/references" }) > 0 then
            Snacks.picker.lsp_references()
          else
            Snacks.picker.grep_word()
          end
        end,
        mode = "n",
        desc = "References (Grep Fallback)",
      },
      {
        "<leader>gg",
        function()
          Snacks.terminal("lazygit")
        end,
        desc = "LazyGit",
      },
      {
        "<leader>gl",
        function()
          Snacks.picker.git_log()
        end,
        desc = "Git Log",
      },
      {
        "<leader>gL",
        function()
          Snacks.picker.git_log_file()
        end,
        desc = "Git Log (Current File)",
      },
      {
        "<leader>gs",
        function()
          Snacks.picker.git_status()
        end,
        desc = "Git Status",
      },
      {
        "<leader>gS",
        function()
          Snacks.picker.git_stash()
        end,
        desc = "Git Stash",
      },
      {
        "<leader>z",
        function()
          Snacks.zen()
        end,
        desc = "Toggle Zen Mode",
      },
      {
        "<leader>.",
        function()
          Snacks.scratch()
        end,
        desc = "Toggle Scratch Buffer",
      },
      {
        "<leader>sn",
        function()
          Snacks.notifier.show_history()
        end,
        desc = "Notification History",
      },
      {
        "<C-/>",
        function()
          Snacks.terminal()
        end,
        desc = "Terminal",
      },
      {
        "<leader>un",
        function()
          Snacks.notifier.hide()
        end,
        desc = "Dismiss All Notifications",
      },
      {
        "<leader>bd",
        function()
          Snacks.bufdelete()
        end,
        desc = "Delete Buffer",
      },
      {
        "<leader>bD",
        "<cmd>bd<cr>",
        desc = "Delete Buffer and Window",
      },
      {
        "<leader>bo",
        function()
          Snacks.bufdelete.other()
        end,
        desc = "Delete Other Buffers",
      },
      {
        "<leader>bi",
        function()
          Snacks.bufdelete.invisible()
        end,
        desc = "Delete Invisible Buffers",
      },
      -- Sequential buffer nav. All <leader>b* ownership lives in this spec so
      -- there is one file to look in; core/keymaps.lua no longer defines any.
      { "<leader>bp", "<cmd>bprevious<cr>", desc = "Previous Buffer" },
      { "<leader>bn", "<cmd>bnext<cr>", desc = "Next Buffer" },
      { "<leader>b1", "<cmd>BufferLineGoToBuffer 1<cr>", desc = "Go to Buffer 1" },
      { "<leader>b2", "<cmd>BufferLineGoToBuffer 2<cr>", desc = "Go to Buffer 2" },
      { "<leader>b3", "<cmd>BufferLineGoToBuffer 3<cr>", desc = "Go to Buffer 3" },
      { "<leader>b4", "<cmd>BufferLineGoToBuffer 4<cr>", desc = "Go to Buffer 4" },
      { "<leader>b5", "<cmd>BufferLineGoToBuffer 5<cr>", desc = "Go to Buffer 5" },
      { "<leader>b6", "<cmd>BufferLineGoToBuffer 6<cr>", desc = "Go to Buffer 6" },
      { "<leader>b7", "<cmd>BufferLineGoToBuffer 7<cr>", desc = "Go to Buffer 7" },
      { "<leader>b8", "<cmd>BufferLineGoToBuffer 8<cr>", desc = "Go to Buffer 8" },
      { "<leader>b9", "<cmd>BufferLineGoToBuffer 9<cr>", desc = "Go to Buffer 9" },
      {
        "<leader>bb",
        "<cmd>e #<cr>",
        desc = "Switch to Other Buffer",
      },
      { "<S-h>", "<cmd>bprevious<cr>", desc = "Prev Buffer" },
      { "<S-l>", "<cmd>bnext<cr>", desc = "Next Buffer" },
      { "[b", "<cmd>bprevious<cr>", desc = "Prev Buffer" },
      { "]b", "<cmd>bnext<cr>", desc = "Next Buffer" },
    },
  },
  {
    "folke/persistence.nvim",
    -- Must load on every startup, not just when a real file buffer is read
    -- ("BufReadPre" never fires if you only browse the dashboard/explorer),
    -- otherwise persistence.nvim's save autocmd (and our explorer-reopen
    -- hook below) never get registered and no session is saved at all.
    event = "VimEnter",
    opts = {},
    config = function(_, opts)
      require("persistence").setup(opts)
      -- mksession has no concept of the Snacks explorer (it's a picker, not
      -- a real file buffer), so if it's left open when a session is saved,
      -- its window is serialized as a blank `enew` buffer and comes back
      -- empty on restore instead of reopening the explorer. Close it before
      -- saving and reopen it once the session loads back in.
      require("tetravim.util.session").setup()
    end,
    keys = {
      {
        "<leader>qs",
        function()
          require("persistence").load()
        end,
        desc = "Restore Session",
      },
      {
        "<leader>ql",
        function()
          require("persistence").load({ last = true })
        end,
        desc = "Restore Last Session",
      },
      {
        "<leader>qd",
        function()
          require("persistence").stop()
        end,
        desc = "Don't Save Current Session",
      },
    },
  },
}
