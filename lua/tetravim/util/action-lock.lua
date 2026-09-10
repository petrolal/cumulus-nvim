-- TetraVim Action Lock (shared busy-guard for refactor.lua / extract.lua)
--
-- refactor.lua's project-wide rename and extract.lua's extract/inline
-- actions both drive the same buffer-local quickfix-preview-then-apply
-- flow against the same JDTLS/Kotlin LS client. Each module used to keep
-- its own private `M._busy` flag, which only guarded against a SECOND
-- action of the SAME kind overlapping -- a rename in progress in
-- refactor.lua would NOT block a concurrent extract in extract.lua (or vice
-- versa), letting two overlapping previews/applies race against the same
-- buffers. This module is the single shared source of truth for that guard
-- instead, without changing either module's public API.
--
-- Self-healing watchdog: `acquire()` also arms a timer that force-releases
-- the lock if no `release()` arrives within `DEFAULT_TIMEOUT_MS`. Call
-- sites still release on every deterministic path (that stays the contract
-- and keeps the UX responsive), but a future handler that returns early
-- without releasing can no longer wedge every subsequent refactor/extract
-- for the rest of the session.

local M = {}

local busy = false
local watchdog ---@type uv_timer_t|nil

-- Ceiling for any single refactor/extract action. Comfortably longer than
-- refactor.lua's RENAME_TIMEOUT_MS and extract.lua's ACTION_TIMEOUT_MS, so
-- this only ever fires when a call site genuinely leaked the lock.
local DEFAULT_TIMEOUT_MS = 45000

local function stop_watchdog()
  if watchdog then
    if not watchdog:is_closing() then
      watchdog:stop()
      watchdog:close()
    end
    watchdog = nil
  end
end

--- @return boolean true while any refactor/extract action is in flight.
function M.is_busy()
  return busy
end

--- Marks the lock held. Callers must still pair this with a later release()
--- on EVERY deterministic path out (success, warning, error, cancel). The
--- watchdog is only a backstop against a leaked lock.
--- @param timeout_ms? number override for the force-release deadline
function M.acquire(timeout_ms)
  busy = true
  stop_watchdog()
  local t = vim.uv.new_timer()
  if not t then
    return
  end
  watchdog = t
  t:start(
    timeout_ms or DEFAULT_TIMEOUT_MS,
    0,
    vim.schedule_wrap(function()
      if busy then
        busy = false
        pcall(function()
          require("tetravim.util.notify").notify_warn(
            "Refactor/extract lock auto-released after timeout -- the previous action never reported completion.",
            "TetraVim Refactor"
          )
        end)
      end
      stop_watchdog()
    end)
  )
end

--- Releases the lock and disarms the watchdog. Idempotent.
function M.release()
  busy = false
  stop_watchdog()
end

return M
