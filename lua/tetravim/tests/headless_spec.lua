-- lua/tetravim/tests/headless_spec.lua
--
-- Epic 5, Story 5.2 -- Enterprise Headless Setup & Telemetry.
--
-- The network-bound provisioning run (`scripts/headless-setup.sh`) is not
-- executed here; these tests assert the contract it depends on: the script
-- shape, the `TETRAVIM_HEADLESS` env -> `vim.g.tetravim_headless` bridge, the
-- machine-readable health JSON, and the opt-in telemetry sink capturing
-- notifications routed through `tetravim.util.ui`.

local config = vim.fn.stdpath("config")

describe("headless setup script (Story 5.2)", function()
  local path = config .. "/scripts/headless-setup.sh"

  it("is present and executable", function()
    assert.equals(1, vim.fn.filereadable(path))
    assert.equals(1, vim.fn.executable(path))
  end)

  it("runs non-interactively: sets TETRAVIM_HEADLESS and drives nvim --headless", function()
    local src = table.concat(vim.fn.readfile(path), "\n")
    assert.is_truthy(src:match("TETRAVIM_HEADLESS=1"))
    assert.is_truthy(src:match("%-%-headless"))
    assert.is_truthy(src:match("Lazy!?%s+sync"))
  end)

  it("provisions the Mason tool-chain and Tree-sitter parsers", function()
    local src = table.concat(vim.fn.readfile(path), "\n")
    assert.is_truthy(src:match("MasonToolsInstall"))
    assert.is_truthy(src:match("nvim%-treesitter"))
  end)
end)

describe("TETRAVIM_HEADLESS env bridge (Story 5.2)", function()
  it("flips vim.g.tetravim_headless when the env var is set", function()
    local saved_g = vim.g.tetravim_headless
    local saved_env = vim.env.TETRAVIM_HEADLESS

    vim.g.tetravim_headless = false
    vim.env.TETRAVIM_HEADLESS = "1"
    package.loaded["tetravim.core.options"] = nil
    pcall(require, "tetravim.core.options")

    assert.is_true(vim.g.tetravim_headless == true)

    vim.env.TETRAVIM_HEADLESS = saved_env
    vim.g.tetravim_headless = saved_g
  end)
end)

describe("machine-readable health JSON (Story 5.2)", function()
  local health = require("tetravim.core.health")

  it("json() returns valid JSON carrying the documented keys", function()
    local decoded = vim.json.decode(health.json())
    assert.is_string(decoded.neovim_version)
    assert.is_table(decoded.lsp_clients)
    assert.is_number(decoded.plugin_count)
    assert.is_number(decoded.pending_async_tasks)
    assert.is_boolean(decoded.telemetry_enabled)
  end)

  it("registers the :CheckHealthJson command", function()
    assert.equals(2, vim.fn.exists(":CheckHealthJson"))
  end)

  it("counts only in-flight (type=='pending') LSP requests as pending_async_tasks", function()
    local saved = vim.lsp.get_clients
    vim.lsp.get_clients = function()
      return {
        {
          name = "jdtls",
          requests = {
            [1] = { type = "pending" },
            [2] = { type = "complete" },
            [3] = { type = "cancel" },
            [4] = { type = "pending" },
          },
        },
      }
    end

    local decoded = vim.json.decode(health.json())
    vim.lsp.get_clients = saved

    assert.equals(2, decoded.pending_async_tasks)
  end)
end)

describe("telemetry export sink (Story 5.2)", function()
  local notify = require("tetravim.util.notify")
  local ui = require("tetravim.util.ui")
  local log_path = config .. "/telemetry.log"

  local saved_notify, saved_flag

  before_each(function()
    saved_notify = vim.notify
    saved_flag = vim.g.tetravim_telemetry_enabled
    vim.notify = function() end
  end)

  after_each(function()
    vim.notify = saved_notify
    vim.g.tetravim_telemetry_enabled = saved_flag
  end)

  local function log_line_count()
    if vim.fn.filereadable(log_path) ~= 1 then
      return 0
    end
    return #vim.fn.readfile(log_path)
  end

  it("is opt-in: nothing is written while telemetry is disabled", function()
    notify.disable_telemetry()
    local before = log_line_count()
    ui.notify_info("headless_spec: disabled probe")
    assert.equals(before, log_line_count())
  end)

  it("captures tetravim.util.ui notifications once enabled", function()
    notify.enable_telemetry()
    local marker = "headless_spec probe " .. tostring(os.time()) .. "-" .. tostring(math.random(1, 1e6))
    ui.notify_warn(marker)
    notify.disable_telemetry()

    -- The telemetry append is handed to libuv (non-blocking); wait for the
    -- marker line to actually land before reading it back.
    local hit
    local function scan()
      for _, line in ipairs(vim.fn.filereadable(log_path) == 1 and vim.fn.readfile(log_path) or {}) do
        if line:find(marker, 1, true) then
          hit = vim.json.decode(line)
        end
      end
      return hit ~= nil
    end
    vim.wait(2000, scan)

    assert.is_truthy(hit)
    assert.equals("warn", hit.level)
    assert.equals("TetraVim", hit.source)
  end)
end)
