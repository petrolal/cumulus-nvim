-- TetraVim dashboard building blocks.
--
-- Carved out of lua/tetravim/plugins/editor-snacks.lua so the plugin spec stays
-- a declarative list of `opts`/`keys` and the imperative bits (a git-sha reader
-- that must not shell out, a footer section builder) live here as plain,
-- testable functions.

local M = {}

-- Short commit hash for the dashboard footer, resolved at most once per
-- session. The previous implementation shelled out via io.popen("git
-- rev-parse ...") inside the dashboard section closure, which runs on every
-- dashboard render -- a synchronous subprocess spawn at the most
-- latency-sensitive moment of startup -- and io.popen is compiled out or
-- disabled in some locked-down enterprise builds. Read .git directly
-- instead: no subprocess, and a missing/unreadable repo just yields "".
local _git_sha_cache

function M.git_short_sha()
  if _git_sha_cache ~= nil then
    return _git_sha_cache
  end
  _git_sha_cache = ""

  local git_dir = vim.fn.stdpath("config") .. "/.git"
  local head = (vim.fn.filereadable(git_dir .. "/HEAD") == 1) and vim.fn.readfile(git_dir .. "/HEAD")[1] or nil
  if not head then
    return _git_sha_cache
  end

  local full
  local ref = head:match("^ref:%s+(.+)$")
  if ref then
    if vim.fn.filereadable(git_dir .. "/" .. ref) == 1 then
      full = vim.fn.readfile(git_dir .. "/" .. ref)[1]
    end
    if not full and vim.fn.filereadable(git_dir .. "/packed-refs") == 1 then
      for _, line in ipairs(vim.fn.readfile(git_dir .. "/packed-refs")) do
        local sha, name = line:match("^(%x+)%s+(.+)$")
        if name == ref then
          full = sha
          break
        end
      end
    end
  else
    -- Detached HEAD: the file holds the raw commit hash.
    full = head:match("^(%x+)")
  end

  _git_sha_cache = (full and full:sub(1, 7)) or ""
  return _git_sha_cache
end

--- Snacks dashboard section: centered "TETRAVIM • vX • <sha> • <date>" footer.
---@return table
function M.footer_section()
  local commit = M.git_short_sha()
  local date = os.date("%d/%m/%y")
  local version = "v1.0.0"
  local parts = { "TETRAVIM", version }
  if commit ~= "" then
    parts[#parts + 1] = commit
  end
  parts[#parts + 1] = date
  return {
    align = "center",
    text = {
      {
        table.concat(parts, " • "),
        hl = "SnacksDashboardFooter",
      },
    },
  }
end

return M
