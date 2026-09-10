-- TetraVim Git Work-Tree Guard (SPEC-4.1 / SPEC-4.1 review remediation)
--
-- Shared entry-point guard for the git conflict/compare feature cluster.
-- Every <leader>gc* keymap in tools-diffview.lua runs M.guard() first so a
-- missing `git` binary or a non-repo buffer produces one clear notification
-- (never a raw stacktrace). Story 4.2 reuses this same guard, and
-- M.repo_root(bufnr), for its forge commands.
--
-- The per-keystroke path is PURE LUA: `vim.fs.root` walks the buffer's
-- directory tree for a `.git` dir OR a `.git` gitfile -- no subprocess, no
-- `:wait()`, so a hung or pathologically slow `git` can never freeze a
-- keymap press (epic-4 "no editor freeze" NFR). Only the deliberate history
-- precheck (M.has_commits) and `:checkhealth` may shell out, each with a
-- short timeout, since those are explicit git operations, not a guard.

local ui = require("tetravim.util.ui")

local M = {}

-- Upper bound on the one deliberate `git rev-parse --verify HEAD` probe used
-- by the history path (M.has_commits). Mirrors tetravim.util.clients.http's
-- JQ_TIMEOUT_MS pattern so a hung git can never wedge the history keymap.
local PROBE_TIMEOUT_MS = 2000

--- Resolve the git repo root for a buffer, buffer-first: walk up from the
--- buffer's own file (so a buffer under repo A resolves to repo A even when
--- Neovim's cwd is repo B), falling back to Neovim's cwd for unnamed /
--- scratch buffers. Pure Lua -- `vim.fs.root` matches either a `.git`
--- directory or a `.git` gitfile (worktrees / submodules). Returns nil when
--- neither the buffer's path nor the cwd sits inside a work tree.
---@param bufnr? integer
---@return string|nil
function M.repo_root(bufnr)
  local name = vim.api.nvim_buf_get_name(bufnr or 0)
  local start = (name ~= "" and vim.fs.dirname(name)) or vim.fn.getcwd()
  return vim.fs.root(start, ".git")
end

--- Whether the current buffer sits inside a git work tree. Pure Lua, no
--- subprocess: true iff M.repo_root() resolves.
---@param bufnr? integer
---@return boolean
function M.in_worktree(bufnr)
  return vim.fn.executable("git") == 1 and M.repo_root(bufnr) ~= nil
end

--- Whether `root` has at least one commit (a born HEAD). Used only by the
--- deliberate file-history precheck -- a fresh `git init` repo has an unborn
--- HEAD and `:DiffviewFileHistory` would otherwise surface a raw error.
--- One short, timeout-bounded `git` call; returns false (never errors) on a
--- missing binary, a timeout, or any non-zero exit.
---@param root string
---@return boolean
function M.has_commits(root)
  if type(root) ~= "string" or root == "" or vim.fn.executable("git") ~= 1 then
    return false
  end
  local ok, res = pcall(function()
    return vim
      .system({ "git", "-C", root, "rev-parse", "--verify", "--quiet", "HEAD" }, { text = true, timeout = PROBE_TIMEOUT_MS })
      :wait()
  end)
  if not ok or type(res) ~= "table" or type(res.code) ~= "number" then
    return false
  end
  return res.code == 0
end

--- Guard a git conflict/compare entry point. Returns true when it is safe to
--- proceed; otherwise emits a condition-specific ui notification and returns
--- false. Every message names its ACTUAL condition -- missing `git` vs. not a
--- work tree -- never a blanket "Not a git repository".
---@param bufnr? integer
---@return boolean
function M.guard(bufnr)
  if vim.fn.executable("git") ~= 1 then
    ui.notify_err(
      "`git` is not installed or not on $PATH. Install git (e.g. `apt install git`, `brew install git`, "
        .. "`pacman -S git`) to use the conflict/compare commands."
    )
    return false
  end

  if not M.repo_root(bufnr) then
    ui.notify_err(
      "Not inside a git work tree -- this buffer's file is not under a git repository "
        .. "(`git init`, or open a file inside one)."
    )
    return false
  end

  return true
end

return M
