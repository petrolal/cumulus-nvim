-- TetraVim Theme Loader
-- ---------------------
-- TetraVim ships a single, canonical colour scheme: the self-contained
-- "Tetris" palette in `tetravim.theme.tetris`. This module is the thin
-- loader / persistence shim that the core bootstrap (`core/options.lua`)
-- and the statusline integration (`plugins/ui-theme.lua`) call into.
--
-- History: this file was previously a multi-provider "Cloud Theme
-- Switcher" that delegated to an external binary for AWS / Azure / GCP /
-- OCI accent palettes (read from `~/.config/tetravim/theme/state` +
-- `palette.json`). That system, its provider tables and the `set_theme` /
-- `select_theme` picker have been removed -- TetraVim now standardises
-- strictly on the Tetris palette.

local M = {}

--- Canonical colourscheme name. Kept as a function because call sites
--- historically treated the return value as an opaque theme token; there
--- is now exactly one value.
---@return string
function M.get_current_theme()
  return "tetravim"
end

--- Apply the canonical Tetris palette and refresh the derived UI colour
--- cache consumed by lualine / bufferline.
function M.apply()
  local ok, tetris = pcall(require, "tetravim.theme.tetris")
  if not ok then
    vim.notify("tetravim.theme.tetris failed to load: " .. tostring(tetris), vim.log.levels.ERROR)
    return
  end

  tetris.apply()

  local colors_ok, theme_colors = pcall(require, "tetravim.util.theme_colors")
  if colors_ok then
    -- Hand the freshly-applied highlight table to the derived-colour cache
    -- as a module field (previously a `_G._tetravim_current_highlights`
    -- global) so `refresh_cache()` reads it back without touching `_G`.
    theme_colors.current_highlights = tetris.highlights()
    theme_colors.refresh_cache()
  end
end

--- Bootstrap entry point (called from `core/options.lua` on startup).
function M.load_saved_theme()
  M.apply()
end

--- Compatibility shim for `require("tetravim.theme").setup()` (used by the
--- smoke-test script and any external caller). Any `opts` are ignored.
function M.setup(_)
  M.apply()
end

return M
