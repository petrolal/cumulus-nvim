-- TetraVim interactive panel helper
--
-- A refreshable, keymapped list/tree panel rendered in the shared persistent
-- split (tetravim.util.split) -- the substrate for the IDEA-style "tool window"
-- panels: the Endpoints view, the Kubernetes cluster explorer and the Docker /
-- Compose dashboard.
--
-- The caller hands `render` a static header, a flat list of body rows (each an
-- optional opaque `item`) and a table of single-key actions. This module owns
-- buffer creation, the line->item map, the `q` / `<CR>` / `r` conventions and
-- makes the buffer non-modifiable so a stray keystroke can't corrupt the view.

local split = require("tetravim.util.split")

local M = {}

--- Render (or re-render, in place) an interactive panel.
---@param opts {
---  name_hint: string,
---  filetype?: string,
---  direction?: string,
---  header?: string[],
---  rows: { text: string, item?: any }[],
---  on_select?: fun(item: any|nil, ctx: { bufnr: integer, refresh: fun() }),
---  refresh?: fun(),
---  keymaps?: table<string, fun(item: any|nil, ctx: { bufnr: integer, refresh: fun() })>,
--- }
---@return integer bufnr
function M.render(opts)
  local header = opts.header or {}
  local lines = {}
  vim.list_extend(lines, header)

  local line_to_item = {}
  local base = #lines
  for i, row in ipairs(opts.rows) do
    lines[#lines + 1] = row.text
    line_to_item[base + i] = row.item
  end

  local bufnr = split.open(table.concat(lines, "\n"), {
    filetype = opts.filetype or "tetravim-panel",
    name_hint = opts.name_hint,
    direction = opts.direction,
  })
  vim.bo[bufnr].modifiable = false

  local ctx = {
    bufnr = bufnr,
    refresh = function()
      if opts.refresh then
        opts.refresh()
      end
    end,
  }

  local function item_under_cursor()
    local lnum = vim.api.nvim_win_get_cursor(0)[1]
    return line_to_item[lnum]
  end

  local function bind(lhs, fn)
    vim.keymap.set("n", lhs, function()
      fn(item_under_cursor(), ctx)
    end, { buffer = bufnr, silent = true, nowait = true })
  end

  bind("q", function()
    -- `close`, not `quit`: never take down the last window.
    pcall(vim.cmd, "close")
  end)
  if opts.refresh then
    bind("r", function()
      ctx.refresh()
    end)
  end
  if opts.on_select then
    bind("<CR>", opts.on_select)
  end
  for lhs, fn in pairs(opts.keymaps or {}) do
    bind(lhs, fn)
  end

  return bufnr
end

return M
