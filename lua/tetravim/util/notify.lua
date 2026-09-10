-- TetraVim notification helpers
--
-- Thin, consistent wrappers around vim.notify so every subsystem emits messages
-- under one title and level vocabulary.

local M = {}

--- Standardized notification dispatcher with default title and level mapping.
---@param msg string Message text
---@param level? number vim.log.levels level (default: INFO)
---@param title? string Notification title (default: "TetraVim")
---@param opts? table Additional notification options (e.g. id, timeout)
function M.notify(msg, level, title, opts)
  level = level or vim.log.levels.INFO
  title = title or "TetraVim"
  opts = vim.tbl_extend("force", { title = title }, opts or {})
  vim.notify(msg, level, opts)
  -- Telemetry: if enabled, also log a JSON line to the telemetry file
  if vim.g.tetravim_telemetry_enabled then
    local log_path = vim.fn.stdpath("config") .. "/telemetry.log"
    local entry = vim.json.encode({
      -- os.time() already returns epoch seconds in UTC. The old
      -- os.time(os.date("!*t")) fed a UTC calendar table back through
      -- os.time(), which reads its argument as *local* time -- skewing
      -- every logged timestamp by the machine's UTC offset.
      timestamp = os.time(),
      level = (function(lvl)
        if lvl == vim.log.levels.INFO then
          return "info"
        elseif lvl == vim.log.levels.WARN then
          return "warn"
        elseif lvl == vim.log.levels.ERROR then
          return "error"
        else
          return "unknown"
        end
      end)(level),
      msg = msg,
      source = title,
    })
    -- Bounded log: roll over to a single `.1` backup once the file passes
    -- ~1 MiB so an always-on session cannot grow telemetry.log without limit.
    -- The rotation (a stat + two metadata ops, only when actually over the
    -- limit) stays synchronous so it is guaranteed to happen before the
    -- append; the append itself -- the part that runs on every notification
    -- -- is handed to libuv so the main thread never blocks on disk I/O.
    local MAX_BYTES = 1024 * 1024
    local uv = vim.uv
    local stat = uv.fs_stat(log_path)
    if stat and stat.size and stat.size > MAX_BYTES then
      os.remove(log_path .. ".1")
      os.rename(log_path, log_path .. ".1")
    end
    uv.fs_open(log_path, "a", tonumber("644", 8), function(err, fd)
      if err or not fd then
        return
      end
      uv.fs_write(fd, entry .. "\n", -1, function()
        uv.fs_close(fd, function() end)
      end)
    end)
  end
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

--- Enable telemetry collection.
function M.enable_telemetry()
  vim.g.tetravim_telemetry_enabled = true
end

--- Disable telemetry collection.
function M.disable_telemetry()
  vim.g.tetravim_telemetry_enabled = false
end

vim.api.nvim_create_user_command("TetraVimTelemetryEnable", function()
  require("tetravim.util.notify").enable_telemetry()
end, { desc = "Enable telemetry" })

vim.api.nvim_create_user_command("TetraVimTelemetryDisable", function()
  require("tetravim.util.notify").disable_telemetry()
end, { desc = "Disable telemetry" })

return M
