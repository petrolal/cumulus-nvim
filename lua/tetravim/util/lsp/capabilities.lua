-- TetraVim shared LSP client capabilities
--
-- Single source of truth for the `capabilities` table every language server is
-- started with. Neovim 0.11 already merges `make_client_capabilities()` into
-- `vim.lsp.config`, but that base table does NOT advertise the extended
-- completion item support (snippet edits, resolve of additionalTextEdits /
-- documentation, insert-replace ranges, label details) that nvim-cmp needs to
-- give a full IntelliSense experience -- servers gate features on what the
-- client claims to understand. `cmp_nvim_lsp.default_capabilities()` fills that
-- gap; this module folds it in and degrades to the plain base table when
-- nvim-cmp is not present (headless CI, `:Lazy` not yet synced).

local M = {}

local cached

--- Build the capabilities table shared by every server.
--- Result is memoised -- capabilities never change within a session.
---@param overrides table|nil extra capability fields to deep-merge on top
---@return table
function M.make(overrides)
  if not cached then
    local caps = vim.lsp.protocol.make_client_capabilities()

    local ok, cmp_lsp = pcall(require, "cmp_nvim_lsp")
    if ok and type(cmp_lsp.default_capabilities) == "function" then
      caps = vim.tbl_deep_extend("force", caps, cmp_lsp.default_capabilities())
    else
      -- Minimum viable snippet support so `${1:...}` placeholders from a
      -- server still expand via the native handler even without cmp.
      caps.textDocument = caps.textDocument or {}
      caps.textDocument.completion = caps.textDocument.completion or {}
      caps.textDocument.completion.completionItem =
        vim.tbl_deep_extend("force", caps.textDocument.completion.completionItem or {}, {
          snippetSupport = true,
          resolveSupport = { properties = { "documentation", "detail", "additionalTextEdits" } },
        })
    end

    -- nvim-ufo / native fold range hints -- harmless for servers that ignore it.
    caps.textDocument = caps.textDocument or {}
    caps.textDocument.foldingRange = { dynamicRegistration = false, lineFoldingOnly = true }

    cached = caps
  end

  if overrides then
    return vim.tbl_deep_extend("force", vim.deepcopy(cached), overrides)
  end
  return vim.deepcopy(cached)
end

return M
