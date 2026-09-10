-- TetraVim JVM continuous profiling -- async-profiler front-end.
--
-- Wraps the async-profiler launcher (`asprof` on v3, `profiler.sh` on v2, or an
-- `async-profiler` shim) behind the <leader>jp keymaps. All process launches go
-- through `vim.system` async -- nothing here blocks the UI thread.
--
-- Two paths:
--   * <leader>jps / jpx / jpv -- the fire-and-forget path: start/stop a live
--     session, open the generated interactive HTML flamegraph in a browser.
--   * <leader>jpp (M.capture) -- IDEA's "profiler tool window" parity: pick a
--     running JVM with `jps`, take a fixed-duration `-o collapsed` capture, parse
--     the folded stacks into a call tree and render it foldable in the shared
--     tetravim.util.panel split.

local M = {}

-- Public so profiling_spec.lua can assert they initialise to nil.
M.active_pid = nil
M.last_flamegraph = nil

-- Interactive call-tree state. Module-level because panel.render() fully
-- re-renders on every refresh, so fold state cannot live in the closure.
M._tree = nil
M._collapsed = {}
M._last_capture = nil
M._raw_file = nil

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

-- ---------------------------------------------------------------------------
-- Interactive call-tree path (<leader>jpp)
-- ---------------------------------------------------------------------------

