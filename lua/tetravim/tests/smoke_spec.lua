local assert = require("luassert")

describe("Startup smoke (bootstrap syntax)", function()
  it("verifies shell scripts syntax", function()
    local root = vim.fn.fnamemodify(debug.getinfo(1, "S").source:sub(2), ":p:h:h:h:h")
    local scripts = { "bootstrap.sh" }
    for _, script in ipairs(scripts) do
      local path = root .. "/" .. script
      vim.fn.system({ "bash", "-n", path })
      assert.equals(0, vim.v.shell_error, "Syntax check failed for " .. script)
    end
  end)
end)

describe("Startup smoke (validate.sh stage 1.1)", function()
  it("verifies bootstrap dependency coverage", function()
    local root = vim.fn.fnamemodify(debug.getinfo(1, "S").source:sub(2), ":p:h:h:h:h")

    local bootstrap_path = root .. "/bootstrap.sh"
    local f = io.open(bootstrap_path, "r")
    assert.is_truthy(f, "Could not open bootstrap.sh")
    local src = f:read("*a")
    f:close()

    assert.is_truthy(src:find("async-profiler", 1, true), "bootstrap.sh does not provision async-profiler")
    assert.is_truthy(src:match("ripgrep") or src:match("[^a%-z]rg[^a%-z]"), "bootstrap.sh does not provision ripgrep")

    local health_path = root .. "/lua/tetravim/health.lua"
    local f2 = io.open(health_path, "r")
    assert.is_truthy(f2, "Could not open health.lua")
    local src2 = f2:read("*a")
    f2:close()

    assert.is_truthy(src2:find("async-profiler", 1, true), "health.lua has no async-profiler probe")
  end)
end)

describe("Startup smoke (validate.sh stages 2-3)", function()
  it("verifies core init and modules load", function()
    assert.is_truthy(pcall(require, "tetravim.core.options"))
    assert.is_truthy(pcall(require, "tetravim.core.keymaps"))
    assert.is_truthy(pcall(require, "tetravim.core.autocmds"))
    assert.is_truthy(pcall(require, "tetravim.health"))
  end)
end)

describe("Startup smoke (validate.sh stage 5)", function()
  it("verifies LSP, completion & UI specs", function()
    local root = vim.fn.fnamemodify(debug.getinfo(1, "S").source:sub(2), ":p:h:h:h:h")
    local code =
      "assert(pcall(require, 'cmp'), 'cmp not available'); assert(pcall(require, 'lspconfig'), 'lspconfig not available'); assert(pcall(require, 'render-markdown'), 'render-markdown not available'); assert(pcall(require, 'persistence'), 'persistence not available')"
    local out = vim.fn.system({ "nvim", "--headless", "-u", root .. "/init.lua", "-c", "lua " .. code, "-c", "qa!" })
    assert.equals(0, vim.v.shell_error, "Failed to load plugins in child process: " .. out)
  end)
end)

describe("Startup smoke (validate.sh stage 5.1)", function()
  it("verifies File Explorer (oil.nvim) and keymaps", function()
    local root = vim.fn.fnamemodify(debug.getinfo(1, "S").source:sub(2), ":p:h:h:h:h")
    local code =
      "assert(pcall(require, 'oil'), 'oil module not found'); local maps = vim.api.nvim_get_keymap('n'); local found = false; for _, m in ipairs(maps) do if m.lhs == '<Space>e' or m.lhs == ' e' or m.lhs == '<leader>e' then found = true; break end end; assert(found, '<leader>e keymap not found')"
    local out = vim.fn.system({ "nvim", "--headless", "-u", root .. "/init.lua", "-c", "lua " .. code, "-c", "qa!" })
    assert.equals(0, vim.v.shell_error, "Failed to load oil.nvim and verify keymaps in child process: " .. out)
  end)
end)
