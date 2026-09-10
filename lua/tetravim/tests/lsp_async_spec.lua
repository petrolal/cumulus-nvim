-- lua/tetravim/tests/lsp_async_spec.lua
--
-- Epic 5, Story 5.1 -- non-blocking LSP request fan-out.

local async = require("tetravim.util.lsp.async")

describe("request_all_async", function()
  local saved_get, saved_get_active, saved_schedule, saved_defer
  local deferred

  before_each(function()
    saved_get = vim.lsp.get_clients
    saved_get_active = vim.lsp.get_active_clients
    saved_schedule = vim.schedule
    saved_defer = vim.defer_fn
    deferred = {}
    -- run scheduled callbacks inline so the tests stay synchronous
    vim.schedule = function(fn)
      fn()
    end
    -- capture the timeout timer instead of arming the real event loop
    vim.defer_fn = function(fn, ms)
      table.insert(deferred, { fn = fn, ms = ms })
      return {
        stop = function() end,
        is_closing = function()
          return false
        end,
        close = function() end,
      }
    end
  end)

  after_each(function()
    vim.lsp.get_clients = saved_get
    vim.lsp.get_active_clients = saved_get_active
    vim.schedule = saved_schedule
    vim.defer_fn = saved_defer
  end)

  local function fake_client(id, answer)
    return {
      id = id,
      request = function(_self, _method, _params, handler)
        -- deliver a response without touching the real event loop
        handler(answer.err, answer.result)
        return true, id
      end,
    }
  end

  it("invokes the callback once with a client.id -> {err,result} map", function()
    vim.lsp.get_clients = function()
      return {
        fake_client(1, { result = "a" }),
        fake_client(2, { result = "b" }),
      }
    end

    local calls, got = 0, nil
    async.request_all_async(0, "textDocument/rename", {}, function(results)
      calls = calls + 1
      got = results
    end)

    assert.equals(1, calls)
    assert.equals("a", got[1].result)
    assert.equals("b", got[2].result)
  end)

  it("still calls back (with an empty table) when no client is attached", function()
    vim.lsp.get_clients = function()
      return {}
    end

    local called, got = false, nil
    async.request_all_async(0, "textDocument/rename", {}, function(results)
      called = true
      got = results
    end)

    assert.is_true(called)
    assert.same({}, got)
  end)

  it("does not strand the callback when a client refuses the request", function()
    vim.lsp.get_clients = function()
      return {
        {
          id = 7,
          request = function()
            return false
          end,
        },
        fake_client(8, { result = "ok" }),
      }
    end

    local called, got = false, nil
    async.request_all_async(0, "textDocument/rename", {}, function(results)
      called = true
      got = results
    end)

    assert.is_true(called)
    assert.equals("ok", got[8].result)
    assert.is_nil(got[7])
  end)

  it("cancels a client that never answers once the timeout fires, settling once", function()
    local cancelled = {}
    vim.lsp.get_clients = function()
      return {
        {
          id = 3,
          request = function()
            return true, 99
          end,
          cancel_request = function(_self, id)
            table.insert(cancelled, id)
          end,
        },
      }
    end

    local calls, got = 0, nil
    async.request_all_async(0, "textDocument/rename", {}, function(results)
      calls = calls + 1
      got = results
    end, { timeout_ms = 50 })

    assert.equals(0, calls) -- nothing has answered yet
    assert.equals(1, #deferred)

    deferred[1].fn() -- fire the timeout

    assert.equals(1, calls)
    assert.is_true(got[3].timed_out)
    assert.same({ 99 }, cancelled)
  end)

  it("the returned cancel() settles a still-pending client and is idempotent", function()
    vim.lsp.get_clients = function()
      return {
        {
          id = 4,
          request = function()
            return true, 7
          end,
          cancel_request = function() end,
        },
      }
    end

    local calls, got = 0, nil
    local cancel = async.request_all_async(0, "textDocument/rename", {}, function(results)
      calls = calls + 1
      got = results
    end)

    assert.equals(0, calls)
    cancel()
    assert.equals(1, calls)
    assert.is_true(got[4].cancelled)

    cancel() -- a second call must not fire the callback again
    assert.equals(1, calls)
  end)

  it("falls back to get_active_clients on older Neovim", function()
    vim.lsp.get_clients = nil
    vim.lsp.get_active_clients = function()
      return { fake_client(1, { result = "legacy" }) }
    end

    local got
    async.request_all_async(0, "textDocument/rename", {}, function(results)
      got = results
    end)

    assert.equals("legacy", got[1].result)
  end)
end)
