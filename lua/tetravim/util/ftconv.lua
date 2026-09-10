-- TetraVim per-filetype editor conventions.
--
-- The thin `ftplugin/*.lua` files (css, html, javascript, typescript, lua, sql,
-- xml, http, proto, jsp, velocity, freemarker) each opened with the same four
-- lines of 2-space soft-tab setup before their own commentstring / comments /
-- match_words. That indent block lives here now so the "TetraVim uses a 2-space
-- soft tab" decision has one home; every ftplugin still owns its comment and
-- matchit specifics.

local M = {}

--- Buffer-local 2-space soft-tab indent (`expandtab`, `shiftwidth` /
--- `tabstop` / `softtabstop` = width). Meant to be called from an
--- `ftplugin/*.lua`, where `vim.bo` targets the buffer being set up.
---@param width integer|nil defaults to 2
function M.soft_tabs(width)
  width = width or 2
  vim.bo.shiftwidth = width
  vim.bo.tabstop = width
  vim.bo.softtabstop = width
  vim.bo.expandtab = true
end

return M
