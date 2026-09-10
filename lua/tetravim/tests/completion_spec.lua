-- Autocompletion / IntelliSense wiring -- shared capabilities + cmp stack

describe("tetravim.util.lsp_capabilities", function()
  local caps_mod = require("tetravim.util.lsp_capabilities")

  it("returns a fresh capabilities table each call (no shared mutation)", function()
    local a = caps_mod.make()
    local b = caps_mod.make()
    assert.is_table(a)
    assert.are_not.equal(a, b)
    a.textDocument.completion.completionItem.snippetSupport = "TAMPERED"
    assert.are_not.equal("TAMPERED", b.textDocument.completion.completionItem.snippetSupport)
  end)

  it("advertises snippet support and resolvable completion items", function()
    local caps = caps_mod.make()
    local item = caps.textDocument.completion.completionItem
    assert.is_true(item.snippetSupport == true)
    assert.is_table(item.resolveSupport)
    assert.is_true(vim.tbl_contains(item.resolveSupport.properties, "additionalTextEdits"))
  end)

  it("advertises line-only folding range support", function()
    local caps = caps_mod.make()
    assert.is_table(caps.textDocument.foldingRange)
    assert.is_true(caps.textDocument.foldingRange.lineFoldingOnly)
  end)

  it("deep-merges caller overrides without dropping the base fields", function()
    local caps = caps_mod.make({ textDocument = { colorProvider = { dynamicRegistration = false } } })
    assert.is_table(caps.textDocument.colorProvider)
    -- base completion caps still present alongside the override
    assert.is_true(caps.textDocument.completion.completionItem.snippetSupport == true)
  end)
end)

-- Behavioural cmp assertions (does cmp.get_config() actually carry our
-- sources, does lua_ls resolve with the capabilities, ...) live in
-- scripts/validate-completion.sh -- forcing require("lazy").load() inside
-- plenary's harness corrupts lazy's internal state (see dap_jvm_spec.lua).
-- Here we only assert the spec file's static shape.
describe("editor-completion.lua spec shape", function()
  local src = assert(io.open("lua/tetravim/plugins/editor-completion.lua", "r")):read("*a")

  it("declares the LSP / snippet / buffer / path source plugins", function()
    for _, dep in ipairs({
      "hrsh7th/nvim%-cmp",
      "hrsh7th/cmp%-nvim%-lsp",
      "hrsh7th/cmp%-buffer",
      "hrsh7th/cmp%-path",
      "saadparwaiz1/cmp_luasnip",
      "L3MON4D3/LuaSnip",
      "rafamadriz/friendly%-snippets",
    }) do
      assert.is_truthy(src:match(dep), "editor-completion.lua does not declare " .. dep:gsub("%%", ""))
    end
  end)

  it("wires a real cmp.setup (not the old empty stub)", function()
    assert.is_truthy(src:match("cmp%.setup%("), "no cmp.setup() call")
    assert.is_truthy(src:match("luasnip%.lsp_expand"), "no snippet expander")
    assert.is_truthy(src:match('name = "nvim_lsp"'), "nvim_lsp source not configured")
    assert.is_truthy(src:match("from_vscode"), "friendly-snippets not lazy-loaded")
    assert.is_truthy(src:match("completeopt"), "completeopt not set")
  end)

  it("loads friendly-snippets before use", function()
    assert.is_truthy(src:match("lazy_load"))
  end)
end)

describe("shared capabilities are threaded into every server", function()
  it("lsp-core.lua uses the wildcard config and the fallback path", function()
    local src = assert(io.open("lua/tetravim/plugins/lsp-core.lua", "r")):read("*a")
    assert.is_truthy(src:match("lsp_capabilities"))
    assert.is_truthy(src:match('vim%.lsp%.config%("%*"'))
    assert.is_truthy(src:match("capabilities = vim%.deepcopy%(capabilities%)"))
  end)

  it("ftplugin/java.lua injects it into the jdtls config", function()
    local src = assert(io.open("ftplugin/java.lua", "r")):read("*a")
    assert.is_truthy(src:match('capabilities = require%("tetravim%.util%.lsp_capabilities"%)%.make%(%)'))
  end)

  it("lsp-scala.lua injects it into the metals config", function()
    local src = assert(io.open("lua/tetravim/plugins/lsp-scala.lua", "r")):read("*a")
    assert.is_truthy(src:match('metals_config%.capabilities = require%("tetravim%.util%.lsp_capabilities"%)'))
  end)
end)

describe("autocompletion runtime behavior (migrated from validate-completion.sh)", function()
  it("nvim-cmp loads and is configured with an LSP source + snippet expander", function()
    local code = [[
      require('lazy').load({ plugins = { 'LuaSnip', 'nvim-cmp' } })
      local cmp = require('cmp')
      assert(pcall(require, 'cmp_nvim_lsp'), 'cmp-nvim-lsp not resolvable after load')
      assert(pcall(require, 'luasnip'), 'luasnip not resolvable after load')
      local cfg = cmp.get_config()
      assert(type(cfg.snippet) == 'table' and type(cfg.snippet.expand) == 'function', 'no snippet expander wired')
      local names = {}
      for _, s in ipairs(cfg.sources or {}) do names[s.name] = true end
      assert(names.nvim_lsp, 'nvim_lsp source missing from cmp config')
      assert(names.luasnip, 'luasnip source missing from cmp config')
      assert(names.path and names.buffer, 'path/buffer sources missing from cmp config')
      vim.cmd('qa!')
    ]]
    local out = vim.fn.system({ "nvim", "--headless", "-u", "init.lua", "-c", "lua " .. code })
    assert.are.equal(0, vim.v.shell_error, out)
  end)

  it("completeopt is menuone,noselect so nothing is auto-accepted", function()
    local code = [[
      require('lazy').load({ plugins = { 'nvim-cmp' } })
      local co = vim.opt.completeopt:get()
      assert(vim.tbl_contains(co, 'noselect'), 'completeopt missing noselect, got: ' .. vim.inspect(co))
      assert(vim.tbl_contains(co, 'menuone'), 'completeopt missing menuone, got: ' .. vim.inspect(co))
      vim.cmd('qa!')
    ]]
    local out = vim.fn.system({ "nvim", "--headless", "-u", "init.lua", "-c", "lua " .. code })
    assert.are.equal(0, vim.v.shell_error, out)
  end)

  it("a server routed through lsp-core carries the cmp capabilities", function()
    local code = [[
      require('lazy').load({ plugins = { 'nvim-cmp', 'nvim-lspconfig' } })
      local resolved = vim.lsp.config.lua_ls
      assert(type(resolved) == 'table', 'vim.lsp.config.lua_ls did not resolve')
      local item = resolved.capabilities
        and resolved.capabilities.textDocument
        and resolved.capabilities.textDocument.completion
        and resolved.capabilities.textDocument.completion.completionItem
      assert(item and item.snippetSupport == true, 'lua_ls not started with cmp completion capabilities')
      vim.cmd('qa!')
    ]]
    local out = vim.fn.system({ "nvim", "--headless", "-u", "init.lua", "-c", "lua " .. code })
    assert.are.equal(0, vim.v.shell_error, out)
  end)
end)
