-- lua/tetravim/tests/lsp_kotlin_spec.lua
--
-- Guards the JetBrains kotlin-lsp (intellij-server) concurrent-workspace-index
-- fix: a second intellij-server sharing one RocksDB index fails every request
-- ("While lock file: .../kotlin-server/rocks/vNNN/LOCK: Resource temporarily
-- unavailable") and nvim surfaces it as an uncaught vim.schedule assert.

local function read(path)
  local fh = assert(io.open(path, "r"))
  local body = fh:read("*a")
  fh:close()
  return body
end

describe("lsp-kotlin.lua concurrent-index guard", function()
  local spec = require("tetravim.plugins.lsp-kotlin")
  local servers = spec[2].opts.servers

  it("kotlin_lsp carries a bespoke on_exit (opts out of the generic restart)", function()
    assert.is_function(servers.kotlin_lsp.on_exit)
  end)

  it("kotlin_lsp.enabled is a resolved boolean, not left nil", function()
    assert.are.equal("boolean", type(servers.kotlin_lsp.enabled))
  end)

  it("the fallback kotlin_language_server keeps its plain-table on_attach", function()
    -- extract_spec.lua reaches through this exact path.
    assert.is_function(servers.kotlin_language_server.on_attach)
  end)

  it("source gates on a live intellij-server and honours the force escape hatch", function()
    local body = read("lua/tetravim/plugins/lsp-kotlin.lua")
    assert.is_truthy(body:match("TETRAVIM_KOTLIN_LSP_FORCE"))
    assert.is_truthy(body:match("pgrep"))
    assert.is_truthy(body:match("kotlin_lsp_suppressed"))
    -- on_exit must not blindly restart into a locked index.
    assert.is_truthy(body:match("foreign_kotlin_lsp"))
    assert.is_truthy(body:match('resilience%.reset%("kotlin_lsp"%)'))
  end)
end)
