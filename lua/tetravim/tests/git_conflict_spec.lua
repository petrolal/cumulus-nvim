-- SPEC-4.1: Advanced Git Conflict Resolution -- static shape + runtime spec.
--
-- Static registration/shape checks live in the first describe block.
-- Runtime behavior (stages 1–7) runs each check in its own fresh
-- `nvim --headless` child process via vim.fn.system() so lazy.nvim loads
-- normally. This file supersedes scripts/validate-4-1.sh (decommissioned).
--
-- NOTE: do NOT require("diffview") at the top level -- plenary's harness
-- never fires lazy load events, and forcing a load corrupts lazy's state.

local assert = require("luassert")

-- Resolve the repo root from this file's own path (not CWD) so io.open()
-- source-text checks work regardless of where the suite is launched from.
local THIS = debug.getinfo(1, "S").source:sub(2)
local REPO_ROOT = vim.fn.fnamemodify(THIS, ":p:h:h:h:h")

local function read_file(rel)
  local fh = assert(io.open(REPO_ROOT .. "/" .. rel, "r"), "could not open " .. rel .. " from repo root " .. REPO_ROOT)
  local src = fh:read("*a")
  fh:close()
  return src
end

describe("SPEC-4.1 Advanced Git Conflict Resolution", function()
  it("tools-diffview.lua declares diffview.nvim lazy on cmd + keys", function()
    local snapshot = package.loaded["diffview"]
    package.loaded["diffview"] = nil

    local spec = require("tetravim.plugins.tools-diffview")
    assert.is_table(spec)
    assert.is_table(spec[1])
    assert.equals("sindrets/diffview.nvim", spec[1][1])

    assert.is_table(spec[1].cmd)
    assert.is_true(vim.tbl_contains(spec[1].cmd, "DiffviewOpen"))
    assert.is_true(vim.tbl_contains(spec[1].cmd, "DiffviewFileHistory"))

    -- opts stays a function so requiring the spec never pulls in diffview.
    assert.is_function(spec[1].opts)
    assert.is_table(spec[1].dependencies)
    assert.is_true(
      vim.tbl_contains(spec[1].dependencies, "nvim-lua/plenary.nvim"),
      "diffview spec must depend on nvim-lua/plenary.nvim"
    )

    assert.is_table(spec[1].keys)
    local by_lhs = {}
    for _, k in ipairs(spec[1].keys) do
      by_lhs[k[1]] = k
    end
    for _, want in ipairs({ "<leader>gco", "<leader>gcq", "<leader>gch", "<leader>gcH", "<leader>gcf" }) do
      assert.is_table(by_lhs[want], "missing golden keymap " .. want)
    end
    assert.equals("x", by_lhs["<leader>gcH"].mode, "<leader>gcH must be a visual-mode (x) keymap")

    -- Every new global keymap sits under <leader>g (frozen boundary).
    for _, k in ipairs(spec[1].keys) do
      assert.truthy(tostring(k[1]):match("^<leader>g"), tostring(k[1]) .. " must live under <leader>g")
    end

    -- Requiring the spec must not eagerly pull in diffview itself.
    assert.is_nil(package.loaded["diffview"])

    package.loaded["diffview"] = snapshot
  end)

  it("configures a 3-way merge_tool layout without calling opts()", function()
    -- opts() require()s diffview.actions, so assert on source text instead.
    -- The spec leaves diff3_mixed vs diff4_mixed free -- do not pin a literal.
    local src = read_file("lua/tetravim/plugins/tools-diffview.lua")
    assert.truthy(src:find("merge_tool", 1, true), "tools-diffview.lua must configure view.merge_tool")
    assert.truthy(src:match('layout%s*=%s*"diff[34]_mixed"'), "merge_tool.layout must be a 3-way diff[34]_mixed layout")
  end)

  it("tetravim.util.git exposes the shared guard + repo-root resolvers", function()
    local git = require("tetravim.util.git")
    assert.is_table(git)
    assert.is_function(git.in_worktree)
    assert.is_function(git.guard)
    assert.is_function(git.repo_root)
    assert.is_function(git.has_commits)
  end)

  it("tools-diffview.lua retires the file-panel picks and confirms whole-file resolution", function()
    local src = read_file("lua/tetravim/plugins/tools-diffview.lua")
    assert.truthy(src:find("file_panel", 1, true), "tools-diffview.lua must define a file_panel keymaps block")
    assert.truthy(
      src:find("vim.fn.confirm", 1, true),
      "whole-file / delete-region resolution must go through vim.fn.confirm"
    )
    assert.truthy(src:find("<leader>gX", 1, true), "whole-file picks must be rebound under <leader>gX")
  end)

  it("which-key keeps <leader>gc global and drops the global <leader>gx group", function()
    local src = read_file("lua/tetravim/plugins/ui-whichkey.lua")
    assert.truthy(src:find('"<leader>gc"', 1, true), "ui-whichkey.lua must register the <leader>gc group")
    assert.truthy(src:find("conflict/compare", 1, true), "the <leader>gc group must be named conflict/compare")
    assert.falsy(
      src:match('{%s*"<leader>gx"%s*,%s*group'),
      "ui-whichkey.lua must NOT register a global <leader>gx group (now buffer-local, from tools-diffview.lua)"
    )
  end)

  it("the healthcheck registers the Advanced Git Conflict Resolution section", function()
    local src = require("tetravim.tests.helpers").health_source(REPO_ROOT)
    assert.truthy(
      src:find("Advanced Git Conflict Resolution", 1, true),
      "the healthcheck must start an 'Advanced Git Conflict Resolution' section"
    )
    assert.truthy(src:find("diffview", 1, true), "the health section must cover diffview.nvim")
    assert.truthy(src:find('executable("git")', 1, true), "the health section must check for the git binary")
  end)
end)

