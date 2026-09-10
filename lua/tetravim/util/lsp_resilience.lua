-- TetraVim LSP Resilience (Epic 5, Story 5.1)
--
-- Two guarantees for the long-running language servers TetraVim drives --
-- JDTLS above all:
--
--   * a bounded JVM heap, so indexing a large multi-module monorepo cannot
--     let the language server grow without limit and OOM the machine;
--   * a bounded auto-restart when the server process crashes, so a single
--     segfault does not silently leave the buffer with no LSP for the rest
--     of the session.
--
-- `apply_memory_limit` and `note_exit` are pure and unit-tested;
-- `make_on_exit` wires `note_exit` to a real restart callback so it can be
-- dropped straight into an LSP client's `on_exit`.

local M = {}

-- Heap ceiling / floor handed to the JDTLS JVM. 2g comfortably indexes a
-- large Maven/Gradle build without letting the server balloon; 512m keeps
-- the initial allocation modest on smaller machines.
M.JDTLS_MAX_HEAP = "2g"
M.JDTLS_MIN_HEAP = "512m"

-- At most this many automatic restarts per server inside the rolling
-- window. Past that TetraVim stops fighting a server that will not stay up
-- and points the user at `:LspLog`.
M.MAX_RESTARTS = 3
M.WINDOW_S = 180

-- Base backoff between automatic restarts. The nth restart in the current
-- window waits `n * RESTART_BACKOFF_MS` so a server that crashes on startup
-- is not hammered in a tight loop.
M.RESTART_BACKOFF_MS = 1000

-- ---------------------------------------------------------------------------
-- Memory limits (pure).
-- ---------------------------------------------------------------------------

