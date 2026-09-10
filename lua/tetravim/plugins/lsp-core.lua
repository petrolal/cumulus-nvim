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

      if vim.lsp.config and vim.lsp.enable then
        -- 0.11: a "*" config is merged into every named server config, so one
        -- assignment covers lua_ls, kotlin_language_server, html, cssls, ts_ls,
        -- pyright/ruff, yaml, terraform, and everything else routed here.
        vim.lsp.config("*", { capabilities = capabilities })
        for server, server_opts in pairs(opts.servers or {}) do
          vim.lsp.config(server, server_opts or {})
          vim.lsp.enable(server)
        end
      else
        local lspconfig = require("lspconfig")
        for server, server_opts in pairs(opts.servers or {}) do
          if lspconfig[server] then
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
        end,
      })
      -- Drop the dedupe entry when a server process detaches, so a client id
      -- reused after a server restart/crash notifies again (and the table
      -- doesn't accumulate stale ids for a long-lived session).
      vim.api.nvim_create_autocmd("LspDetach", {
        group = notify_group,
        callback = function(args)
          notified_clients[args.data.client_id] = nil
        end,
      })
    end,
  },
}
