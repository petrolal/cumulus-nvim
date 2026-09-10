-- Async LSP request utilities for TetraVim (Epic 5, Story 5.1)
--
-- Non-blocking wrappers around LSP requests. The synchronous
-- `vim.lsp.buf_request_all` blocks the UI thread until every client answers
-- (or the timeout fires); `request_all_async` instead fans the request out
-- to every attached client and invokes a callback on `vim.schedule` once the
-- last response lands, so the editor stays interactive under heavy load.

local M = {}

--- Every LSP client attached to `bufnr`, across Neovim versions
--- (`vim.lsp.get_clients` is 0.10+; older builds expose `get_active_clients`).
---@param bufnr integer
---@return vim.lsp.Client[]
local function attached_clients(bufnr)
  local getter = vim.lsp.get_clients or vim.lsp.get_active_clients
  return getter({ bufnr = bufnr })
end

--- Issue an LSP request on a client, tolerating both the method-call form
--- (`client:request`, current) and the older function form (`client.request`).
---@return boolean ok
---@return integer|nil request_id
local function client_request(client, method, params, handler, bufnr)
  local send = client.request
  if type(send) ~= "function" then
    return false
  end
  -- `client.request` and `client:request` share an implementation; passing
  -- `client` explicitly keeps it working whichever way the field is defined.
  return send(client, method, params, handler, bufnr)
end

--- Best-effort cancel of an in-flight request on a client, across the
--- method-call (`client:cancel_request`) and function (`client.cancel_request`)
--- forms. Silent when the client exposes no cancel entry point.
local function client_cancel(client, request_id)
  if request_id == nil then
    return
  end
  local cancel = client.cancel_request
  if type(cancel) == "function" then
    pcall(cancel, client, request_id)
  end
end

--- Synchronous wrapper around the existing `vim.lsp.buf_request_all` (may
--- block). Retained for callers that genuinely need the result inline.
--- @param bufnr integer Buffer number
--- @param method string LSP method name
--- @param params table Parameters for the request
--- @return table responses Mapping client.id -> { err = ..., result = ... }
function M.request_all_sync(bufnr, method, params)
  return vim.lsp.buf_request_all(bufnr, method, params)
end

--- Asynchronous fan-out: dispatch `method` to every LSP client attached to
--- `bufnr` and call `callback(results)` -- on `vim.schedule` -- once all
--- clients have responded (or the optional timeout fires). `results` maps
--- `client.id` to `{ err = ..., error = ..., result = ... }` (`error` is a
--- stdlib-parity alias for `err`). Never blocks the UI thread.
--- @param bufnr integer Buffer number
--- @param method string LSP method name
--- @param params table Parameters for the request
--- @param callback fun(results: table<integer, { err: any, error: any, result: any }>)|nil
--- @param opts? { timeout_ms?: integer } When `timeout_ms` is set, any client
---        that has not answered by then is cancelled and recorded with
---        `timed_out = true`, and the callback fires once.
--- @return fun() cancel Cancels every still-pending client request and settles
---         the callback with what has arrived so far (each unfinished client
---         recorded with `cancelled = true`). Safe to call after completion.
function M.request_all_async(bufnr, method, params, callback, opts)
  opts = opts or {}
  local clients = attached_clients(bufnr)
  local pending = #clients
  local results = {}
  local answered = {}
  local finished = false
  local inflight = {}
  local timer

  local function finish()
    if finished then
      return
    end
    finished = true
    if timer then
      timer:stop()
      if not timer:is_closing() then
        timer:close()
      end
      timer = nil
    end
    if callback then
      vim.schedule(function()
        callback(results)
      end)
    end
  end

  -- Settle one client exactly once. `entry` nil means "count it as answered
  -- but record nothing" (a client that refused the request outright).
  local function settle(client_id, entry)
    if finished or answered[client_id] then
      return
    end
    answered[client_id] = true
    inflight[client_id] = nil
    if entry ~= nil then
      results[client_id] = entry
    end
    pending = pending - 1
    if pending <= 0 then
      finish()
    end
  end

  if pending == 0 then
    finish()
    return function() end
  end

  for _, client in ipairs(clients) do
    local cid = client.id
    local ok, request_id = client_request(client, method, params, function(err, result)
      settle(cid, { err = err, error = err, result = result })
    end, bufnr)

    if ok then
      if not answered[cid] and request_id ~= nil then
        inflight[cid] = { client = client, request_id = request_id }
      end
    else
      -- The client refused the request outright -- count it as answered so
      -- the callback is not stranded waiting on a response that will never
      -- come. Guarded by `answered` so a client whose handler already fired
      -- synchronously is not double-counted.
      settle(cid, nil)
    end
  end

  local function cancel_pending(reason_key)
    for cid, rec in pairs(inflight) do
      client_cancel(rec.client, rec.request_id)
      if not answered[cid] then
        answered[cid] = true
        results[cid] = { err = reason_key, error = reason_key, result = nil, [reason_key] = true }
        pending = pending - 1
      end
    end
    inflight = {}
    finish()
  end

  if not finished and type(opts.timeout_ms) == "number" and opts.timeout_ms > 0 then
    timer = vim.defer_fn(function()
      timer = nil
      if not finished then
        cancel_pending("timed_out")
      end
    end, opts.timeout_ms)
  end

  return function()
    if not finished then
      cancel_pending("cancelled")
    end
  end
end

return M
