-- lua/tetravim/tests/notify_layer_spec.lua
--
-- Guard for report finding #9: every subsystem notification must route through
-- the util/ui facade (which forwards to util/notify -- default title + opt-in
-- telemetry sink). Raw `vim.notify(...)` bypasses both, so it is only allowed
-- in the two files that *are* the layer:
--   * lua/tetravim/util/notify.lua -- the base impl + telemetry
--   * lua/tetravim/util/ui.lua     -- the facade's raw fallback when notify.lua
--                                     cannot be required
--
-- This is the `stylua`-independent check the finding asks for. It runs in the
-- busted suite so CI (which gates on the printed summary) catches a regression.

local WHITELIST = {
  ["lua/tetravim/util/notify.lua"] = true,
  ["lua/tetravim/util/ui.lua"] = true,
}

--- Strip `--` line comments (naive: ignores the rare `--` inside a string) so a
--- prose mention of the API in a comment does not trip the guard.
local function decomment(line)
  local i = line:find("%-%-")
  return i and line:sub(1, i - 1) or line
end

local function scan(root, offenders)
  for _, path in ipairs(vim.fn.globpath(root, "**/*.lua", false, true)) do
    local rel = path:gsub("^" .. vim.pesc(vim.fn.getcwd() .. "/"), "")
    if not WHITELIST[rel] and not rel:match("^lua/tetravim/tests/") then
      local fh = io.open(path, "r")
      if fh then
        local lnum = 0
        for line in fh:lines() do
          lnum = lnum + 1
          if decomment(line):find("vim%.notify%s*%(") then
            table.insert(offenders, ("%s:%d"):format(rel, lnum))
          end
        end
        fh:close()
      end
    end
  end
end

describe("notify layer (report finding #9)", function()
  it("no raw vim.notify() outside util/notify.lua and util/ui.lua", function()
    local offenders = {}
    scan("lua/tetravim", offenders)
    assert.are.same(
      {},
      offenders,
      "raw vim.notify() found -- route it through require('tetravim.util.ui').notify_*:\n  "
        .. table.concat(offenders, "\n  ")
    )
  end)
end)
