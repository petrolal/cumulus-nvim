-- TetraVim Neovim Distribution Entry Point

-- Byte-compiled Lua module cache (Neovim 0.9+). This distribution eagerly
-- require()s ~40 util modules and ~60 plugin specs on every launch, so the
-- loader cache is a measurable, zero-risk startup win. Must run before the
-- first non-trivial require() below.
if vim.loader and vim.loader.enable then
  vim.loader.enable()
end

-- Hard requirement: TetraVim uses vim.lsp.config / vim.lsp.enable,
-- vim.diagnostic.jump and winborder -- all 0.11 APIs. On an older Neovim the
-- failure is an opaque stack trace deep inside a plugin spec, so fail loudly
-- and early with an actionable message instead.
if vim.fn.has("nvim-0.11") == 0 then
  vim.api.nvim_echo({
    { "tetravim.nvim requires Neovim >= 0.11\n", "ErrorMsg" },
    { "Running: " .. tostring(vim.version()) .. "\n", "WarningMsg" },
  }, true, {})
  return
end

local config_dir = vim.fn.fnamemodify(debug.getinfo(1, "S").source:sub(2), ":p:h")
if not vim.tbl_contains(vim.opt.rtp:get(), config_dir) then
  vim.opt.rtp:prepend(config_dir)
end

require("tetravim.util.notify")
require("tetravim.core")
require("tetravim.core.lazy")
