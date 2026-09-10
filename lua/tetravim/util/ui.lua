-- TetraVim notification frontend
--
-- This is TetraVim's primary notifier (~30 call sites). It is a thin facade
-- over `tetravim.util.notify`, which owns the default title/level vocabulary
-- *and* the opt-in telemetry sink -- routing through here means every
-- subsystem notification is captured in `telemetry.log` when telemetry is on.
-- Interactive terminals live in `tetravim.util.term`, not here.

local M = {}

--- Standardized notification dispatcher with default title and level mapping.
---@param msg string Message text
---@param level? number vim.log.levels level (default: INFO)
---@param title? string Notification title (default: "TetraVim")
---@param opts? table Additional notification options (e.g. id, timeout)
function M.notify(msg, level, title, opts)
  local ok, notify = pcall(require, "tetravim.util.notify")
  if ok and type(notify.notify) == "function" then
    notify.notify(msg, level, title, opts)
    return
  end
  -- Fallback: the notify module failed to load -- still surface the message
  -- rather than swallowing it (telemetry capture is lost for this call only).
  vim.notify(msg, level or vim.log.levels.INFO, vim.tbl_extend("force", { title = title or "TetraVim" }, opts or {}))
end

--- Standardized info notification.
---@param msg string Message text
---@param title? string Notification title (default: "TetraVim")
---@param opts? table Additional notification options
function M.notify_info(msg, title, opts)
  M.notify(msg, vim.log.levels.INFO, title, opts)
end

--- Standardized warning notification.
---@param msg string Message text
---@param title? string Notification title (default: "TetraVim")
---@param opts? table Additional notification options
function M.notify_warn(msg, title, opts)
  M.notify(msg, vim.log.levels.WARN, title, opts)
end

--- Standardized error notification.
---@param msg string Message text
---@param title? string Notification title (default: "TetraVim")
---@param opts? table Additional notification options
function M.notify_err(msg, title, opts)
  M.notify(msg, vim.log.levels.ERROR, title, opts)
end

return M
