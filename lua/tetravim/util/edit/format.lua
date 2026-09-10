-- Autoformat toggle helper (Story 34.2)
--
-- Provides a global `vim.g.autoformat` flag and a per-buffer
-- `vim.b.autoformat` override so users can disable format-on-save
-- globally or just for the current buffer, without touching
-- conform.nvim's `formatters_by_ft` configuration.
-- `tools-formatting.lua`'s `format_on_save` callback consults
-- `enabled()` before running so the toggle actually takes effect.

local M = {}

local ui = require("tetravim.util.ui")

---@param buf? number
---@return boolean
function M.enabled(buf)
  buf = (buf == nil or buf == 0) and vim.api.nvim_get_current_buf() or buf
  local baf = vim.b[buf].autoformat

  if baf ~= nil then
    return baf
  end

  return (vim.g.autoformat ~= false)
end

---@param buf? number
function M.info(buf)
  buf = buf or vim.api.nvim_get_current_buf()
  local gaf = (vim.g.autoformat ~= false)
  local baf = vim.b[buf].autoformat
  local enabled = M.enabled(buf)
  local lines = {
    ("global: %s"):format(gaf and "enabled" or "disabled"),
    ("buffer: %s"):format(baf == nil and "inherit" or (baf and "enabled" or "disabled")),
  }
  ui.notify(
    table.concat(lines, "\n"),
    enabled and vim.log.levels.INFO or vim.log.levels.WARN,
    "Autoformat (" .. (enabled and "enabled" or "disabled") .. ")"
  )
end

---@param buf boolean If true, toggle for the current buffer only; otherwise toggle globally.
function M.toggle(buf)
  local bufnr = buf and vim.api.nvim_get_current_buf() or nil
  local enable = not M.enabled(bufnr)
  if buf then
    vim.b.autoformat = enable
  else
    vim.g.autoformat = enable
    vim.b.autoformat = nil
  end
  M.info()
end

---@param opts? {force?:boolean, buf?:number}
function M.format(opts)
  opts = opts or {}
  local buf = opts.buf or vim.api.nvim_get_current_buf()
  if not (opts.force or M.enabled(buf)) then
    return
  end

  local ok, conform = pcall(require, "conform")
  if ok then
    conform.format({ bufnr = buf, lsp_format = "fallback", timeout_ms = 3000 })
  else
    vim.lsp.buf.format({ bufnr = buf, timeout_ms = 3000 })
  end
end

return M
