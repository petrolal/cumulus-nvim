-- lua/tetravim/core/health_json.lua
-- Machine-readable health snapshot for CI / provisioning (see docs/CLAUDE.md).
-- The human-facing `:checkhealth tetravim` report lives in lua/tetravim/health.lua
-- and already re-validates this JSON inline, so this module deliberately does NOT
-- register its own `:checkhealth` provider.

local M = {}

--- Return health information as JSON string
function M.json()
  local neovim_version = vim.version()
  local version_str = string.format("%d.%d.%d", neovim_version.major, neovim_version.minor, neovim_version.patch)

  -- LSP client names
  local lsp_clients = vim.lsp.get_clients()
  local client_names = {}
  for _, client in ipairs(lsp_clients) do
    table.insert(client_names, client.name)
  end

  -- Plugin count via lazy.nvim core config if available
  local plugin_count = 0
  local ok, lazy_cfg = pcall(require, "lazy.core.config")
  if ok and lazy_cfg.plugins then
    for _ in pairs(lazy_cfg.plugins) do
      plugin_count = plugin_count + 1
    end
  end

  -- Pending async tasks: LSP requests still in flight across all clients
  -- (the async work TetraVim actually drives -- see util/lsp_async.lua).
  -- `client.requests` keeps entries for completed and cancelled requests too;
  -- only `type == "pending"` is genuinely still in flight.
  local async_tasks = 0
  for _, client in ipairs(lsp_clients) do
    for _, req in pairs(client.requests or {}) do
      if type(req) == "table" and req.type == "pending" then
        async_tasks = async_tasks + 1
      end
    end
  end

  local telemetry_enabled = vim.g.tetravim_telemetry_enabled == true

  local health_tbl = {
    neovim_version = version_str,
    lsp_clients = client_names,
    plugin_count = plugin_count,
    pending_async_tasks = async_tasks,
    telemetry_enabled = telemetry_enabled,
  }

  return vim.json.encode(health_tbl)
end

-- Register user command
vim.api.nvim_create_user_command("CheckHealthJson", function()
  vim.api.nvim_out_write(M.json() .. "\n")
end, { desc = "Echo health information as JSON" })

return M
