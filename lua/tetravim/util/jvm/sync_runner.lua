-- TetraVim Shared Maven/Gradle Sync Runner (Story 41.6)
--
-- maven.lua and gradle.lua each spawn their own build tool's dependency
-- resolution and drive an identical timer/notification lifecycle (heartbeat
-- toast, timeout-kill safeguard, success/failure notify, sync_state's
-- mark_ready()). This module owns that shared lifecycle so a future fix
-- only needs to be made once -- a duplicated double-close bug fix
-- previously had to be manually re-applied across both files.
local M = {}

local ui = require("tetravim.util.ui")

-- Cold local-repo/offline-mirror resolution can legitimately take a while,
-- but a stuck mvn/gradle process (hung proxy auth, dead network) must not
-- hide the gated java/kotlin/maven keymaps (lang_keymaps.lua) forever.
local SYNC_TIMEOUT_MS = 120000

-- How often the heartbeat timer refreshes the "syncing..." toast so a
-- healthy-but-slow sync is visibly distinguishable from a hung one.
local HEARTBEAT_INTERVAL_MS = 5000

--- Run a build-tool dependency sync with a heartbeat-updating notification
--- toast and a timeout/cancellation safeguard.
---
--- @param opts table
---   cmd        table  command + args passed to vim.system, e.g.
---                     { "mvn", "-q", "dependency:resolve" }
---   notify_id  string stable vim.notify id so start/heartbeat/success/
---                     failure/timeout all collapse into one toast
---   tool_label string e.g. "Maven" / "Gradle", used to build message text
---   base_cmd   string the resolved binary/wrapper, used only in the
---                     spawn-failure message
function M.run(opts)
  local sync_state = require("tetravim.util.jvm.build_sync_state")

  ui.notify_info(opts.tool_label .. ": syncing dependencies...", nil, { id = opts.notify_id })
  local timed_out = false
  local timer = vim.uv.new_timer()
  -- Independent from `timer` (the timeout-kill timer) above -- this one only
  -- ever updates the notification toast and never touches the process.
  local heartbeat = vim.uv.new_timer()
  local started = vim.uv.now()

  -- The timeout branch below and the process exit callback can both want to
  -- close `heartbeat` (timeout closes it immediately so it stops updating
  -- the toast after a "timed out" notification; the exit callback closes it
  -- via stop_timers() when the killed process's exit eventually shows up).
  -- Guard against double-closing the same handle, which libuv raises as an
  -- uncaught Lua error ("handle already closing").
  local function close_heartbeat()
    if heartbeat:is_closing() then
      return
    end
    heartbeat:stop()
    heartbeat:close()
  end

  -- Same double-close guard for the timeout-kill timer. `timer` used to be
  -- closed only from stop_timers(), which only runs from the process exit
  -- callback -- but the timeout branch below documents that that callback may
  -- never fire (an orphaned grandchild keeps the pipes open), so on every
  -- timed-out sync the handle leaked for the rest of the session. Close it in
  -- the timeout branch too, via this guard so the (possibly late) exit
  -- callback's stop_timers() doesn't double-close.
  local function close_timer()
    if timer:is_closing() then
      return
    end
    timer:stop()
    timer:close()
  end

  local function stop_timers()
    close_timer()
    close_heartbeat()
  end

  -- vim.system() throws synchronously (not via the callback) when the
  -- binary doesn't exist at all (ENOENT) -- e.g. no wrapper script and the
  -- tool isn't on $PATH. pcall it so that shows up as a notification instead
  -- of an uncaught error breaking whatever autocmd triggered this.
  local ok, handle_or_err = pcall(vim.system, opts.cmd, { text = true, cwd = opts.cwd }, function(result)
    stop_timers()
    if timed_out then
      -- The timeout timer below already called mark_ready() and notified
      -- the user -- don't fire a second, possibly-contradictory
      -- notification if the killed process's exit callback eventually
      -- shows up late (e.g. a forked, non-exec'd grandchild kept the
      -- stdout/stderr pipes open after the direct child was killed).
      return
    end
    vim.schedule(function()
      -- The java/kotlin/maven-related keymaps (lang_keymaps.lua) stay
      -- hidden until sync finishes -- mark ready on both success and
      -- failure so a broken/offline sync doesn't hide them forever.
      sync_state.mark_ready()
      if result.code == 0 then
        ui.notify_info(opts.tool_label .. ": dependencies synced", nil, { id = opts.notify_id })
      else
        local detail = (result.stderr ~= "" and result.stderr)
          or (result.stdout ~= "" and result.stdout)
          or ("exit code " .. result.code)
        ui.notify_err(opts.tool_label .. ": dependency sync failed\n" .. detail, nil, { id = opts.notify_id })
      end
    end)
  end)
  if ok then
    local handle = handle_or_err
    heartbeat:start(
      HEARTBEAT_INTERVAL_MS,
      HEARTBEAT_INTERVAL_MS,
      vim.schedule_wrap(function()
        local elapsed_seconds = math.floor((vim.uv.now() - started) / 1000)
        ui.notify_info(
          opts.tool_label .. ": syncing dependencies... (" .. elapsed_seconds .. "s)",
          nil,
          { id = opts.notify_id }
        )
      end)
    )
    timer:start(SYNC_TIMEOUT_MS, 0, function()
      -- Set the flag and kill the process synchronously, right here in the
      -- raw (unscheduled) timer callback -- both are libuv-level operations
      -- safe outside the main loop. Deferring `timed_out = true` itself via
      -- vim.schedule_wrap would leave a race window where the process's own
      -- (also unscheduled) exit callback could see `timed_out == false` and
      -- report success/failure normally right before this timeout branch
      -- also runs, producing two contradictory notifications.
      timed_out = true
      close_heartbeat()
      close_timer()
      pcall(handle.kill, handle, "sigterm")
      vim.schedule(function()
        -- Don't wait for the exit callback to fire before unhiding the
        -- gated keymaps: a killed process is not guaranteed to actually
        -- close its stdout/stderr pipes promptly (e.g. an orphaned
        -- grandchild process can keep them open indefinitely), and that
        -- callback is what the exit-callback branch above depends on. Mark
        -- ready and notify here, unconditionally, so a timeout always
        -- resolves on schedule regardless of whether the kill signal is
        -- ever actually observed to take effect.
        sync_state.mark_ready()
        ui.notify_err(
          opts.tool_label .. ": dependency sync timed out after " .. (SYNC_TIMEOUT_MS / 1000) .. "s",
          nil,
          { id = opts.notify_id }
        )
      end)
    end)
  else
    stop_timers()
    sync_state.mark_ready()
    ui.notify_err(
      opts.tool_label
        .. ": dependency sync failed to start ("
        .. opts.base_cmd
        .. " not found)\n"
        .. tostring(handle_or_err),
      nil,
      { id = opts.notify_id }
    )
  end
end

return M
