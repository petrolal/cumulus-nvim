local assert = require("luassert")

local function read(path)
  local fd = assert(io.open(path, "r"))
  local body = fd:read("*a")
  fd:close()
  return body
end

describe("template engines (FreeMarker / Velocity / JSP)", function()
  it("detects the template filetypes by extension", function()
    require("tetravim.plugins.lang-templates")
    assert.are.equal("freemarker", vim.filetype.match({ filename = "page.ftl" }))
    assert.are.equal("freemarker", vim.filetype.match({ filename = "page.ftlh" }))
    assert.are.equal("freemarker", vim.filetype.match({ filename = "page.ftlx" }))
    assert.are.equal("velocity", vim.filetype.match({ filename = "mail.vm" }))
    assert.are.equal("jsp", vim.filetype.match({ filename = "index.jsp" }))
    assert.are.equal("jsp", vim.filetype.match({ filename = "fragment.jspf" }))
  end)

  it("ships hand-rolled syntax files for FreeMarker and Velocity", function()
    assert.is_true(#vim.api.nvim_get_runtime_file("syntax/freemarker.vim", false) > 0)
    assert.is_true(#vim.api.nvim_get_runtime_file("syntax/velocity.vim", false) > 0)
  end)

  it("provides ftplugin editor conventions with directive-aware comment strings", function()
    for ft, cs in pairs({
      freemarker = "<#-- %s -->",
      velocity = "## %s",
      jsp = "<%-- %s --%>",
    }) do
      local files = vim.api.nvim_get_runtime_file("ftplugin/" .. ft .. ".lua", false)
      assert.is_true(#files > 0, "missing ftplugin/" .. ft .. ".lua")
      local body = read(files[1])
      assert.is_truthy(body:find(cs, 1, true), ft .. " ftplugin should set commentstring " .. cs)
      assert.is_truthy(body:find("match_words", 1, true), ft .. " ftplugin should set matchit pairs")
      assert.is_truthy(body:find("soft_tabs", 1, true), ft .. " ftplugin should use the shared 2-space indent helper")
    end
  end)

  it("registers the template filetypes with emmet", function()
    local body = read(vim.fn.getcwd() .. "/lua/tetravim/plugins/lsp-web-tooling.lua")
    for _, ft in ipairs({ "freemarker", "velocity", "jsp" }) do
      assert.is_truthy(body:find('"' .. ft .. '"', 1, true), "emmet filetypes should include " .. ft)
    end
  end)

  it("has a checkhealth section for the template engines", function()
    local body = require("tetravim.tests.helpers").health_source()
    assert.is_truthy(body:find("TetraVim Template Engines (FreeMarker / Velocity / JSP)", 1, true))
  end)
end)
