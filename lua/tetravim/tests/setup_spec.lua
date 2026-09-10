-- TetraVim Native Setup & Headless Provisioning Specs

local assert = require("luassert")

describe("tetravim.core.setup", function()
  local setup_mod

  before_each(function()
    package.loaded["tetravim.core.setup"] = nil
    setup_mod = require("tetravim.core.setup")
  end)

  it("exposes run() and setup() functions", function()
    assert.is_table(setup_mod)
    assert.is_function(setup_mod.run)
    assert.is_function(setup_mod.setup)
  end)

  it("registers the :TetraVimSetup command", function()
    setup_mod.setup()
    assert.equals(2, vim.fn.exists(":TetraVimSetup"))
  end)

  it("run() returns structured result table", function()
    local res = setup_mod.run({ silent = true, parsers = {} })
    assert.is_table(res)
    assert.is_boolean(res.ok)
    assert.is_table(res.degraded)
    assert.is_table(res.health)
  end)

  it("run() tolerates missing optional modules without unhandled error", function()
    local saved_jvm = package.loaded["tetravim.util.jvm_frameworks"]
    package.loaded["tetravim.util.jvm_frameworks"] = {
      fetch_jars = function()
        return false
      end,
    }

    local res = setup_mod.run({ silent = true, parsers = {} })
    assert.is_table(res)
    assert.is_false(res.ok)
    assert.is_true(vim.tbl_contains(res.degraded, "jvm-lsp-jars"))

    package.loaded["tetravim.util.jvm_frameworks"] = saved_jvm
  end)
end)
