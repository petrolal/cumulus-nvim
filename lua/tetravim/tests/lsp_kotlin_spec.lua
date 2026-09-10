-- lua/tetravim/tests/lsp_kotlin_spec.lua
--
-- Guards the JetBrains kotlin-lsp (intellij-server) concurrent-workspace-index
-- fix: a second intellij-server sharing one RocksDB index fails every request
-- ("While lock file: .../kotlin-server/rocks/vNNN/LOCK: Resource temporarily
-- unavailable") and nvim surfaces it as an uncaught vim.schedule assert.
--
-- Also guards that the guard's precondition check (a synchronous `pgrep`) does
-- NOT run at module-load time -- it sat on the eager startup path the CI
-- startup-time budget watches -- but is deferred into the server's root_dir.

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

  it("kotlin_lsp.root_dir is a function (deferred concurrent-index guard lives here)", function()
    assert.is_function(servers.kotlin_lsp.root_dir)
  end)

  it("the fallback kotlin_language_server keeps its plain-table on_attach", function()
    -- extract_spec.lua reaches through this exact path.
    assert.is_function(servers.kotlin_language_server.on_attach)
  end)

  it("source gates on a live intellij-server and honours the force escape hatch", function()
    local body = read("lua/tetravim/plugins/lsp-kotlin.lua")
    assert.is_truthy(body:match("TETRAVIM_KOTLIN_LSP_FORCE"))
    assert.is_truthy(body:match("pgrep"))
    -- on_exit must not blindly restart into a locked index.
    assert.is_truthy(body:match("foreign_kotlin_lsp"))
    assert.is_truthy(body:match('resilience%.reset%("kotlin_lsp"%)'))
  end)

  it("the pgrep precondition is NOT evaluated at module load (stays off the startup path)", function()
    local body = read("lua/tetravim/plugins/lsp-kotlin.lua")
    -- The old form: `local kotlin_lsp_suppressed = has_kotlin_lsp and foreign_kotlin_lsp()`
    -- at file scope. It must be gone -- the check now lives inside a function.
    assert.is_nil(body:match("kotlin_lsp_suppressed"))
    assert.is_truthy(body:match("function kotlin_lsp_root"), "expected the deferred root resolver kotlin_lsp_root()")
  end)

  it("with TETRAVIM_KOTLIN_LSP_FORCE=1 the root resolver bypasses the guard and runs resolve_root", function()
    -- plenary's busted shim has no finally(); restore the env by hand.
    local prev = vim.env.TETRAVIM_KOTLIN_LSP_FORCE
    vim.env.TETRAVIM_KOTLIN_LSP_FORCE = "1"
    local got
    local ok, err = pcall(function()
      servers.kotlin_lsp.root_dir(vim.api.nvim_get_current_buf(), function(dir)
        got = dir or "<nil-but-called>"
      end)
    end)
    vim.env.TETRAVIM_KOTLIN_LSP_FORCE = prev

    -- Either on_dir fired (lspconfig present) or resolve_root's own
    -- `require("lspconfig.util")` blew up (lspconfig not loaded in this bare
    -- test env). Both prove the FORCE hatch skipped the early `return` in the
    -- guard -- the failure mode we care about is a *silent* nil return.
    if not ok then
      assert.is_truthy(
        tostring(err):match("lspconfig"),
        "root_dir raised something other than the lspconfig require: " .. tostring(err)
      )
    else
      assert.is_truthy(got, "on_dir was never called -- force hatch did not bypass the guard")
    end
  end)
end)
