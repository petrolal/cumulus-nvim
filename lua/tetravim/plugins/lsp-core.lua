-- TetraVim Core LSP Engine (Epic 3)

-- Every server configured across the lsp-*.lua/cloud-*.lua specs attaches
-- automatically, per-buffer, whenever nvim-lspconfig's `.setup()` sees a
-- matching filetype in the project -- that's already "load based on the
-- project/files present", no extra wiring needed. What's missing is
-- visibility: attaching happens silently, so there's no way to tell a
-- language server is genuinely running vs. just configured. This notifies
-- once per server *process* (deduped by client id, not by buffer) the first
-- time each one attaches.
local attach_messages = {
  jdtls = "JDTLS attached -- test runner & refactor keymaps are ready",
  kotlin_lsp = "Kotlin LSP (JetBrains) attached",
  kotlin_language_server = "Kotlin Language Server attached",
  html = "HTML Language Server attached",
  cssls = "CSS Language Server attached",
  ts_ls = "TypeScript / JavaScript Language Server attached",
  lua_ls = "Lua Language Server attached",
}

return {
  {
    "neovim/nvim-lspconfig",
    event = { "BufReadPre", "BufNewFile" },
    dependencies = {
      "williamboman/mason.nvim",
    },
    opts = {
      servers = {},
    },
    config = function(_, opts)
      -- Shared capabilities table (cmp-nvim-lsp extended completion support +
      -- native fold hints). This is what turns on real IntelliSense -- servers
      -- only emit snippet edits / resolvable docs when the client claims to
      -- understand them. jdtls (ftplugin/java.lua) and metals (lsp-scala.lua)
      -- inject the same table on their own start paths.
      local capabilities = require("tetravim.util.lsp_capabilities").make()
      local resilience = require("tetravim.util.lsp_resilience")

      if vim.lsp.config and vim.lsp.enable then
        -- 0.11: a "*" config is merged into every named server config, so one
        -- assignment covers lua_ls, kotlin_language_server, html, cssls, ts_ls,
        -- pyright/ruff, yaml, terraform, and everything else routed here.
        -- Hand each merge target its own copy -- the merge mutates the table
        -- in place, and a shared reference has leaked capabilities between
        -- servers before.
        vim.lsp.config("*", { capabilities = vim.deepcopy(capabilities) })
        for server, server_opts in pairs(opts.servers or {}) do
          server_opts = server_opts or {}
          if server_opts.enabled ~= false then
            -- Bounded auto-restart for every generically-configured server, not
            -- just jdtls/metals: an unexpected exit re-enables the server (max
            -- 3 times / 180s, then it gives up and points at :LspLog). Specs
            -- that need bespoke restart handling set their own `on_exit`.
            if server_opts.on_exit == nil then
              local name = server
              server_opts.on_exit = resilience.make_on_exit(name, function()
                pcall(vim.lsp.enable, name, false)
                pcall(vim.lsp.enable, name)
              end)
            end
            vim.lsp.config(server, server_opts)
            vim.lsp.enable(server)
          end
        end
      else
        local lspconfig = require("lspconfig")
        for server, server_opts in pairs(opts.servers or {}) do
          if server_opts and server_opts.enabled ~= false and lspconfig[server] then
            lspconfig[server].setup(
              vim.tbl_deep_extend("keep", server_opts or {}, { capabilities = vim.deepcopy(capabilities) })
            )
          end
        end
      end

      -- If buffers are already opened, trigger FileType so their LSP attaches immediately
      for _, bufnr in ipairs(vim.api.nvim_list_bufs()) do
        if vim.api.nvim_buf_is_loaded(bufnr) and vim.bo[bufnr].buftype == "" and vim.bo[bufnr].filetype ~= "" then
          vim.api.nvim_exec_autocmds("FileType", { buffer = bufnr })
        end
      end

      local notified_clients = {}
      local notify_group = vim.api.nvim_create_augroup("tetravim_lsp_attach_notify", { clear = true })
      vim.api.nvim_create_autocmd("LspAttach", {
        group = notify_group,
        callback = function(args)
          local client = vim.lsp.get_client_by_id(args.data.client_id)
          if not client or notified_clients[client.id] then
            return
          end
          notified_clients[client.id] = true
          vim.notify(attach_messages[client.name] or (client.name .. " attached"), vim.log.levels.INFO)

          -- Per-client IntelliSense wiring shared by every server routed here
          -- (inlay hints, symbol-under-cursor document highlight, <C-k>
          -- signature help), each capability-gated. jdtls / metals call the
          -- same module from their own attach paths.
          pcall(function()
            require("tetravim.util.lsp_attach").on_attach(client, args.buf)
          end)
        end,
      })
      -- Drop the dedupe entry when a server process detaches, so a client id
      -- reused after a server restart/crash notifies again (and the table
      -- doesn't accumulate stale ids for a long-lived session).
      vim.api.nvim_create_autocmd("LspDetach", {
        group = notify_group,
        callback = function(args)
          notified_clients[args.data.client_id] = nil
          -- Tear down the document-highlight autocmds / reference marks this
          -- buffer picked up on attach, so a detached server doesn't keep
          -- firing on CursorHold.
          pcall(function()
            require("tetravim.util.lsp_attach").on_detach(args.buf)
          end)
        end,
      })
    end,
  },
}
