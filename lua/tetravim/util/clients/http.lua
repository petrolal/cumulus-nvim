-- TetraVim jq-based JSON Response Filtering (SPEC-3.2)
--
-- Shells out to a real `jq` binary via vim.system, mirroring
-- profiling.lua's canonical vim.system(cmd, {text=true}, function(out)
-- vim.schedule(function() ... end) end) async pattern -- jq logic itself is
-- never reimplemented in Lua.

local ui = require("tetravim.util.ui")

local M = {}

-- Guards against a hung/pathologically slow `jq` invocation leaving the
-- async call running indefinitely with no feedback to the user.
local JQ_TIMEOUT_MS = 15000

--- Filter `json_text` through `jq` using `filter_expr`, invoking
--- `callback(result_text)` asynchronously with jq's stdout on success.
--- Never blocks the editor UI. Guards for a missing `jq` binary and surfaces
--- jq's own stderr (syntax errors, etc.) on a nonzero exit -- both paths
--- notify via `ui.notify_err` and never crash; `callback` is only invoked on
--- success.
---@param json_text string
---@param filter_expr string
---@param callback fun(result_text: string)
function M.jq_filter(json_text, filter_expr, callback)
  if vim.fn.executable("jq") ~= 1 then
    ui.notify_err(
      "`jq` is not installed or not on $PATH. Install it (e.g. `brew install jq`, `apt install jq`, "
        .. "`pacman -S jq`) to use response filtering."
    )
    return
  end

  if type(filter_expr) ~= "string" or filter_expr == "" then
    ui.notify_err("A jq filter expression is required")
    return
  end

  if type(json_text) ~= "string" then
    ui.notify_err("No JSON text to filter")
    return
  end

  -- `--` terminates jq's option parsing so a filter expression that begins
  -- with "-" (e.g. `-C .`) is treated as the filter, not an unknown flag.
  vim.system({ "jq", "--", filter_expr }, { text = true, stdin = json_text, timeout = JQ_TIMEOUT_MS }, function(out)
    vim.schedule(function()
      -- vim.system() reports a timeout-triggered kill via code=124/signal=15
      -- (the classic `timeout(1)` convention) -- jq itself never legitimately
      -- exits 124, so this is an unambiguous, separate case from a generic
      -- nonzero-exit jq error.
      if out.code == 124 and out.signal and out.signal ~= 0 then
        ui.notify_err("jq filter timed out after " .. (JQ_TIMEOUT_MS / 1000) .. "s")
      elseif out.code == 0 then
        if type(callback) == "function" then
          callback(out.stdout or "")
        end
      else
        local detail = out.stderr
        if not detail or detail == "" then
          detail = out.stdout or ("jq exited with code " .. tostring(out.code))
        end
        ui.notify_err("jq filter failed: " .. detail)
      end
    end)
  end)
end

--- Whether `text` looks like JSON that jq could usefully filter: either a
--- single value vim.json.decode accepts outright (it requires exactly one
--- top-level value), OR JSON Lines / a concatenated stream of JSON values --
--- every non-blank line individually decodes as its own JSON value -- a
--- legitimate jq input shape vim.json.decode rejects on the whole buffer.
--- Requires at least one non-blank line to avoid a vacuous "true" on
--- whitespace-only input.
---@param text string
---@return boolean
function M.looks_like_json(text)
  if pcall(vim.json.decode, text) then
    return true
  end
  local checked_any_line = false
  for _, line in ipairs(vim.split(text, "\n", { plain = true })) do
    local trimmed = vim.trim(line)
    if trimmed ~= "" then
      checked_any_line = true
      if not pcall(vim.json.decode, trimmed) then
        return false
      end
    end
  end
  return checked_any_line
end

return M