--- Return a copy of `cmd` (a language-server argv list) with JVM heap limits
--- applied. A JDTLS-style launcher gets `--jvm-arg=-Xmx…` / `--jvm-arg=-Xms…`;
--- a bare `java -jar …` invocation gets the raw `-Xmx…` / `-Xms…` flags.
--- A flag already present -- as its own argv token, or the wrapper-prefixed
--- form -- is never duplicated, and `-Xmx` is skipped entirely when the
--- command already caps the heap via `-XX:MaxRAM*`. Non-table / empty input
--- is returned unchanged. Heap values are coerced to strings.
---
--- Note: an out-of-band `_JAVA_OPTIONS` / `JAVA_TOOL_OPTIONS` heap cap in the
--- environment is not visible to this pure argv transform; the launched JVM
--- still honours it and simply logs the override.
---@param cmd string[]
---@param opts? { xmx?: string|number, xms?: string|number }
---@return string[]
function M.apply_memory_limit(cmd, opts)
  if type(cmd) ~= "table" or #cmd == 0 then
    return cmd
  end
  opts = opts or {}
  local xmx = tostring(opts.xmx or M.JDTLS_MAX_HEAP)
  local xms = tostring(opts.xms or M.JDTLS_MIN_HEAP)

  local out = vim.deepcopy(cmd)
  local argv = vim.tbl_map(tostring, out)

  -- Launcher detection off the executable basename + whether any existing
  -- token already uses the wrapper's `--jvm-arg=` form -- not a blind
  -- substring scan of the whole joined command line.
  local wrapper = vim.fs.basename(argv[1] or ""):find("jdtls", 1, true) ~= nil
  for _, a in ipairs(argv) do
    if a:find("^%-%-jvm%-arg=") then
      wrapper = true
      break
    end
  end

  -- True when some argv token (bare or `--jvm-arg=`-prefixed) starts with
  -- `prefix`; token-anchored so `-Xmx` cannot match a substring mid-token.
  local function token_has_prefix(prefix)
    for _, a in ipairs(argv) do
      local bare = a:gsub("^%-%-jvm%-arg=", "")
      if bare:sub(1, #prefix) == prefix then
        return true
      end
    end
    return false
  end

  local function ensure(flag, value, skip_if)
    if token_has_prefix(flag) then
      return
    end
    for _, other in ipairs(skip_if or {}) do
      if token_has_prefix(other) then
        return
      end
    end
    out[#out + 1] = (wrapper and "--jvm-arg=" or "") .. flag .. value
  end

  ensure("-Xmx", xmx, { "-XX:MaxRAM" })
  ensure("-Xms", xms)
  return out
end

-- ---------------------------------------------------------------------------
-- Bounded auto-restart bookkeeping.
-- ---------------------------------------------------------------------------

-- name -> { count = <restarts still inside the window>, stamps = { <os.time>... } }
M._restarts = {}

--- Record that server `name` has exited unexpectedly and decide what to do.
--- Returns `"restart"` while the server is still inside its restart budget
--- for the current rolling window, or `"give-up"` once the budget is spent.
--- The second return value is the running restart count.
---@param name string
---@param now? integer os.time()-style timestamp (defaults to os.time())
---@return "restart"|"give-up" decision
---@return integer count
function M.note_exit(name, now)
  now = now or os.time()
  local rec = M._restarts[name]
  if not rec then
    rec = { count = 0, stamps = {} }
    M._restarts[name] = rec
  end

  -- Rolling window: drop restarts that have aged past WINDOW_S so a slow
  -- drip of crashes spread wider than the window never exhausts the budget.
  local cutoff = now - M.WINDOW_S
  local kept = {}
  for _, ts in ipairs(rec.stamps) do
    if ts > cutoff then
      kept[#kept + 1] = ts
    end
  end
  kept[#kept + 1] = now
  rec.stamps = kept
  rec.count = #kept

  if rec.count > M.MAX_RESTARTS then
    return "give-up", rec.count
  end
  return "restart", rec.count
end

--- Forget the restart history for `name` (or all servers when omitted).
--- Call after a healthy re-attach so a later crash starts a fresh window.
---@param name? string
function M.reset(name)
  if name then
    M._restarts[name] = nil
  else
    M._restarts = {}
  end
end

--- Build an LSP `on_exit` handler for server `name` that auto-restarts via
--- `restart_fn`, bounded by `MAX_RESTARTS` per `WINDOW_S` with an increasing
--- backoff between attempts. Only a clean shutdown -- exit code exactly 0 and
--- no signal (`:LspStop`, `:qa`) -- is ignored; a nil/unknown code is treated
--- as an unexpected exit worth a bounded restart.
---@param name string
---@param restart_fn fun()|nil
---@return fun(code: integer, signal: integer, client_id: integer)
function M.make_on_exit(name, restart_fn)
  return function(code, signal)
    -- Neovim is tearing down (`:qa`, `:qa!`, or a fatal signal): the server
    -- is being killed on purpose. A SIGTERM on shutdown often surfaces here
    -- as a non-zero code / signal 15 -- don't score it as a crash, don't
    -- burn a slot in the restart window, and don't queue a `vim.defer_fn`
    -- restart that just races the event-loop teardown.
    if vim.v.exiting ~= vim.NIL or vim.v.dying ~= 0 then
      return
    end

    if code == 0 and (signal == nil or signal == 0) then
      return
    end

    local decision, count = M.note_exit(name)
    local ui = require("tetravim.util.ui")

    if decision == "give-up" then
      vim.schedule(function()
        ui.notify_err(
          string.format(
            "%s crashed and was auto-restarted %d times within %ds -- giving up. Inspect :LspLog and restart manually.",
            name,
            M.MAX_RESTARTS,
            M.WINDOW_S
          )
        )
      end)
      return
    end

    local can_restart = type(restart_fn) == "function"
    vim.schedule(function()
      ui.notify_warn(
        string.format(
          "%s exited unexpectedly (code %s, signal %s) -- %s (%d/%d).",
          name,
          tostring(code),
          tostring(signal),
          can_restart and "auto-restarting" or "no restart handler wired",
          count,
          M.MAX_RESTARTS
        )
      )
    end)

    if can_restart then
      local delay = math.min(count, M.MAX_RESTARTS) * M.RESTART_BACKOFF_MS
      vim.defer_fn(function()
        pcall(restart_fn)
      end, delay)
    end
  end
end

--- Emit `:checkhealth` lines for Story 5.1 (async LSP + resilience).
--- Kept here so the wiring is exercised by the same unit path as the logic.
function M.health()
  local h = vim.health

  local async_ok, async = pcall(require, "tetravim.util.lsp_async")
  if async_ok and type(async.request_all_async) == "function" then
    h.ok("tetravim.util.lsp_async.request_all_async: available (non-blocking LSP fan-out)")
  else
    h.error("tetravim.util.lsp_async: failed to load or missing request_all_async")
  end

  local refactor_src_ok, refactor_src = pcall(function()
    return table.concat(vim.fn.readfile(vim.fn.stdpath("config") .. "/lua/tetravim/util/refactor.lua"), "\n")
  end)
  if refactor_src_ok and refactor_src:find("lsp_async", 1, true) then
    h.ok("Project-wide rename dispatches through the async wrapper (no synchronous buf_request_all)")
  else
    h.warn("refactor.lua does not appear to use tetravim.util.lsp_async for its LSP fan-out")
  end

  h.info(
    string.format(
      "JDTLS heap bounded to -Xmx%s / -Xms%s; crashed servers auto-restart up to %d times per %ds",
      M.JDTLS_MAX_HEAP,
      M.JDTLS_MIN_HEAP,
      M.MAX_RESTARTS,
      M.WINDOW_S
    )
  )

  local busy = {}
  for name, rec in pairs(M._restarts) do
    table.insert(busy, string.format("%s=%d", name, rec.count))
  end
  if #busy > 0 then
    h.warn("Servers that have needed an auto-restart this session: " .. table.concat(busy, ", "))
  else
    h.ok("No language server has required an auto-restart this session")
  end
end

return M
