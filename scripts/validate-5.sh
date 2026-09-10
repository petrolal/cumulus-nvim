#!/usr/bin/env bash
# EPIC 5: Enterprise Operability -- smoke test
#
# Story 5.1 (Asynchronous LSP Operations & Resilience) and Story 5.2
# (Enterprise Headless Setup & Telemetry). Every assertion runs
# `vim.cmd('cquit 1')` on failure so the exit code is trustworthy. No real
# language-server process is ever started and the network-bound
# `headless-setup.sh` provisioning run is NOT executed here -- only its
# contract is checked.
#
# Covers, without any network or real binary:
#   - util/lsp_resilience.lua: apply_memory_limit (JDTLS heap flags) and the
#     bounded note_exit / make_on_exit auto-restart budget
#   - util/lsp_async.lua: non-blocking request fan-out + get_clients fallback
#   - ftplugin/java.lua: heap limit + on_exit restart wiring
#   - util/ui.lua -> util/notify.lua telemetry routing (all ~20 call sites)
#   - scripts/headless-setup.sh shape; core/health.lua machine-readable JSON
#   - the Story 5.1 / 5.2 :checkhealth sections

set -euo pipefail

echo "=== TetraVim Enterprise Operability (EPIC 5) Smoke Test ==="

echo "[1/5] Unit specs: lsp_resilience_spec + lsp_async_spec + headless_spec..."
nvim --headless -u init.lua -c "lua require('plenary.busted')" -c "PlenaryBustedDirectory lua/tetravim/tests/lsp_resilience_spec.lua" -c "qa"
nvim --headless -u init.lua -c "lua require('plenary.busted')" -c "PlenaryBustedDirectory lua/tetravim/tests/lsp_async_spec.lua" -c "qa"
nvim --headless -u init.lua -c "lua require('plenary.busted')" -c "PlenaryBustedDirectory lua/tetravim/tests/headless_spec.lua" -c "qa"

echo "[2/5] Static: module shape + ftplugin / headless-setup / telemetry wiring present..."
nvim -u init.lua --headless -c "lua
local ok, err = pcall(function()
  local r = require('tetravim.util.lsp_resilience')
  for _, fn in ipairs({ 'apply_memory_limit', 'note_exit', 'reset', 'make_on_exit', 'health' }) do
    assert(type(r[fn]) == 'function', 'util/lsp_resilience.lua missing ' .. fn)
  end
  assert(type(r.JDTLS_MAX_HEAP) == 'string' and type(r.MAX_RESTARTS) == 'number', 'resilience constants missing')

  local a = require('tetravim.util.lsp_async')
  for _, fn in ipairs({ 'request_all_async', 'request_all_sync' }) do
    assert(type(a[fn]) == 'function', 'util/lsp_async.lua missing ' .. fn)
  end

  local ftj = io.open('ftplugin/java.lua', 'r'):read('*a')
  assert(ftj:match('lsp_resilience'), 'ftplugin/java.lua must apply the resilience helpers')
  assert(ftj:match('apply_memory_limit'), 'ftplugin/java.lua must bound the JDTLS heap')
  assert(ftj:match('on_exit'), 'ftplugin/java.lua must wire an on_exit restart handler')

  local refactor_src = io.open('lua/tetravim/util/refactor.lua', 'r'):read('*a')
  assert(refactor_src:match('lsp_async'), 'refactor.lua must dispatch through the async wrapper')

  local ui_src = io.open('lua/tetravim/util/ui.lua', 'r'):read('*a')
  assert(ui_src:match('tetravim%.util%.notify'), 'util/ui.lua must route notifications through util/notify for telemetry')

  local hs = io.open('scripts/headless-setup.sh', 'r'):read('*a')
  assert(hs:match('TETRAVIM_HEADLESS=1'), 'headless-setup.sh must export TETRAVIM_HEADLESS')
  assert(hs:match('%-%-headless'), 'headless-setup.sh must drive nvim --headless')
  assert(hs:match('MasonToolsInstall'), 'headless-setup.sh must provision the Mason tool-chain')
  assert(hs:match('nvim%-treesitter'), 'headless-setup.sh must install Tree-sitter parsers')

  local nt = io.open('lua/tetravim/util/notify.lua', 'r'):read('*a')
  assert(nt:match('telemetry'), 'util/notify.lua must own the telemetry sink')
end)
if not ok then
  io.stderr:write('FAIL: ' .. tostring(err) .. '\n')
  vim.cmd('cquit 1')
