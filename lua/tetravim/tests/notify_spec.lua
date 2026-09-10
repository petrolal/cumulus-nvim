-- Smoke tests for tetravim.util.notify

describe("tetravim.util.notify", function()
  local notify = require("tetravim.util.notify")

  local captured
  local orig_notify

  before_each(function()
    captured = {}
    orig_notify = vim.notify
    vim.notify = function(msg, level, opts)
      table.insert(captured, { msg = msg, level = level, opts = opts })
    end
  end)

  after_each(function()
    vim.notify = orig_notify
  end)

  it("exposes the four wrappers", function()
    assert.is_function(notify.notify)
    assert.is_function(notify.notify_info)
    assert.is_function(notify.notify_warn)
    assert.is_function(notify.notify_err)
  end)

  it("defaults level to INFO and title to TetraVim", function()
    notify.notify("hello")
    assert.are.equal("hello", captured[1].msg)
    assert.are.equal(vim.log.levels.INFO, captured[1].level)
    assert.are.equal("TetraVim", captured[1].opts.title)
  end)

  it("maps each helper to its level and keeps a custom title", function()
    notify.notify_info("i", "Custom")
    notify.notify_warn("w", "Custom")
    notify.notify_err("e", "Custom")
    assert.are.equal(vim.log.levels.INFO, captured[1].level)
    assert.are.equal(vim.log.levels.WARN, captured[2].level)
    assert.are.equal(vim.log.levels.ERROR, captured[3].level)
    assert.are.equal("Custom", captured[3].opts.title)
  end)

  it("merges caller-supplied opts without dropping the title", function()
    notify.notify("x", vim.log.levels.WARN, "T", { timeout = 10, id = "abc" })
    assert.are.equal("T", captured[1].opts.title)
    assert.are.equal(10, captured[1].opts.timeout)
    assert.are.equal("abc", captured[1].opts.id)
  end)

  it("rolls telemetry.log over to a single .1 backup once it passes ~1 MiB", function()
    local tmp = vim.fn.tempname()
    vim.fn.mkdir(tmp, "p")
    local saved_stdpath = vim.fn.stdpath
    local saved_flag = vim.g.tetravim_telemetry_enabled
    vim.fn.stdpath = function(what)
      if what == "config" then
        return tmp
      end
      return saved_stdpath(what)
    end
    vim.g.tetravim_telemetry_enabled = true

    local log_path = tmp .. "/telemetry.log"
    local seed = io.open(log_path, "w")
    seed:write(string.rep("x", 1024 * 1024 + 16))
    seed:close()

    notify.notify("rotation probe")

    -- The append is now handed to libuv (non-blocking); wait for it to land.
    vim.wait(2000, function()
      return vim.fn.filereadable(log_path) == 1
    end)

    vim.g.tetravim_telemetry_enabled = saved_flag
    vim.fn.stdpath = saved_stdpath

    assert.equals(1, vim.fn.filereadable(log_path .. ".1"))
    -- the fresh log holds only the just-written line, not the seeded bulk
    local size = (vim.uv or vim.loop).fs_stat(log_path).size
    assert.is_true(size < 1024 * 1024)
  end)
end)
