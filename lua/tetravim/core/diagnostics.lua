-- TetraVim Unified Diagnostics Presentation
--
-- One place that decides how every LSP / linter / DevOps diagnostic looks,
-- so the distro reads consistently instead of inheriting Neovim's plain
-- defaults:
--   * gutter signs use Nerd Font glyphs, coloured by the existing
--     DiagnosticSign* highlights (Z-piece red for errors, etc.);
--   * the sign's severity colour bleeds onto the line-number column;
--   * inline virtual text is prefixed with a slim bar and only shows its
--     source when more than one is reporting on the line;
--   * the hover float (`<leader>cd` / `vim.diagnostic.open_float`) gets a
--     rounded border to match `winborder`;
--   * `[d` / `]d` jumps pop that same float on arrival;
--   * signs stack most-severe-first.
--
-- Returns a module so editor-snacks.lua can bind `<leader>uv` to
-- `toggle_virtual_lines()` -- swap the terse one-line virtual text for
-- `vim.diagnostic`'s multi-line `virtual_lines` rendering on the current
-- line, which is far easier to read for long type-mismatch messages.

local M = {}

local severity = vim.diagnostic.severity

local icons = {
  [severity.ERROR] = "󰅚 ",
  [severity.WARN] = "󰀪 ",
  [severity.INFO] = "󰋽 ",
  [severity.HINT] = "󰌶 ",
}

local sign_hl = {
  [severity.ERROR] = "DiagnosticSignError",
  [severity.WARN] = "DiagnosticSignWarn",
  [severity.INFO] = "DiagnosticSignInfo",
  [severity.HINT] = "DiagnosticSignHint",
}

-- The terse single-line virtual text, restored whenever virtual_lines is
-- toggled back off.
local virtual_text_spec = {
  spacing = 4,
  source = "if_many",
  prefix = "▎",
}

vim.diagnostic.config({
  severity_sort = true,
  update_in_insert = false,
  underline = true,
  signs = {
    text = icons,
    numhl = sign_hl,
  },
  virtual_text = virtual_text_spec,
  float = {
    border = "rounded",
    source = "if_many",
    header = "",
    prefix = "",
  },
  -- `[d` / `]d` / `vim.diagnostic.jump` open the float on landing, so a jump
  -- shows the full message without a second keystroke.
  jump = {
    float = true,
  },
})

--- Multi-line `virtual_lines` for the current line vs. the default terse
--- one-line `virtual_text`. Off by default (virtual_lines is verbose); bound
--- to `<leader>uv` via editor-snacks.lua.
M.virtual_lines_enabled = false

function M.toggle_virtual_lines()
  M.virtual_lines_enabled = not M.virtual_lines_enabled
  vim.diagnostic.config({
    virtual_text = M.virtual_lines_enabled and false or virtual_text_spec,
    virtual_lines = M.virtual_lines_enabled and { current_line = true } or false,
  })
end

return M