-- ============================================================================
-- Runtime tests (stages 1–7 from validate-4-1.sh)
-- Each test spawns an isolated `nvim --headless` child process.
-- ============================================================================

local THIS_RT = debug.getinfo(1, "S").source:sub(2)
local REPO_ROOT_RT = vim.fn.fnamemodify(THIS_RT, ":p:h:h:h:h")

--- Run code in a headless child nvim; return true on success.
local function headless(code, extra_cmds)
  extra_cmds = extra_cmds or {}
  local cmd = { "nvim", "--headless", "-u", REPO_ROOT_RT .. "/init.lua" }
  for _, c in ipairs(extra_cmds) do
    vim.list_extend(cmd, { "-c", c })
  end
  vim.list_extend(cmd, { "-c", "lua " .. code, "-c", "qa!" })
  vim.fn.system(cmd)
  return vim.v.shell_error == 0
end

--- Build a minimal git repo with a two-branch merge conflict.
--- Returns the temp dir path (caller must rm -rf).
local function make_merge_repo(ours, theirs, base_content)
  base_content = base_content or "alpha\nbeta\ngamma\n"
  ours = ours or "alpha\nOURS\ngamma\n"
  theirs = theirs or "alpha\nTHEIRS\ngamma\n"

  local d = vim.fn.trim(vim.fn.system({ "mktemp", "-d" }))
  local function g(...)
    local args = { "git", "-C", d }
    for _, v in ipairs({ ... }) do
      table.insert(args, v)
    end
    vim.fn.system(args)
  end

  g("init", "-q")
  g("config", "user.email", "tetravim-test@example.com")
  g("config", "user.name", "TetraVim Test")
  g("config", "commit.gpgsign", "false")

  vim.fn.writefile(vim.split(base_content, "\n", { trimempty = false }), d .. "/file.txt")
  g("add", "file.txt")
  g("commit", "-qm", "base")

  local base_branch = vim.fn.trim(vim.fn.system({ "git", "-C", d, "rev-parse", "--abbrev-ref", "HEAD" }))

  g("checkout", "-q", "-b", "feature")
  vim.fn.writefile(vim.split(theirs, "\n", { trimempty = false }), d .. "/file.txt")
  g("commit", "-qam", "feature edit")

  g("checkout", "-q", base_branch)
  vim.fn.writefile(vim.split(ours, "\n", { trimempty = false }), d .. "/file.txt")
  g("commit", "-qam", "base edit")

  vim.fn.system({ "git", "-C", d, "merge", "feature", "-q" })
  -- ignore non-zero (conflict is expected)

  return d
end

