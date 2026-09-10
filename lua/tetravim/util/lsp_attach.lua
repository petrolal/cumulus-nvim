-- TetraVim shared per-client LspAttach wiring (resilience / IntelliSense audit).
--
-- lsp-core.lua's single global `LspAttach` autocmd used to do nothing but
-- emit a "server attached" toast. Every client that routes through it --
-- jdtls and metals included -- now also gets, each capability-gated:
--
--   * inlay hints turned on for the buffer (with a `<leader>uh` /
--     `:TetraToggleInlayHints` toggle that also sticks for buffers opened
--     later, via `vim.g.tetravim_inlay_hints`);
--   * document highlight -- the symbol under the cursor is highlighted on
--     `CursorHold` and cleared on `CursorMoved`, i.e. an IDE's "highlight
--     usages";
--   * `<C-k>` signature help in insert and normal mode, since Neovim 0.11
--     binds hover / rename / code-action by default but not signature help.
--
-- Logic lives here (not inline in the autocmd) so it stays a one-liner in
-- lsp-core.lua and is exercised by a unit path.

local M = {}

-- Per-(buffer, client) bookkeeping. A single module-level augroup shared by
-- every client on a buffer meant the last client's closure won any capability
-- and ANY one client detaching wiped document-highlight for the whole buffer.
-- Instead: one augroup per (bufnr, client.id), and the buffer-wide teardown
-- (clear_references, `<C-k>` keymap) fires only when the last capable client
-- detaches.
--   M._dochl[bufnr] = { [client_id] = augroup_id, ... }
--   M._sig[bufnr]   = { [client_id] = true, ... }
M._dochl = {}
M._sig = {}

-- Per-filetype inlay-hint default consulted only when the user has expressed
-- no session-wide preference (vim.g.tetravim_inlay_hints is nil). Verbose
-- languages where parameter-name / inferred-type hints are noise default off.
M.INLAY_DEFAULTS = {
  java = true,
  kotlin = true,
  scala = true,
  lua = true,
  go = true,
  rust = true,
  typescript = true,
  typescriptreact = true,
  javascript = true,
  json = false,
  yaml = false,
  markdown = false,
  text = false,
}

local function supports(client, method)
  if not client then
    return false
  end
  if type(client.supports_method) == "function" then
    return client:supports_method(method)
  end
  return true
end

--- Turn inlay hints on for `bufnr` when the client provides them and the
--- user has not switched them off for the session.
---@param client vim.lsp.Client
---@param bufnr integer
function M.maybe_enable_inlay_hints(client, bufnr)
  if not (vim.lsp.inlay_hint and supports(client, "textDocument/inlayHint")) then
    return
  end
  local pref = vim.g.tetravim_inlay_hints
  if pref == false then
    return
  end
  if pref == nil then
    -- No explicit session choice -> fall back to the per-filetype default
    -- (unknown filetypes keep the historical "on" behaviour).
    local ft = vim.bo[bufnr] and vim.bo[bufnr].filetype or ""
    if M.INLAY_DEFAULTS[ft] == false then
      return
    end
  end
  pcall(vim.lsp.inlay_hint.enable, true, { bufnr = bufnr })
end

--- Flip inlay hints for every loaded buffer and remember the choice so
--- buffers that attach a client later inherit it.
function M.toggle_inlay_hints()
  if not vim.lsp.inlay_hint then
    return
  end
  local currently_on = false
  local ok, enabled = pcall(vim.lsp.inlay_hint.is_enabled, {})
  if ok then
    currently_on = enabled
  end
  local on = not currently_on
  vim.g.tetravim_inlay_hints = on
  for _, bufnr in ipairs(vim.api.nvim_list_bufs()) do
    if vim.api.nvim_buf_is_loaded(bufnr) then
      pcall(vim.lsp.inlay_hint.enable, on, { bufnr = bufnr })
    end
  end
  require("tetravim.util.ui").notify_info("Inlay hints " .. (on and "enabled" or "disabled"))
