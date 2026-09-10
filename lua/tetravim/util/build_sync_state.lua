-- TetraVim Build Sync Readiness State
--
-- Tracks whether the one-time Maven/Gradle dependency sync (see
-- lua/tetravim/core/autocmds.lua's "build_sync" VimEnter autocmd and
-- maven.sync_dependencies()/gradle.sync_dependencies()) has finished for
-- this session, so the java/kotlin/maven-related keymaps in
-- lua/tetravim/core/lang_keymaps.lua can stay hidden until dependencies are
-- actually resolved -- matching the "keybindings only show after sync
-- completes" behavior.

local M = {}

M.ready = false

-- True while a sync spawned by run() is in flight. apply() in
-- lang_keymaps.lua only ever ADDS keymaps, never removes them, so a
-- ready_gate keymap already bound to a buffer (e.g. <leader>cjS itself)
-- stays pressable even while `ready == false` -- only the which-key popup
-- hides it. Without this guard, pressing it twice in quick succession would
-- spawn two independent, uncoordinated sync processes.
M.syncing = false

local listeners = {}
local sync_timer = nil

--- Mark the sync as finished (success, failure, or "nothing to sync") and
--- fire every listener registered via on_ready(). Safe to call more than
--- once -- only the first call fires listeners, but syncing is always
--- cleared so a stuck M.syncing flag can never outlive its sync attempt.
function M.mark_ready()
  M.syncing = false
  if sync_timer then
    vim.fn.timer_stop(sync_timer)
    sync_timer = nil
  end
  if M.ready then
    return
  end
  M.ready = true
  for _, cb in ipairs(listeners) do
    local ok, err = pcall(cb)
    if not ok then
      vim.notify("TetraVim: build_sync_state on_ready listener failed: " .. tostring(err), vim.log.levels.WARN)
    end
  end
end

--- Register a callback to run once sync is ready. If it's already ready,
--- runs immediately (synchronously).
function M.on_ready(cb)
  if M.ready then
    cb()
  else
    table.insert(listeners, cb)
  end
end

--- Re-arm the state for a manual resync (see keymaps.lua's <leader>cjS).
--- Deliberately does NOT touch `listeners` -- mark_ready() iterates that
--- table without draining it, so every callback already registered via
--- on_ready() (e.g. lang_keymaps.lua's which-key refresh) fires again on
--- the next mark_ready() with no need to re-register.
function M.reset()
  M.ready = false
end

--- Detect the project's build tool and (re)run its dependency sync, or mark
--- ready immediately if there's nothing to sync. Single source of truth for
--- both the one-time VimEnter sync (autocmds.lua) and the manual resync
--- keymap, so the branch only lives in one place. No-ops while a sync is
--- already in flight (see M.syncing above) instead of spawning a second,
--- overlapping mvn/gradle process.
function M.run()
  if M.syncing then
    return
  end
  M.syncing = true
  -- Set a timeout to auto-clear the syncing flag after 60s to prevent indefinite lock
  if sync_timer then
    vim.fn.timer_stop(sync_timer)
  end
  sync_timer = vim.fn.timer_start(60000, function()
    if M.syncing then
      vim.notify("TetraVim: build sync timeout (60s), clearing lock", vim.log.levels.WARN)
      M.syncing = false
      sync_timer = nil
    end
  end)
  local cwd = vim.fn.getcwd()
  local tool, root = require("tetravim.util.build").detect(cwd)

  if not tool then
    -- Nothing to sync -- don't leave the gated java/kotlin/maven keymaps
    -- (lang_keymaps.lua) hidden forever waiting on a sync that will never run.
    M.mark_ready()
    return
  end
  root = root or cwd
  local sync_runner = require("tetravim.util.sync_runner")

  if tool == "maven" then
    local base_cmd = require("tetravim.util.build").wrapper_cmd("maven", root)
    sync_runner.run({
      cmd = { base_cmd, "-q", "dependency:resolve" },
      notify_id = "tetravim_maven_sync",
      tool_label = "Maven",
      base_cmd = base_cmd,
      cwd = root,
    })
  elseif tool == "gradle" then
    local base_cmd = require("tetravim.util.build").wrapper_cmd("gradle", root)
    sync_runner.run({
      cmd = { base_cmd, "-q", "dependencies" },
      notify_id = "tetravim_gradle_sync",
      tool_label = "Gradle",
      base_cmd = base_cmd,
      cwd = root,
    })
  else
    M.mark_ready()
  end
end

return M
