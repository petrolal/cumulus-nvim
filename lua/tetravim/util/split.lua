-- TetraVim shared persistent-split renderer
--
-- Helper output (HTTP/gRPC responses, jq-filtered JSON, lint/sonar/CVE
-- reports, generated templates) always renders in a persistent, reused
-- bottom split -- never a floating window -- per the distribution's UX
-- convention (see CLAUDE.md "Conventions").
--
-- This module is the single source of truth for that behavior. It replaces
-- four near-identical private copies that had drifted apart:
--   * core/keymaps.lua  `tetravim_http_open_in_split`
--   * util/cve.lua       `open_in_split`
--   * util/sonar.lua     `open_report_split`
--   * util/lint.lua      `open_in_split`

local M = {}

--- Open `text` in a reused, unlisted scratch split.
---
--- A window whose buffer name starts with "<name_hint>-" from a previous
--- call is reused in place; otherwise a fresh split is created. The buffer
--- is always a throwaway scratch buffer (buftype=nofile + bufhidden=wipe +
--- noswapfile) so a stray `:w` can never dump helper output into the repo.
---
---@param text string Full buffer contents; split on "\n".
---@param opts? { filetype?: string, name_hint?: string, direction?: string }
---   filetype  -- buffer 'filetype' (default: none)
---   name_hint -- basename prefix used to find/name the reused buffer
---                (default: "tetravim-output")
---   direction -- split command (default: "botright vsplit"); pass
---                "botright split" for a horizontal report pane.
---@return integer bufnr The scratch buffer that now holds `text`.
function M.open(text, opts)
  opts = opts or {}
  local name_hint = opts.name_hint or "tetravim-output"
  local direction = opts.direction or "botright vsplit"

  -- Reuse a result window from a previous invocation -- its buffer name
  -- starts with "<name_hint>-" -- instead of stacking a fresh split on
  -- every call.
  local target_win
  for _, win in ipairs(vim.api.nvim_tabpage_list_wins(0)) do
    local buf = vim.api.nvim_win_get_buf(win)
    local ok_name, bufname = pcall(vim.api.nvim_buf_get_name, buf)
    if ok_name and vim.fs.basename(bufname):match("^" .. vim.pesc(name_hint) .. "%-") then
      target_win = win
      break
    end
  end

  if target_win and vim.api.nvim_win_is_valid(target_win) then
    vim.api.nvim_set_current_win(target_win)
  else
    vim.cmd(direction)
  end

  local bufnr = vim.api.nvim_create_buf(false, true)
  vim.api.nvim_win_set_buf(0, bufnr)
  vim.api.nvim_buf_set_lines(bufnr, 0, -1, false, vim.split(text, "\n", { plain = true }))
  vim.bo[bufnr].buftype = "nofile"
  vim.bo[bufnr].bufhidden = "wipe"
  vim.bo[bufnr].swapfile = false
  if opts.filetype then
    vim.bo[bufnr].filetype = opts.filetype
  end
  vim.bo[bufnr].modified = false
  pcall(vim.api.nvim_buf_set_name, bufnr, name_hint .. "-" .. tostring(bufnr))
  return bufnr
end

return M