end

--- `CursorHold` -> highlight the symbol under the cursor; `CursorMoved` ->
--- clear it. Buffer-local, and de-duped so a second client attaching to the
--- same buffer does not double-register.
---@param client vim.lsp.Client
---@param bufnr integer
function M.wire_document_highlight(client, bufnr)
  if not (client and supports(client, "textDocument/documentHighlight")) then
    return
  end
  local group_name = ("tetravim_lsp_dochl_%d_%d"):format(bufnr, client.id)
  local group = vim.api.nvim_create_augroup(group_name, { clear = true })
  vim.api.nvim_create_autocmd({ "CursorHold", "CursorHoldI" }, {
    group = group,
    buffer = bufnr,
    callback = function()
      if supports(client, "textDocument/documentHighlight") then
        pcall(vim.lsp.buf.document_highlight)
      end
    end,
  })
  vim.api.nvim_create_autocmd({ "CursorMoved", "CursorMovedI" }, {
    group = group,
    buffer = bufnr,
    callback = function()
      pcall(vim.lsp.buf.clear_references)
    end,
  })
  M._dochl[bufnr] = M._dochl[bufnr] or {}
  M._dochl[bufnr][client.id] = group
end

--- `<C-k>` signature help (insert + normal), buffer-local.
---@param client vim.lsp.Client
---@param bufnr integer
function M.wire_signature_help(client, bufnr)
  if not (client and supports(client, "textDocument/signatureHelp")) then
    return
  end
  vim.keymap.set({ "i", "n" }, "<C-k>", function()
    vim.lsp.buf.signature_help()
  end, { buffer = bufnr, desc = "Signature Help" })
  M._sig[bufnr] = M._sig[bufnr] or {}
  M._sig[bufnr][client.id] = true
end

--- Drop the document-highlight autocmds, the `<C-k>` keymap and any lingering
--- reference marks a client wired on attach. With `client_id` only that
--- client's slice is removed; the buffer-wide teardown (clear_references,
--- keymap delete) fires when the last tracked client on the buffer is gone.
--- Called with no `client_id` (e.g. BufWipeout) it tears everything down.
---@param bufnr integer
---@param client_id integer|nil
function M.on_detach(bufnr, client_id)
  if client_id then
    local dh = M._dochl[bufnr]
    if dh and dh[client_id] then
      pcall(vim.api.nvim_clear_autocmds, { group = dh[client_id] })
      dh[client_id] = nil
      if next(dh) == nil then
        M._dochl[bufnr] = nil
      end
    end
    if M._sig[bufnr] then
      M._sig[bufnr][client_id] = nil
      if next(M._sig[bufnr]) == nil then
        M._sig[bufnr] = nil
      end
    end
  else
    local dh = M._dochl[bufnr]
    if dh then
      for _, group in pairs(dh) do
        pcall(vim.api.nvim_clear_autocmds, { group = group })
      end
      M._dochl[bufnr] = nil
    end
    M._sig[bufnr] = nil
  end

  -- Nothing tracked for this buffer any more -> remove the shared bits.
  if not M._dochl[bufnr] and not M._sig[bufnr] then
    if vim.api.nvim_buf_is_valid(bufnr) then
      pcall(vim.keymap.del, { "i", "n" }, "<C-k>", { buffer = bufnr })
    end
    pcall(vim.lsp.buf.clear_references)
  end
end

--- Entry point called once per client from lsp-core.lua's global `LspAttach`.
---@param client vim.lsp.Client
---@param bufnr integer
function M.on_attach(client, bufnr)
  if not (client and vim.api.nvim_buf_is_valid(bufnr)) then
    return
  end
  M.maybe_enable_inlay_hints(client, bufnr)
  M.wire_document_highlight(client, bufnr)
  M.wire_signature_help(client, bufnr)
end

return M