describe("SPEC-4.1 Advanced Git Conflict Resolution (runtime / child-nvim)", function()
  local lock_snapshot
  local tmp_dirs = {}

  before_each(function()
    -- Snapshot lazy-lock.json so install side-effects can be reversed.
    local lf = REPO_ROOT_RT .. "/lazy-lock.json"
    local fh = io.open(lf, "r")
    if fh then
      lock_snapshot = fh:read("*a")
      fh:close()
    end
  end)

  after_each(function()
    -- Restore lockfile if a child nvim rewrote it.
    if lock_snapshot then
      local lf = REPO_ROOT_RT .. "/lazy-lock.json"
      local fh = io.open(lf, "w")
      if fh then
        fh:write(lock_snapshot)
        fh:close()
      end
      lock_snapshot = nil
    end
    -- Remove any temp git repos created this test.
    for _, d in ipairs(tmp_dirs) do
      vim.fn.system({ "rm", "-rf", d })
    end
    tmp_dirs = {}
  end)

  -- [1/7] Plugin loads; :Diffview* commands + <leader>gc* keymaps resolve. --
  it(
    "[1/7] diffview.nvim loads; :Diffview* commands + <leader>gc* keymaps resolve; all keys under <leader>g",
    function()
      local code = [==[
local ok, err = pcall(function()
  assert(pcall(require, 'diffview'), 'diffview not resolvable after Lazy! load')
  assert(vim.fn.exists(':DiffviewOpen') == 2, ':DiffviewOpen not registered')
  assert(vim.fn.exists(':DiffviewClose') == 2, ':DiffviewClose not registered')
  assert(vim.fn.exists(':DiffviewFileHistory') == 2, ':DiffviewFileHistory not registered')

  local function mapped(suffix, modes)
    for _, mode in ipairs(modes) do
      for _, m in ipairs(vim.api.nvim_get_keymap(mode)) do
        if m.lhs:gsub('<Space>', ' '):match(suffix .. '$') then return true end
      end
    end
    return false
  end
  assert(mapped('gco', { 'n' }), '<leader>gco (DiffviewOpen) mapping missing')
  assert(mapped('gcq', { 'n' }), '<leader>gcq (DiffviewClose) mapping missing')
  assert(mapped('gch', { 'n' }), '<leader>gch (file history) mapping missing')
  assert(mapped('gcH', { 'x', 'v' }), '<leader>gcH (visual range history) mapping missing')
  assert(mapped('gcf', { 'n' }), '<leader>gcf (toggle files) mapping missing')

  local diffview_spec = require('tetravim.plugins.tools-diffview')[1]
  for _, k in ipairs(diffview_spec.keys) do
    assert(tostring(k[1]):match('^<leader>g'), k[1] .. ' escapes the <leader>g group')
  end
end)
if not ok then io.stderr:write('FAIL: ' .. tostring(err) .. '\n'); vim.cmd('cquit 1') end
]==]
      assert.is_true(
        headless(code, { "Lazy! load diffview.nvim" }),
        "stage 1: diffview.nvim must load cleanly with all Diffview* commands and <leader>gc* keymaps"
      )
    end
  )

  -- [2/7] :checkhealth tetravim reports the Advanced Git Conflict Resolution section. --
  it("[2/7] :checkhealth tetravim reports the Advanced Git Conflict Resolution section", function()
    local code = [==[
local ok, err = pcall(function()
  local out = table.concat(vim.api.nvim_buf_get_lines(0, 0, -1, false), '\n')
  assert(out:find('Advanced Git Conflict Resolution', 1, true), 'health section header missing')
  assert(out:lower():find('diffview', 1, true), 'health section does not mention diffview.nvim')
  assert(out:lower():find('git:', 1, true), 'health section does not report on the git binary')
end)
if not ok then io.stderr:write('FAIL: ' .. tostring(err) .. '\n'); vim.cmd('cquit 1') end
]==]
    assert.is_true(
      headless(code, { "checkhealth tetravim" }),
      "stage 2: :checkhealth tetravim must include Advanced Git Conflict Resolution section mentioning diffview + git"
    )
  end)

  -- [3/7] Outside a git work tree: guard() + <leader>gco callback error; nothing opens. --
  it("[3/7] outside a git work tree, guard() + <leader>gco callback error; nothing opens", function()
    local non_repo = vim.fn.trim(vim.fn.system({ "mktemp", "-d" }))
    table.insert(tmp_dirs, non_repo)

    local code = [==[
local ok, err = pcall(function()
  assert(vim.fn.getcwd():match('/tmp/'), 'precondition: cwd should be the temp non-repo dir')

  local errors = {}
  local orig = vim.notify
  vim.notify = function(msg, level) table.insert(errors, { msg = msg, level = level }) end

  local git = require('tetravim.util.git')
  local tabs_before = #vim.api.nvim_list_tabpages()

  assert(git.guard() == false, 'git.guard() must return false outside a git work tree')

  local gco
  for _, m in ipairs(vim.api.nvim_get_keymap('n')) do
    if m.lhs:gsub('<Space>', ' '):match('gco$') then gco = m end
  end
  assert(gco and type(gco.callback) == 'function', '<leader>gco must have a function callback after load')
  gco.callback()

  vim.notify = orig

  local saw_err = false
  for _, n in ipairs(errors) do
    if n.level == vim.log.levels.ERROR and tostring(n.msg):lower():find('git') then saw_err = true end
  end
  assert(saw_err, 'expected an ERROR notification mentioning git outside a work tree')
  assert(#vim.api.nvim_list_tabpages() == tabs_before, 'nothing must open when the guard fails')
end)
if not ok then io.stderr:write('FAIL: ' .. tostring(err) .. '\n'); vim.cmd('cquit 1') end
]==]
    assert.is_true(
      headless(code, {
        "lua vim.fn.chdir('" .. non_repo .. "')",
        "Lazy! load diffview.nvim",
      }),
      "stage 3: outside a git work tree, guard() must error out and open no tabpage"
    )
  end)

  -- [4a/7] git binary absent: guard() returns false + install/PATH ERROR. --
  it("[4/7a] git reported absent: guard() returns false with install/PATH ERROR", function()
    local patch =
      "vim.fn.executable = (function(o) return function(n) if n == 'git' then return 0 end return o(n) end end)(vim.fn.executable)"
    local code = [==[
local ok, err = pcall(function()
  assert(vim.fn.executable('git') ~= 1, 'precondition: git must report as not executable')

  local errors = {}
  local orig = vim.notify
  vim.notify = function(msg, level) table.insert(errors, { msg = msg, level = level }) end

  local git = require('tetravim.util.git')
  local proceed = git.guard()
  assert(git.in_worktree() == false, 'in_worktree() must be false when git is not executable')

  vim.notify = orig

  assert(proceed == false, 'guard() must return false when git is not executable')
  local hit = false
  for _, e in ipairs(errors) do
    local t = tostring(e.msg):lower()
    if e.level == vim.log.levels.ERROR and (t:find('install') or t:find('path')) then hit = true end
  end
  assert(hit, 'expected an ERROR notification mentioning install/PATH when git is missing')
end)
if not ok then io.stderr:write('FAIL: ' .. tostring(err) .. '\n'); vim.cmd('cquit 1') end
]==]
    assert.is_true(
      headless(code, { "lua " .. patch }),
      "stage 4a: with git absent, guard() must return false and emit an install/PATH ERROR"
    )
  end)

  -- [4b/7] git binary absent: :checkhealth reports git NOT found. --
  it("[4/7b] git reported absent: :checkhealth tetravim reports git NOT found", function()
    local patch =
      "vim.fn.executable = (function(o) return function(n) if n == 'git' then return 0 end return o(n) end end)(vim.fn.executable)"
    local code = [==[
local ok, err = pcall(function()
  local out = table.concat(vim.api.nvim_buf_get_lines(0, 0, -1, false), '\n'):lower()
  assert(out:find('advanced git conflict resolution', 1, true), 'health section missing')
  assert(out:match('git:[^\n]*not found'), 'health must report git as NOT found when unavailable')
end)
if not ok then io.stderr:write('FAIL: ' .. tostring(err) .. '\n'); vim.cmd('cquit 1') end
]==]
    assert.is_true(
      headless(code, { "lua " .. patch, "checkhealth tetravim" }),
      "stage 4b: with git absent, :checkhealth tetravim must report git NOT found"
    )
  end)

  -- [5/7] Real mid-merge repo: <leader>gco opens a diff4_mixed tabpage; <leader>gcq closes it. --
  it("[5/7] mid-merge repo: <leader>gco opens a diff4_mixed merge tabpage; <leader>gcq closes it", function()
    local merge_repo = make_merge_repo()
    table.insert(tmp_dirs, merge_repo)

    local code = [==[
local ok, err = pcall(function()
  local lib = require('diffview.lib')

  local gco, gcq
  for _, m in ipairs(vim.api.nvim_get_keymap('n')) do
    local l = m.lhs:gsub('<Space>', ' ')
    if l:match('gco$') then gco = m end
    if l:match('gcq$') then gcq = m end
  end
  assert(gco and type(gco.callback) == 'function', 'no <leader>gco callback')
  assert(gcq and type(gcq.callback) == 'function', 'no <leader>gcq callback')

  local tabs_before = #vim.api.nvim_list_tabpages()
  gco.callback()
  vim.wait(5000, function() return #vim.api.nvim_list_tabpages() > tabs_before end, 50)
  assert(#vim.api.nvim_list_tabpages() > tabs_before, '<leader>gco callback did not open its own tabpage')
  assert(lib.get_current_view() ~= nil, 'diffview.lib.get_current_view() is nil after <leader>gco')

  for _, win in ipairs(vim.api.nvim_tabpage_list_wins(0)) do
    assert(vim.api.nvim_win_get_config(win).relative == '', 'diffview must render in real splits, not floats')
  end

  local cfg_ok, cfg = pcall(function() return require('diffview.config').get_config() end)
  if cfg_ok and cfg and cfg.view and cfg.view.merge_tool then
    assert(
      cfg.view.merge_tool.layout == 'diff4_mixed',
      'merge_tool.layout must be diff4_mixed, got ' .. tostring(cfg.view.merge_tool.layout)
    )
  else
    assert(#vim.api.nvim_tabpage_list_wins(0) >= 4, 'expected >= 4 windows in the merge tabpage')
  end

  gcq.callback()
  vim.wait(3000, function() return #vim.api.nvim_list_tabpages() == tabs_before end, 50)
  assert(#vim.api.nvim_list_tabpages() == tabs_before, '<leader>gcq callback did not close the diffview tabpage')
end)
if not ok then io.stderr:write('FAIL: ' .. tostring(err) .. '\n'); vim.cmd('cquit 1') end
]==]
    assert.is_true(
      headless(code, {
        "lua vim.fn.chdir('" .. merge_repo .. "')",
        "lua vim.cmd.edit('file.txt')",
        "Lazy! load diffview.nvim",
      }),
      "stage 5: <leader>gco must open a diff4_mixed merge tabpage; <leader>gcq must close it"
    )
  end)

  -- [6/7] <leader>gch (whole file) + <leader>gcH (visual range) open history tabpages, no floats. --
  it("[6/7] <leader>gch and <leader>gcH each open a history tabpage with no floating windows", function()
    local merge_repo = make_merge_repo()
    table.insert(tmp_dirs, merge_repo)

    local code = [==[
local ok, err = pcall(function()
  vim.o.showmode = false
  vim.fn.system({ 'git', 'merge', '--abort' })
  vim.cmd('edit! file.txt')
  local lib = require('diffview.lib')

  local function close_history_cleanly(tabs_before)
    vim.wait(8000, function()
      local v = lib.get_current_view()
      local p = v and v.panel
      return p ~= nil and type(p.entries) == 'table' and #p.entries > 0
    end, 50)
    pcall(vim.api.nvim_clear_autocmds, { group = 'diffview_nvim' })
    pcall(vim.cmd, 'DiffviewClose')
    vim.wait(2000, function() return #vim.api.nvim_list_tabpages() == tabs_before end, 50)
  end

  local function cb(suffix, mode)
    for _, m in ipairs(vim.api.nvim_get_keymap(mode)) do
      if m.lhs:gsub('<Space>', ' '):match(suffix .. '$') then return m.callback end
    end
  end

  local gch = cb('gch', 'n')
  assert(type(gch) == 'function', 'no <leader>gch callback')
  local tabs_before = #vim.api.nvim_list_tabpages()
  gch()
  vim.wait(5000, function() return #vim.api.nvim_list_tabpages() > tabs_before end, 50)
  assert(#vim.api.nvim_list_tabpages() > tabs_before, '<leader>gch callback did not open its own tabpage')
  for _, win in ipairs(vim.api.nvim_tabpage_list_wins(0)) do
    assert(vim.api.nvim_win_get_config(win).relative == '', 'file history must not render in a float')
  end
  close_history_cleanly(tabs_before)

  local gcH = cb('gcH', 'x')
  assert(type(gcH) == 'function', 'no <leader>gcH visual-mode callback')
  vim.cmd('edit! file.txt')
  vim.cmd('silent! normal! ggVG')
  gcH()
  vim.cmd('silent! normal! \27')
  vim.wait(5000, function() return #vim.api.nvim_list_tabpages() > tabs_before end, 50)
  assert(#vim.api.nvim_list_tabpages() > tabs_before, '<leader>gcH callback did not open a range-scoped history tabpage')
  assert(lib.get_current_view() ~= nil, 'no diffview view after <leader>gcH')
  for _, win in ipairs(vim.api.nvim_tabpage_list_wins(0)) do
    assert(vim.api.nvim_win_get_config(win).relative == '', 'range history must not render in a float')
  end
  close_history_cleanly(tabs_before)
end)
if not ok then io.stderr:write('FAIL: ' .. tostring(err) .. '\n'); vim.cmd('cquit 1') end
]==]
    assert.is_true(
      headless(code, {
        "lua vim.fn.chdir('" .. merge_repo .. "')",
        "lua vim.cmd.edit('file.txt')",
        "Lazy! load diffview.nvim",
      }),
      "stage 6: <leader>gch and <leader>gcH must each open a history tabpage with no floating windows"
    )
  end)

  -- [7/7] buffer-local <leader>gx3 / <leader>gX1 resolve regions; no <leader>c*/dx picks. --
  it("[7/7] buffer-local gx3/gX1 resolve conflict regions; merge buffer has no <leader>c*/dx picks", function()
    -- Two distinct conflict regions: OURS-1/THEIRS-1 and OURS-2/THEIRS-2
    local base = "top\nA\nf1\nf2\nf3\nf4\nf5\nf6\nf7\nf8\nB\nbot\n"
    local ours = "top\nOURS-1\nf1\nf2\nf3\nf4\nf5\nf6\nf7\nf8\nOURS-2\nbot\n"
    local theirs = "top\nTHEIRS-1\nf1\nf2\nf3\nf4\nf5\nf6\nf7\nf8\nTHEIRS-2\nbot\n"

    local resolve_repo = make_merge_repo(ours, theirs, base)
    table.insert(tmp_dirs, resolve_repo)

    -- Verify fixture: must have exactly 2 conflict markers.
    local marker_count = tonumber(
      vim.fn.trim(vim.fn.system("grep -c '^<<<<<<<' " .. resolve_repo .. "/file.txt 2>/dev/null || echo 0"))
    ) or 0
    if marker_count ~= 2 then
      -- Single-line diff may coalesce; skip gracefully (setup variance).
      pending("fixture did not produce 2 distinct conflict regions (got " .. marker_count .. "); skipping")
      return
    end

    local code = [==[
local ok, err = pcall(function()
  local lib = require('diffview.lib')

  local function count_markers(buf)
    local n = 0
    for _, l in ipairs(vim.api.nvim_buf_get_lines(buf, 0, -1, false)) do
      if l:match('^<<<<<<<') then n = n + 1 end
    end
    return n
  end

  local function buf_maps(buf)
    local set = {}
    for _, m in ipairs(vim.api.nvim_buf_get_keymap(buf, 'n')) do
      set[m.lhs:gsub('<Space>', ' '):gsub('^ ', '')] = m
    end
    return set
  end

  local gco
  for _, m in ipairs(vim.api.nvim_get_keymap('n')) do
    if m.lhs:gsub('<Space>', ' '):match('gco$') then gco = m end
  end
  assert(gco and type(gco.callback) == 'function', 'no <leader>gco callback')

  local tabs_before = #vim.api.nvim_list_tabpages()
  gco.callback()

  vim.wait(10000, function()
    local v = lib.get_current_view()
    return v ~= nil and v.files ~= nil and v.files.conflicting ~= nil and #v.files.conflicting > 0
  end, 50)

  local view = lib.get_current_view()
  assert(view ~= nil, 'no diffview view after <leader>gco on a mid-merge repo')
  assert(view.files and #view.files.conflicting > 0, 'diffview listed no conflicting files')

  view:set_file(view.files.conflicting[1], true, true)
  vim.wait(10000, function()
    local m = view.cur_layout and view.cur_layout.get_main_win and view.cur_layout:get_main_win()
    if not (m and m.file and m.file.bufnr and vim.api.nvim_buf_is_valid(m.file.bufnr)) then return false end
    if count_markers(m.file.bufnr) ~= 2 then return false end
    return buf_maps(m.file.bufnr)['gx3'] ~= nil
  end, 50)

  local main = view.cur_layout:get_main_win()
  assert(main ~= nil and main:is_valid(), 'merge-tool main (result) window not available')
  local buf = main.file.bufnr
  assert(buf and vim.api.nvim_buf_is_valid(buf), 'merge-tool result buffer is invalid')
  vim.api.nvim_set_current_win(main.id)

  local maps = buf_maps(buf)
  for _, bad in ipairs({ 'co', 'ct', 'cb', 'ca', 'cO', 'cT', 'cB', 'cA', 'dx', 'dX' }) do
    assert(maps[bad] == nil, bad .. ' must NOT be mapped in the merge buffer (frozen boundary)')
  end
  for _, want in ipairs({ 'gx1', 'gx2', 'gx3', 'gxa', 'gx0', 'gX1', 'gXa' }) do
    assert(type(maps[want] and maps[want].callback) == 'function', want .. ' must be a buffer-local mapping')
  end

  local before = count_markers(buf)
  assert(before == 2, 'expected 2 conflict regions, got ' .. tostring(before))

  for i, l in ipairs(vim.api.nvim_buf_get_lines(buf, 0, -1, false)) do
    if l:match('^<<<<<<<') then
      vim.api.nvim_win_set_cursor(main.id, { i, 0 })
      break
    end
  end
  maps['gx3'].callback()
  vim.wait(3000, function() return count_markers(buf) < before end, 50)
  local mid = count_markers(buf)
  assert(mid == before - 1, 'gx3 should drop conflict count by 1 (got ' .. tostring(mid) .. ')')

  maps['gX1'].callback()
  vim.wait(3000, function() return count_markers(buf) == 0 end, 50)
  assert(count_markers(buf) == 0, 'gX1 should clear all remaining conflict markers')

  vim.wait(1500)
  pcall(vim.api.nvim_clear_autocmds, { group = 'diffview_nvim' })
  vim.api.nvim_buf_call(buf, function() vim.cmd('silent write') end)
  pcall(vim.cmd, 'DiffviewClose')
  vim.wait(2000, function() return #vim.api.nvim_list_tabpages() == tabs_before end, 50)
  vim.wait(500)

  local disk = table.concat(vim.fn.readfile('file.txt'), '\n')
  assert(not disk:find('<<<<<<<', 1, true), 'working-tree file still has <<<<<<< markers')
  assert(not disk:find('=======', 1, true), 'working-tree file still has ======= markers')
  assert(not disk:find('>>>>>>>', 1, true), 'working-tree file still has >>>>>>> markers')
  assert(disk:find('THEIRS-1', 1, true), 'region 1 should carry THEIRS content')
  assert(disk:find('OURS-2', 1, true), 'region 2 should carry OURS content')
  assert(not disk:find('OURS-1', 1, true), 'region 1 should NOT retain OURS content')
  assert(not disk:find('THEIRS-2', 1, true), 'region 2 should NOT retain THEIRS content')
end)
if not ok then io.stderr:write('FAIL: ' .. tostring(err) .. '\n'); vim.cmd('cquit 1') end
]==]
    assert.is_true(
      headless(code, {
        "lua vim.fn.chdir('" .. resolve_repo .. "')",
        "lua vim.cmd.edit('file.txt')",
        "Lazy! load diffview.nvim",
      }),
      "stage 7: buffer-local gx3/gX1 must remove conflict markers and write the chosen sides; no <leader>c*/dx picks"
    )
  end)
end)
