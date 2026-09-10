-- TetraVim Core Options (Story 1.1 & Story 2.1)

vim.g.mapleader = " "
vim.g.maplocalleader = "\\"

vim.g.have_nerd_font = true

-- Enterprise headless mode flag (Story 5‑2)
vim.g.tetravim_headless = false

-- Telemetry enable flag (Story 5‑2)
vim.g.tetravim_telemetry_enabled = false

-- Set headless flag from environment variable if present
if vim.env.TETRAVIM_HEADLESS == "1" then
  vim.g.tetravim_headless = true
end

-- Enable 24-bit true color support for theme highlights (Story 5.1)
vim.opt.termguicolors = true

-- Sync yank/paste with the OS clipboard (fixes y/p not reaching system
-- clipboard). Deferred, and skipped entirely in headless mode: setting this
-- at load time makes the first yank probe for xclip/xsel/wl-copy, which on a
-- bare SSH / CI session with no provider is wasted work (and noise).
vim.schedule(function()
  if not vim.g.tetravim_headless then
    vim.opt.clipboard = "unnamedplus"
  end
end)

-- Visual polish -------------------------------------------------------------
-- One consistent rounded frame around every plugin-agnostic floating window
-- (LSP hover / signature help, `vim.diagnostic.open_float`, `vim.ui`
-- prompts, `:checkhealth` popups...). Plugins that draw their own borders
-- (telescope, which-key's "helix" preset, noice) are unaffected. Native
-- since Neovim 0.11.
if vim.fn.exists("&winborder") == 1 then
  vim.opt.winborder = "rounded"
end

-- Highlight the line the cursor sits on -- the "Tetris" theme already ships
-- a dedicated CursorLine surface colour for it.
vim.opt.cursorline = true

-- Keep a little breathing room around the cursor while scrolling.
vim.opt.scrolloff = 6
vim.opt.sidescrolloff = 8

-- Idle delay before `CursorHold` fires. The default 4s makes LSP
-- symbol-under-cursor highlighting (wired per client in util/lsp_attach.lua)
-- feel broken; 300ms is the usual IDE-like "highlight usages" cadence.
vim.opt.updatetime = 300

-- Persistent undo: keep the full undo tree on disk so it survives a restart.
-- This is what turns undotree (editor-undotree.lua) into a real "Local
-- History" -- time-travel through past edits of a file days later, not just
-- within the current session.
vim.opt.undofile = true
vim.opt.undolevels = 10000

-- Cleaner chrome: drop the "~" end-of-buffer tildes and give folds /
-- vertical splits softer glyphs than the default ASCII.
vim.opt.fillchars = {
  eob = " ",
  fold = " ",
  foldsep = " ",
  diff = "╱",
}

-- Apply the canonical TetraVim "Tetris" colour scheme
vim.schedule(function()
  require("tetravim.theme").load_saved_theme()
end)