--- Choose a running JVM. Uses `jps -l` when available, otherwise prompts for a
--- PID. Calls `cb(pid)` with a validated numeric string; silent on cancel.
---@param cb fun(pid: string)
function M.pick_pid(cb)
  local function prompt_manual()
    vim.ui.input({ prompt = "Enter JVM PID to profile: " }, function(pid)
      if not pid or vim.trim(pid) == "" then
        return
      end
      pid = vim.trim(pid)
      if not pid:match("^%d+$") then
        say("Invalid PID", vim.log.levels.ERROR)
        return
      end
      cb(pid)
    end)
  end

  if vim.fn.executable("jps") ~= 1 then
    prompt_manual()
    return
  end

  vim.system({ "jps", "-l" }, { text = true }, function(out)
    vim.schedule(function()
      if out.code ~= 0 then
        prompt_manual()
        return
      end
      local items = {}
      for line in (out.stdout or ""):gmatch("[^\r\n]+") do
        local pid, label = line:match("^(%d+)%s*(.*)$")
        if pid and not (label or ""):match("sun%.tools%.jps%.Jps") and not (label or ""):match("jdk%.jcmd") then
          items[#items + 1] = { pid = pid, label = (label ~= "" and label or "<unknown>") }
        end
      end
      if #items == 0 then
        say("No running JVMs found by jps -- enter a PID manually", vim.log.levels.WARN)
        prompt_manual()
        return
      end
      vim.ui.select(items, {
        prompt = "Select JVM to profile:",
        format_item = function(it)
          return ("%-8s %s"):format(it.pid, it.label)
        end,
      }, function(choice)
        if choice then
          cb(choice.pid)
        end
      end)
    end)
  end)
end

--- Parse async-profiler `-o collapsed` folded stacks into a call tree.
---@param lines string[]
---@return table root
local function build_tree(lines)
  local root = { name = "all", total = 0, self = 0, children = {}, order = {}, id = "" }
  for _, line in ipairs(lines) do
    local frames, count = line:match("^(.-)%s+(%d+)%s*$")
    count = tonumber(count)
    if frames and count then
      local cur = root
      root.total = root.total + count
      local last
      for frame in frames:gmatch("[^;]+") do
        local child = cur.children[frame]
        if not child then
          child = { name = frame, total = 0, self = 0, children = {}, order = {}, id = cur.id .. "/" .. frame }
          cur.children[frame] = child
          cur.order[#cur.order + 1] = frame
        end
        child.total = child.total + count
        cur = child
        last = child
      end
      if last then
        last.self = last.self + count
      else
        root.self = root.self + count
      end
    end
  end
  return root
end

function M._render_panel()
  local panel = require("tetravim.util.panel")
  local tree = M._tree
  if not tree then
    return
  end
  local total = math.max(tree.total, 1)
  local rows = {}

  local function add_rows(node, depth)
    local kids = {}
    for _, name in ipairs(node.order) do
      kids[#kids + 1] = node.children[name]
    end
    table.sort(kids, function(a, b)
      return a.total > b.total
    end)
    local indent = string.rep("  ", depth)
    for _, k in ipairs(kids) do
      local has_kids = #k.order > 0
      local expanded = has_kids and not M._collapsed[k.id]
      local marker = has_kids and (expanded and "▾" or "▸") or " "
      rows[#rows + 1] = {
        text = string.format(
          "%s%s %6.2f%%  self %5.2f%%  %10d  %s",
          indent,
          marker,
          k.total / total * 100,
          k.self / total * 100,
          k.total,
          k.name
        ),
        item = { id = k.id, name = k.name },
      }
      if expanded then
        add_rows(k, depth + 1)
      end
    end
  end

  add_rows(tree, 0)

  local pid, dur = "?", "?"
  if M._last_capture then
    pid, dur = M._last_capture.pid, M._last_capture.dur
  end

  panel.render({
    name_hint = "tetravim-profiler",
    filetype = "tetravim-profiler",
    header = {
      string.format("TetraVim Profiler  ·  PID %s  ·  %ss  ·  %d samples", pid, dur, tree.total),
      "<CR>/o expand · E expand-all · C collapse-top · g raw stacks · r re-capture · q close",
      "",
    },
    rows = rows,
    on_select = M._toggle,
    refresh = function()
      if M._last_capture then
        M.capture(M._last_capture)
      end
    end,
    keymaps = {
      o = M._toggle,
      E = function()
        M._collapsed = {}
        M._render_panel()
      end,
      C = function()
        for _, name in ipairs(M._tree.order) do
          M._collapsed[M._tree.children[name].id] = true
        end
        M._render_panel()
      end,
      g = function()
        if M._raw_file and vim.fn.filereadable(M._raw_file) == 1 then
          local body = table.concat(vim.fn.readfile(M._raw_file), "\n")
          require("tetravim.util.split").open(body, { filetype = "text", name_hint = "tetravim-profiler-raw" })
        else
          say("No raw capture file available", vim.log.levels.WARN)
        end
      end,
    },
  })
end

function M._toggle(item)
  if not item then
    return
  end
  M._collapsed[item.id] = not M._collapsed[item.id] or nil
  M._render_panel()
end

--- Take a fixed-duration collapsed-stack capture and render the call tree.
--- `opts.pid` + `opts.dur` skip the prompts (used by the panel's `r` refresh).
---@param opts? { pid: string, dur: string|number }
function M.capture(opts)
  local cmd = M.profiler_cmd()
  if not cmd then
    say("async-profiler launcher not found in $PATH (asprof / profiler.sh)", vim.log.levels.ERROR)
    return
  end

  local function run(pid, dur)
    local tmp_dir = vim.fn.stdpath("cache") .. "/tetravim-profiler"
    vim.fn.mkdir(tmp_dir, "p")
    local out_file = tmp_dir .. "/collapsed_" .. pid .. "_" .. os.time() .. ".txt"
    say(("Profiling PID %s for %ss…"):format(pid, dur), vim.log.levels.INFO)
    vim.system(
      { cmd, "-d", tostring(dur), "-o", "collapsed", "-f", out_file, pid },
      { text = true, timeout = (tonumber(dur) or 30) * 1000 + 30000 },
      function(out)
        vim.schedule(function()
          if out.code == 124 then
            say("Profiler timed out", vim.log.levels.ERROR)
            return
          end
          if out.code ~= 0 or vim.fn.filereadable(out_file) == 0 then
            say("Capture failed: " .. (out.stderr or out.stdout or ""), vim.log.levels.ERROR)
            return
          end
          local lines = vim.fn.readfile(out_file)
          if #lines == 0 then
            say("Capture produced no samples (JVM idle, or needs -e wall)", vim.log.levels.WARN)
            return
          end
          M._tree = build_tree(lines)
          M._collapsed = {}
          M._last_capture = { pid = pid, dur = tostring(dur) }
          M._raw_file = out_file
          M._render_panel()
        end)
      end
    )
  end

  if opts and opts.pid and opts.dur then
    run(opts.pid, opts.dur)
    return
  end

  M.pick_pid(function(pid)
    vim.ui.input({ prompt = "Profile duration (seconds): ", default = "30" }, function(dur)
      if not dur or vim.trim(dur) == "" then
        return
      end
      dur = vim.trim(dur)
      if not dur:match("^%d+$") then
        say("Invalid duration", vim.log.levels.ERROR)
        return
      end
      run(pid, dur)
    end)
  end)
end

return M
