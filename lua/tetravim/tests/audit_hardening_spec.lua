-- lua/tetravim/tests/audit_hardening_spec.lua
--
-- Covers the Neovim-community best-practices / memory-leak audit fixes that
-- don't have a natural home in an existing spec:
--   * jdtls_config session cache (ftplugin memoization)
--   * theme_colors.current_highlights module field (was a _G global)
--   * core/autocmds.lua: bounded typeahead drain + async archive reader
--   * CI startup-time budget
--   * new IDE-parity plugin specs (fidget / trouble / neogit)

local function read(path)
  local fh = assert(io.open(path, "r"))
  local body = fh:read("*a")
  fh:close()
  return body
end

describe("jdtls_config session cache", function()
  local cache = require("tetravim.util.jdtls_config")

  after_each(function()
    cache.reset()
  end)

  it("starts empty and round-trips a value", function()
    cache.reset()
    assert.is_nil(cache.get())
    local payload = { bundles = { "a.jar" }, opts = { settings = {} } }
    cache.set(payload)
    assert.are.equal(payload, cache.get())
  end)

  it("reset() forces the next ftplugin load to recompute", function()
    cache.set({ bundles = {}, opts = {} })
    cache.reset()
    assert.is_nil(cache.get())
  end)

  it("ftplugin/java.lua consults the cache before globbing bundles", function()
    local body = read("ftplugin/java.lua")
    assert.is_truthy(body:match("tetravim%.util%.jdtls_config"))
    assert.is_truthy(body:match("if not static then"))
    -- Framework-extension tokens must still be present for jvm_frameworks_spec.
    for _, tok in ipairs({ "java_extensions", "spring_boot", "microprofile", "quarkus" }) do
      assert.is_truthy(body:match(tok), "ftplugin lost token " .. tok)
    end
  end)
end)

describe("theme_colors.current_highlights", function()
  before_each(function()
    package.loaded["tetravim.util.theme_colors"] = nil
    package.loaded["tetravim.theme"] = nil
  end)

  it("is a module field, not a _G global", function()
    local tc = require("tetravim.util.theme_colors")
    assert.is_true(tc.current_highlights == nil or type(tc.current_highlights) == "table")
    assert.is_nil(_G._tetravim_current_highlights)
    -- No live read or write of the retired global (a back-reference in a
    -- comment is fine, so only flag it as an lvalue or an `or`-fallback rhs).
    assert.is_falsy(read("lua/tetravim/util/theme_colors.lua"):match("_G%._tetravim_current_highlights%s*[=o]"))
    assert.is_falsy(read("lua/tetravim/theme/init.lua"):match("_G%._tetravim_current_highlights%s*[=o]"))
  end)

  it("theme.apply() populates the field and refreshes the derived cache", function()
    local theme = require("tetravim.theme")
    local tc = require("tetravim.util.theme_colors")
    theme.apply()
    assert.are.equal("table", type(tc.current_highlights))
    assert.is_truthy(tc.current_highlights.Normal)
    assert.are.equal("table", type(tc.cache))
    assert.is_truthy(tc.cache.bg)
  end)
end)

describe("core/autocmds.lua hardening", function()
  local body = read("lua/tetravim/core/autocmds.lua")

  it("loads without error", function()
    assert.is_truthy(pcall(require, "tetravim.core.autocmds"))
  end)

  it("bounds the startup typeahead drain instead of an unbounded while", function()
    assert.is_truthy(body:match("for _ = 1, 256 do"))
    assert.is_falsy(body:match("while vim%.fn%.getchar%(1%)"))
  end)

  it("reads archive entries asynchronously via vim.system, not systemlist", function()
    assert.is_falsy(body:match("vim%.fn%.systemlist"))
    assert.is_truthy(body:match("vim%.system%("))
    assert.is_truthy(body:match("nvim_buf_is_valid"))
  end)

  it("debounces the CodeLens refresh with a per-buffer timer", function()
    assert.is_truthy(body:match("codelens_timers"))
    assert.is_truthy(body:match("vim%.uv%.new_timer"))
  end)
end)

describe("CI startup-time budget", function()
  it("the smoke job measures --startuptime and enforces a ceiling", function()
    local ci = read(".github/workflows/ci.yml")
    assert.is_truthy(ci:match("%-%-startuptime"))
    assert.is_truthy(ci:match("BUDGET_MS"))
  end)
end)

describe("IDE-parity plugin specs", function()
  local function spec_for(file, plugin)
    local chunk = assert(loadfile(file))
    local ok, result = pcall(chunk)
    assert.is_true(ok, file .. " raised on load")
    -- These files return a list of lazy.nvim specs.
    for _, s in ipairs(result) do
      if s[1] == plugin then
        return s
      end
    end
    error(plugin .. " not found in " .. file)
  end

  it("fidget.nvim is lazy-loaded on LspAttach", function()
    local s = spec_for("lua/tetravim/plugins/ui-lsp-progress.lua", "j-hui/fidget.nvim")
    assert.are.equal("LspAttach", s.event)
  end)

  it("trouble.nvim binds the Problems panel under <leader>x", function()
    local s = spec_for("lua/tetravim/plugins/tools-trouble.lua", "folke/trouble.nvim")
    local lhs = {}
    for _, k in ipairs(s.keys) do
      lhs[k[1]] = true
    end
    assert.is_true(lhs["<leader>xx"])
    assert.is_true(lhs["<leader>xX"])
  end)

  it("neogit avoids the LazyGit <leader>gg / Snacks <leader>gl bindings", function()
    local s = spec_for("lua/tetravim/plugins/tools-neogit.lua", "NeogitOrg/neogit")
    local lhs = {}
    for _, k in ipairs(s.keys) do
      lhs[k[1]] = true
    end
    assert.is_true(lhs["<leader>gn"])
    assert.is_nil(lhs["<leader>gg"])
    assert.is_nil(lhs["<leader>gl"])
  end)
end)

describe("new <leader>c hierarchy / generate keymaps", function()
  local body = read("lua/tetravim/core/keymaps.lua")

  it("nests call/type hierarchy under <leader>ch (keeps <leader>ci free for Inline)", function()
    assert.is_truthy(body:match('"<leader>chi"'))
    assert.is_truthy(body:match('"<leader>cho"'))
    assert.is_truthy(body:match('"<leader>chs"'))
    assert.is_truthy(body:match('"<leader>chS"'))
    assert.is_falsy(body:match('map%("n", "<leader>ci",'))
  end)

  it("surfaces Generate / change-signature / safe-delete code actions", function()
    assert.is_truthy(body:match('"<leader>cn".-source%.generate'))
    assert.is_truthy(body:match('"<leader>ck"'))
    assert.is_truthy(body:match('"<leader>cy"'))
  end)
end)