else
  print('OK: resilience/async module shape + ftplugin/headless/telemetry wiring present')
end
" -c "qa!"

echo "[3/5] Functional: heap-limit injection + bounded restart budget..."
nvim -u init.lua --headless -c "lua
local ok, err = pcall(function()
  local r = require('tetravim.util.lsp_resilience')

  local cmd = r.apply_memory_limit({ 'jdtls', '-data', '/tmp/ws' }, { xmx = '2g', xms = '512m' })
  assert(vim.tbl_contains(cmd, '--jvm-arg=-Xmx2g'), 'JDTLS launcher must get --jvm-arg=-Xmx2g')
  assert(vim.tbl_contains(cmd, '--jvm-arg=-Xms512m'), 'JDTLS launcher must get --jvm-arg=-Xms512m')

  local raw = r.apply_memory_limit({ 'java', '-jar', 's.jar' }, { xmx = '1g', xms = '256m' })
  assert(vim.tbl_contains(raw, '-Xmx1g'), 'bare java invocation must get raw -Xmx1g')

  local dup = r.apply_memory_limit({ 'jdtls', '--jvm-arg=-Xmx4g' })
  local n = 0
  for _, a in ipairs(dup) do if tostring(a):find('-Xmx', 1, true) then n = n + 1 end end
  assert(n == 1, 'an already-present -Xmx flag must never be duplicated')

  r.reset()
  for i = 1, r.MAX_RESTARTS do
    assert(select(1, r.note_exit('jdtls', 1000 + i)) == 'restart', 'within budget -> restart')
  end
  assert(select(1, r.note_exit('jdtls', 1000 + r.MAX_RESTARTS + 1)) == 'give-up', 'over budget -> give-up')
  assert(select(1, r.note_exit('jdtls', 1000 + r.WINDOW_S + 200)) == 'restart', 'past the window -> budget restored')
  r.reset()
end)
if not ok then
  io.stderr:write('FAIL: ' .. tostring(err) .. '\n')
  vim.cmd('cquit 1')
else
  print('OK: JDTLS heap-limit injection and the bounded auto-restart budget behave correctly')
end
" -c "qa!"

