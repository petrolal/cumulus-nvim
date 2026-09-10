#!/usr/bin/env bash
# SPEC-3.1: Embedded Database Explorer -- cmp-plugin-runtime steps only.
#
# The db.lua module shape, the tools-dadbod.lua plugin-spec wiring
# (nvim-treesitter ensure_installed, init()'s vim.g.dbs assignment + its
# error path, the DirChanged re-discovery autocmd) and the entire
# discover_datasources() parsing / precedence / placeholder / .env /
# malformed-block / encoding matrix now live in
# lua/tetravim/tests/db_spec.lua (run by scripts/validate.sh and CI).
#
# What stays here needs the `cmp` plugin, which the plenary busted
# subprocess has no access to: vim-dadbod-completion's cmp-source
# registration on sql buffers (fresh / re-fired / already-open) and the
# guarantee that it MERGES rather than replaces pre-existing sources.

set -e

echo "=== TetraVim Embedded Database Explorer (SPEC-3.1) -- cmp-source steps ==="

echo "[1/2] Functional: vim-dadbod-completion cmp source registration -- fresh buffer, no duplication on re-fire, and a buffer whose filetype was already sql BEFORE config() ran..."
nvim -u init.lua --headless -c "lua
local ok, err = pcall(function()
  local spec = require('tetravim.plugins.tools-dadbod')
  assert(spec[1] and type(spec[1].config) == 'function', 'plugin spec[1].config missing')

  -- Buffer whose filetype is already 'sql' BEFORE config() runs -- this is
  -- the already-open-buffer coverage gap: the FileType event already fired
  -- once (before any autocmd existed to catch it), so only the 'catch up
  -- already-loaded buffers' loop inside config() can register it.
  local buf_preexisting = vim.api.nvim_create_buf(false, true)
  vim.api.nvim_set_current_buf(buf_preexisting)
  vim.bo[buf_preexisting].filetype = 'sql'

  spec[1].config()

  local cmp = require('cmp')
  local function dadbod_count(bufnr)
    local n = 0
    local sources = vim.api.nvim_buf_call(bufnr, function()
      return cmp.get_config().sources
    end)
    for _, s in ipairs(sources or {}) do
      if s.name == 'vim-dadbod-completion' then n = n + 1 end
    end
    return n
  end

  assert(
    dadbod_count(buf_preexisting) == 1,
    'a buffer already on filetype=sql before config() ran must still get exactly 1 dadbod source, got ' .. dadbod_count(buf_preexisting)
  )

  -- Fresh buffer opened AFTER config() -- covered by the FileType autocmd.
  local buf_fresh = vim.api.nvim_create_buf(false, true)
  vim.api.nvim_set_current_buf(buf_fresh)
  vim.bo[buf_fresh].filetype = 'sql'
  assert(
    dadbod_count(buf_fresh) == 1,
    'a freshly-opened sql buffer must get exactly 1 dadbod source, got ' .. dadbod_count(buf_fresh)
  )

  -- Re-firing FileType on the same buffer (e.g. :e!, filetype re-detection)
  -- must not accumulate duplicate entries.
  vim.api.nvim_exec_autocmds('FileType', { buffer = buf_fresh })
  vim.api.nvim_exec_autocmds('FileType', { buffer = buf_fresh })
  assert(
    dadbod_count(buf_fresh) == 1,
    'refiring FileType must not duplicate the dadbod source, got ' .. dadbod_count(buf_fresh)
  )
end)
if not ok then
  io.stderr:write('FAIL: ' .. tostring(err) .. '\n')
  vim.cmd('cquit 1')
else
  print('OK: cmp source registered exactly once for fresh, re-fired, and already-open sql buffers')
end
" -c "qa!"

echo "[2/2] Functional: cmp source registration MERGES rather than replaces existing sources..."
nvim -u init.lua --headless -c "lua
local ok, err = pcall(function()
  -- Seed a sentinel source into the GLOBAL cmp config (where the project's
  -- real LSP/buffer/snippet sources live), run the plugin's FileType wiring
  -- against a fresh sql buffer, and assert the sentinel SURVIVES alongside
  -- the newly-inserted dadbod source.
  local cmp = require('cmp')
  cmp.setup.global({ sources = { { name = 'cr_sentinel_src' } } })
  vim.cmd('enew')
  local buf = vim.api.nvim_get_current_buf()
  vim.bo[buf].filetype = 'sql'
  require('tetravim.plugins.tools-dadbod')[1].config()
  local srcs = vim.api.nvim_buf_call(buf, function()
    return cmp.get_config().sources
  end)
  local names = {}
  for _, s in ipairs(srcs or {}) do
    names[s.name] = true
  end
  assert(names['vim-dadbod-completion'], 'dadbod cmp source must be registered on the sql buffer, got: ' .. vim.inspect(srcs))
  assert(names['cr_sentinel_src'], 'registration must MERGE -- the pre-existing (global) cmp source must survive, got: ' .. vim.inspect(srcs))
end)
if not ok then
  io.stderr:write('FAIL: ' .. tostring(err) .. '\n')
  vim.cmd('cquit 1')
else
  print('OK: dadbod cmp registration merges (pre-existing source preserved)')
end
" -c "qa!"

echo ""
echo "✔ Embedded Database Explorer (SPEC-3.1) cmp-source steps PASSED."
echo ""
echo "NOT covered by this script (requires a live DBUI session / real DB"
echo "connection, unavailable in this sandbox) -- verify manually per"
echo "spec-3-1's Verification section:"
echo "  - :DBUI actually listing the auto-discovered connection on Neovim startup"
echo "    in a real Spring project"
echo "  - vim-dadbod-completion suggestions appearing alongside LSP/buffer"
echo "    sources when triggering completion in a live .sql buffer with an"
echo "    active DB connection"
echo "  - .sql Treesitter syntax highlighting rendering correctly after"
echo "    ':TSUpdate'/parser install"
