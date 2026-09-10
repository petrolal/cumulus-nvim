-- lua/tetravim/tests/lsp_attach_spec.lua
--
-- Neovim-community best-practices audit -- §2.1 (multi-client document-highlight
-- teardown) and §4 (per-filetype inlay-hint defaults). Exercises the pure
-- bookkeeping in tetravim.util.lsp_attach without a live language server.

local lsp_attach = require("tetravim.util.lsp_attach")

local function fake_client(id)
  return {
    id = id,
    name = "fake-" .. id,
    supports_method = function()
      return true
    end,
  }
end

describe("lsp_attach per-client document-highlight teardown", function()
  local bufnr

  before_each(function()
    lsp_attach._dochl = {}
    lsp_attach._sig = {}
    bufnr = vim.api.nvim_create_buf(false, true)
  end)

  after_each(function()
    if vim.api.nvim_buf_is_valid(bufnr) then
      vim.api.nvim_buf_delete(bufnr, { force = true })
    end
  end)

  it("registers one augroup per (buffer, client) pair", function()
    lsp_attach.wire_document_highlight(fake_client(1), bufnr)
    lsp_attach.wire_document_highlight(fake_client(2), bufnr)

    assert.are.equal("table", type(lsp_attach._dochl[bufnr]))
    assert.is_truthy(lsp_attach._dochl[bufnr][1])
    assert.is_truthy(lsp_attach._dochl[bufnr][2])
    assert.are_not.equal(lsp_attach._dochl[bufnr][1], lsp_attach._dochl[bufnr][2])
  end)

  it("detaching one client leaves the other client's highlight wiring intact", function()
    lsp_attach.wire_document_highlight(fake_client(1), bufnr)
    lsp_attach.wire_document_highlight(fake_client(2), bufnr)
    lsp_attach.wire_signature_help(fake_client(1), bufnr)
    lsp_attach.wire_signature_help(fake_client(2), bufnr)

    lsp_attach.on_detach(bufnr, 1)

    assert.is_nil(lsp_attach._dochl[bufnr][1])
    assert.is_truthy(lsp_attach._dochl[bufnr][2], "client 2 highlight group was wiped by client 1 detach")
    assert.is_nil(lsp_attach._sig[bufnr][1])
    assert.is_truthy(lsp_attach._sig[bufnr][2])
  end)

  it("the last client detaching clears the buffer's bookkeeping entirely", function()
    lsp_attach.wire_document_highlight(fake_client(1), bufnr)
    lsp_attach.wire_signature_help(fake_client(1), bufnr)

    lsp_attach.on_detach(bufnr, 1)

    assert.is_nil(lsp_attach._dochl[bufnr])
    assert.is_nil(lsp_attach._sig[bufnr])
  end)

  it("on_detach with no client_id tears the whole buffer down", function()
    lsp_attach.wire_document_highlight(fake_client(1), bufnr)
    lsp_attach.wire_document_highlight(fake_client(2), bufnr)

    lsp_attach.on_detach(bufnr)

    assert.is_nil(lsp_attach._dochl[bufnr])
    assert.is_nil(lsp_attach._sig[bufnr])
  end)
end)

describe("lsp_attach per-filetype inlay-hint defaults", function()
  it("verbose config filetypes default off, code filetypes default on", function()
    assert.are.equal(false, lsp_attach.INLAY_DEFAULTS.yaml)
    assert.are.equal(false, lsp_attach.INLAY_DEFAULTS.json)
    assert.are.equal(false, lsp_attach.INLAY_DEFAULTS.markdown)
    assert.are.equal(true, lsp_attach.INLAY_DEFAULTS.java)
    assert.are.equal(true, lsp_attach.INLAY_DEFAULTS.kotlin)
    assert.are.equal(true, lsp_attach.INLAY_DEFAULTS.scala)
  end)

  it("maybe_enable_inlay_hints skips an INLAY_DEFAULTS=false filetype when no session pref", function()
    local saved_pref = vim.g.tetravim_inlay_hints
    local saved_inlay = vim.lsp.inlay_hint
    vim.g.tetravim_inlay_hints = nil

    local calls = {}
    vim.lsp.inlay_hint = {
      enable = function(_on, opts)
        table.insert(calls, opts)
      end,
    }

    local buf_yaml = vim.api.nvim_create_buf(false, true)
    vim.bo[buf_yaml].filetype = "yaml"
    lsp_attach.maybe_enable_inlay_hints(fake_client(1), buf_yaml)
    assert.are.equal(0, #calls)

    local buf_java = vim.api.nvim_create_buf(false, true)
    vim.bo[buf_java].filetype = "java"
    lsp_attach.maybe_enable_inlay_hints(fake_client(1), buf_java)
    assert.are.equal(1, #calls)

    vim.g.tetravim_inlay_hints = saved_pref
    vim.lsp.inlay_hint = saved_inlay
    vim.api.nvim_buf_delete(buf_yaml, { force = true })
    vim.api.nvim_buf_delete(buf_java, { force = true })
  end)
end)