echo "[4/5] Functional: async fan-out never blocks / never strands; telemetry captures util.ui..."
nvim -u init.lua --headless -c "lua
local ok, err = pcall(function()
  local async = require('tetravim.util.lsp_async')
  local orig_get = vim.lsp.get_clients
  local orig_sched = vim.schedule
  vim.schedule = function(fn) fn() end

  vim.lsp.get_clients = function() return {
    { id = 1, request = function(_, _, _, h) h(nil, 'a') return true, 1 end },
    { id = 2, request = function() return false end },
  } end
  local called, got = false, nil
  async.request_all_async(0, 'textDocument/rename', {}, function(res) called = true got = res end)
  assert(called, 'callback must fire even when a client refuses')
  assert(got[1].result == 'a', 'answered client result present')
  assert(got[2] == nil, 'refused client is not stranded')

  vim.lsp.get_clients = function() return {} end
  local empty_called = false
  async.request_all_async(0, 'x', {}, function() empty_called = true end)
  assert(empty_called, 'callback must fire with no clients attached')

  vim.lsp.get_clients = orig_get
  vim.schedule = orig_sched

  -- telemetry: a util.ui notification lands in telemetry.log only once enabled
  local notify = require('tetravim.util.notify')
  local ui = require('tetravim.util.ui')
  local log_path = vim.fn.stdpath('config') .. '/telemetry.log'
  local orig_notify = vim.notify
  vim.notify = function() end

  notify.disable_telemetry()
  local before = vim.fn.filereadable(log_path) == 1 and #vim.fn.readfile(log_path) or 0
  ui.notify_info('validate-5 disabled probe')
  local after = vim.fn.filereadable(log_path) == 1 and #vim.fn.readfile(log_path) or 0
  assert(before == after, 'telemetry is opt-in: nothing written while disabled')

  notify.enable_telemetry()
  local marker = 'validate-5 probe ' .. tostring(os.time()) .. '-' .. tostring(math.random(1, 1e6))
  ui.notify_warn(marker)
  notify.disable_telemetry()
  local hit
  -- The telemetry append is non-blocking (libuv); poll for the line to land.
  vim.wait(2000, function()
    for _, l in ipairs(vim.fn.filereadable(log_path) == 1 and vim.fn.readfile(log_path) or {}) do
      if l:find(marker, 1, true) then hit = vim.json.decode(l) end
    end
    return hit ~= nil
  end)
  assert(hit and hit.level == 'warn', 'util.ui notification must be captured as a warn telemetry line')

  vim.notify = orig_notify
end)
if not ok then
  io.stderr:write('FAIL: ' .. tostring(err) .. '\n')
  vim.cmd('cquit 1')
else
  print('OK: async fan-out is non-blocking / non-stranding and util.ui notifications reach the telemetry sink')
end
" -c "qa!"

echo "[5/5] Functional: machine-readable health JSON + Story 5.1/5.2 checkhealth sections..."
nvim -u init.lua --headless -c "lua
local ok, err = pcall(function()
  local core_health = require('tetravim.core.health')
  local decoded = vim.json.decode(core_health.json())
  for _, k in ipairs({ 'neovim_version', 'lsp_clients', 'plugin_count', 'pending_async_tasks', 'telemetry_enabled' }) do
    assert(decoded[k] ~= nil, ':CheckHealthJson output missing key ' .. k)
  end
  assert(vim.fn.exists(':CheckHealthJson') == 2, ':CheckHealthJson command must be registered')

  local sections = {}
  local orig_start = vim.health.start
  vim.health.start = function(name) table.insert(sections, name) end
  local o1, o2, o3, o4 = vim.health.ok, vim.health.info, vim.health.warn, vim.health.error
  vim.health.ok, vim.health.info, vim.health.warn, vim.health.error = function() end, function() end, function() end, function() end
  pcall(require('tetravim.health').check)
  vim.health.start, vim.health.ok, vim.health.info, vim.health.warn, vim.health.error = orig_start, o1, o2, o3, o4

  local saw_51, saw_52 = false, false
  for _, s in ipairs(sections) do
    if tostring(s):match('5%.1') then saw_51 = true end
    if tostring(s):match('5%.2') then saw_52 = true end
  end
  assert(saw_51, 'health.check must emit a Story 5.1 section')
  assert(saw_52, 'health.check must emit a Story 5.2 section')
end)
if not ok then
  io.stderr:write('FAIL: ' .. tostring(err) .. '\n')
  vim.cmd('cquit 1')
else
  print('OK: machine-readable health JSON and both Epic 5 checkhealth sections in place')
end
" -c "qa!"

echo ""
echo "Enterprise Operability (EPIC 5) smoke test PASSED."
echo ""
echo "NOT covered here (needs a real environment): an end-to-end"
echo "'scripts/headless-setup.sh' provisioning run on a clean box, and a"
echo "live JDTLS crash triggering the bounded auto-restart on a real Java"
echo "project -- verify those manually per each story's Verification section."
