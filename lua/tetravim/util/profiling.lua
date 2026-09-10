-- TetraVim JVM continuous profiling -- async-profiler front-end.
--
-- Wraps the async-profiler launcher (`asprof` on v3, `profiler.sh` on v2, or an
-- `async-profiler` shim) behind the <leader>jp keymaps. All process launches go
-- through `vim.system` async -- nothing here blocks the UI thread.

local M = {}

-- Public so profiling_spec.lua can assert they initialise to nil.
M.active_pid = nil
M.last_flamegraph = nil

local notify = require("tetravim.util.notify")

local function say(msg, level)
  notify.notify(msg, level, "TetraVim Profiler")
end

-- Preferred launcher first: `asprof` (v3), then `profiler.sh` (v2), then a
-- distro/`async-profiler` shim as a last resort.
local LAUNCHERS = { "asprof", "profiler.sh", "async-profiler" }

--- Resolve the async-profiler launcher on $PATH.
---@return string|nil
function M.profiler_cmd()
  for _, bin in ipairs(LAUNCHERS) do
    if vim.fn.executable(bin) == 1 then
      return bin
    end
  end
  return nil
end

function M.start()
  if M.active_pid then
    say("Profiling already active for PID: " .. M.active_pid, vim.log.levels.WARN)
    return
  end

  local cmd = M.profiler_cmd()
  if not cmd then
    say("async-profiler launcher not found in $PATH (asprof / profiler.sh)", vim.log.levels.ERROR)
    return
  end

  vim.ui.input({ prompt = "Enter JVM PID to profile: " }, function(pid)
    if not pid or pid == "" then
      return
    end
    pid = vim.trim(pid)
    if not pid:match("^%d+$") then
      say("Invalid PID", vim.log.levels.ERROR)
      return
    end

    vim.system({ cmd, "start", pid }, { text = true }, function(out)
      vim.schedule(function()
        if out.code == 0 then
          M.active_pid = pid
          say("Started profiling PID: " .. pid, vim.log.levels.INFO)
        else
          say("Failed to start profiler: " .. (out.stderr or out.stdout or ""), vim.log.levels.ERROR)
        end
      end)
    end)
  end)
end

function M.stop()
  if not M.active_pid then
    say("No active profiling session found", vim.log.levels.WARN)
    return
  end

  local cmd = M.profiler_cmd()
  if not cmd then
    say("async-profiler launcher not found in $PATH (asprof / profiler.sh)", vim.log.levels.ERROR)
    return
  end

  local tmp_dir = vim.fn.stdpath("cache") .. "/tetravim-profiler"
  vim.fn.mkdir(tmp_dir, "p")
  if vim.fn.filewritable(tmp_dir) ~= 2 then
    say("Cannot write to directory: " .. tmp_dir, vim.log.levels.ERROR)
    return
  end

  local pid = M.active_pid
  local out_file = tmp_dir .. "/flamegraph_" .. pid .. "_" .. os.time() .. ".html"

  vim.system({ cmd, "stop", "-f", out_file, pid }, { text = true }, function(out)
    vim.schedule(function()
      M.active_pid = nil
      if out.code == 0 and vim.fn.filereadable(out_file) == 1 then
        M.last_flamegraph = out_file
        say("Stopped profiling. Flamegraph generated at:\n" .. out_file, vim.log.levels.INFO)
      else
        say("Failed to stop profiler or missing flamegraph: " .. (out.stderr or out.stdout or ""), vim.log.levels.ERROR)
      end
    end)
  end)
end

function M.view()
  if not M.last_flamegraph or vim.fn.filereadable(M.last_flamegraph) == 0 then
    say("No generated flamegraph available", vim.log.levels.ERROR)
    return
  end

  local ok, err = pcall(vim.ui.open, M.last_flamegraph)
  if ok then
    say("Opening flamegraph...", vim.log.levels.INFO)
  else
    say("Cannot open flamegraph: " .. tostring(err), vim.log.levels.ERROR)
  end
end

return M
