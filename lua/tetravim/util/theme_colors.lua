-- Theme Colour Cache & Initialisation
--
-- Derives the handful of UI accent colours that lualine / bufferline need
-- from the currently-applied highlight groups, so those plugins don't
-- duplicate palette data. Colours come from the canonical TetraVim
-- "Tetris" highlight map (`tetravim.theme.tetris`); `M.DEFAULT_COLORS`
-- mirrors that palette as a literal fallback if the module fails to load.
--
-- lualine mode badges and the bufferline indicator are *chrome*, so they
-- take the vivid `*_pure` tetromino hexes from the palette rather than the
-- desaturated on-background text tints used inside the buffer.

local M = {}

-- ============================================================================
-- Fallback Colors
-- ============================================================================

-- Mirrors the canonical TetraVim "Tetris" palette
-- (see lua/tetravim/theme/tetris.lua). Kept as literals so UI plugins have
-- correct colours even if that module fails to load.
M.DEFAULT_COLORS = {
  bg = "#111216", -- Background
  fg = "#BCBEC4", -- Foreground
  fg_dim = "#6B7688", -- Comment gray (inactive statusline text)
  bg_cursorline = "#1E1F26", -- Surface
  statusline_bg = "#1E1F26", -- Surface
  primary_color = "#00F0F0", -- I-piece cyan — default accent (CursorLineNr)
  secondary = "#00F000", -- S-piece green — insert-mode statusline accent
  purple = "#A000F0", -- T-piece — visual-mode badge
  cyan = "#00F0F0", -- I-piece
  yellow = "#F0F000", -- O-piece
  green = "#00F000", -- S-piece
  orange = "#FF7F00", -- L-piece
  blue = "#5B8CFF", -- J-piece (badge-readable tint)
  error = "#F00000", -- Z-piece — replace-mode badge
}

-- Cache stores the current theme colors
M.cache = vim.deepcopy(M.DEFAULT_COLORS)

-- The highlight table of the currently-applied theme. Set by
-- `tetravim.theme.apply()` right after it applies the palette, and read by
-- `init_theme_colors()` below. `nil` until the first theme apply -- in which
-- case we fall back to the canonical Tetris highlight map.
M.current_highlights = nil

-- ============================================================================
-- Color Initialization & Refresh
-- ============================================================================

--- Recompute the cached UI colours from the active highlight groups.
--- Structural colours are scraped from the applied highlights; the vivid
--- accent hexes come straight from `tetris.palette` (`*_pure` keys).
--- Falls back to the Tetris highlight map, then to `M.DEFAULT_COLORS`.
---@return nil
function M.init_theme_colors()
  local highlights = M.current_highlights or {}

  local palette
  local ok, tetris = pcall(require, "tetravim.theme.tetris")
  if ok then
    palette = tetris.palette
    if vim.tbl_isempty(highlights) then
      -- Fall back to the canonical Tetris highlight map before giving up.
      highlights = tetris.highlights()
    end
  end

  if vim.tbl_isempty(highlights) then
    M.cache = vim.deepcopy(M.DEFAULT_COLORS)
  end

  palette = palette or {}
  local d = M.DEFAULT_COLORS

  -- Structural colours — read from the live highlight groups.
  M.cache.bg = (highlights.Normal and highlights.Normal.bg) or d.bg
  M.cache.fg = (highlights.Normal and highlights.Normal.fg) or d.fg
  M.cache.fg_dim = (highlights.Comment and highlights.Comment.fg) or d.fg_dim
  M.cache.bg_cursorline = (highlights.CursorLine and highlights.CursorLine.bg) or d.bg_cursorline
  M.cache.statusline_bg = (highlights.StatusLine and highlights.StatusLine.bg) or d.statusline_bg

  -- Accent colours — vivid `*_pure` tetromino hexes for lualine / bufferline
  -- chrome. `CursorLineNr` already uses `cyan_pure`, so scraping it is safe;
  -- the rest come directly from the palette so badges never desaturate.
  local cursor_line_nr_fg = highlights.CursorLineNr and highlights.CursorLineNr.fg
  M.cache.primary_color = cursor_line_nr_fg or palette.cyan_pure or d.primary_color
  M.cache.secondary = palette.green_pure or d.secondary
  M.cache.purple = palette.purple_pure or d.purple
  M.cache.error = palette.red_pure or d.error
  M.cache.cyan = palette.cyan_pure or d.cyan
  M.cache.yellow = palette.yellow_pure or d.yellow
  M.cache.green = palette.green_pure or d.green
  M.cache.orange = palette.orange_pure or d.orange
  M.cache.blue = palette.blue or d.blue
end

--- Refresh the cached UI colours from the active highlights.
---@param _ any Ignored; retained for call-site compatibility.
---@return nil
function M.refresh_cache(_)
  M.init_theme_colors()
end

return M
