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

local highlight_group = vim.api.nvim_create_augroup("tetravim_lsp_document_highlight", { clear = true })

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
  if vim.g.tetravim_inlay_hints == false then
    return
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
  if not supports(client, "textDocument/documentHighlight") then
    pcall(vim.api.nvim_clear_autocmds, { group = highlight_group, buffer = bufnr })
    return
  end
  pcall(vim.api.nvim_clear_autocmds, { group = highlight_group, buffer = bufnr })
  vim.api.nvim_create_autocmd({ "CursorHold", "CursorHoldI" }, {
    group = highlight_group,
    buffer = bufnr,
    callback = function()
      if supports(client, "textDocument/documentHighlight") then
        pcall(vim.lsp.buf.document_highlight)
      end
    end,
  })
  vim.api.nvim_create_autocmd({ "CursorMoved", "CursorMovedI" }, {
    group = highlight_group,
    buffer = bufnr,
    callback = function()
      pcall(vim.lsp.buf.clear_references)
    end,
  })
end

--- `<C-k>` signature help (insert + normal), buffer-local.
---@param client vim.lsp.Client
---@param bufnr integer
function M.wire_signature_help(client, bufnr)
  if not supports(client, "textDocument/signatureHelp") then
    return
  end
  vim.keymap.set({ "i", "n" }, "<C-k>", function()
    vim.lsp.buf.signature_help()
  end, { buffer = bufnr, desc = "Signature Help" })
end

--- Drop the document-highlight autocmds and any lingering reference marks
--- when a client detaches, so a stale server does not keep firing on
--- `CursorHold`.
---@param bufnr integer
function M.on_detach(bufnr)
  pcall(vim.api.nvim_clear_autocmds, { group = highlight_group, buffer = bufnr })
  pcall(vim.lsp.buf.clear_references)
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
