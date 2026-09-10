#!/usr/bin/env bash
# SPEC-3.2: HTTP Client & REST API Explorer -- real-binary steps only.
#
# Module shape, kulala.nvim plugin-spec wiring, the whole OpenAPI-spec ->
# .http generation matrix, the simulated missing-jq guard, <leader>ah keymap
# registration and ftplugin/http.lua settings now live in
# lua/tetravim/tests/http_spec.lua (run by scripts/validate.sh and CI).
#
# What remains here needs a real `jq` binary that the plenary busted
# subprocess cannot rely on: a valid jq filter producing output, jq's own
# stderr being surfaced on a syntax error, and the <leader>ahj end-to-end
# path. Missing `jq` SKIPs (with a note) rather than failing the run.

set -e

echo "=== TetraVim HTTP Client (SPEC-3.2) -- real-binary (jq) steps ==="

if ! command -v jq >/dev/null 2>&1; then
  echo "[1/3] SKIP: jq not installed -- valid-filter functional check skipped."
  echo "[2/3] SKIP: jq not installed -- syntax-error stderr surfacing skipped."
  echo "[3/3] SKIP: jq not installed -- <leader>ahj end-to-end skipped."
  echo ""
  echo "HTTP Client (SPEC-3.2) real-binary steps SKIPPED (no jq)."
  exit 0
fi

echo "[1/3] Functional: jq installed, valid filter -> filtered output delivered via callback..."
nvim -u init.lua --headless -c "lua
local ok, err = pcall(function()
  local http = require('tetravim.util.http')
  local done, result = false, nil
  http.jq_filter('{\"a\":1}', '.a', function(text)
    result = text
    done = true
  end)
  vim.wait(5000, function() return done end, 50)
  assert(done, 'jq_filter callback never fired within 5s')
  assert(vim.trim(result) == '1', 'unexpected filtered result: ' .. vim.inspect(result))
end)
if not ok then
  io.stderr:write('FAIL: ' .. tostring(err) .. '\n')
  vim.cmd('cquit 1')
else
  print('OK: valid jq filter produced the expected filtered output')
end
" -c "qa!"

echo "[2/3] Functional: jq filter syntax error -> jq's own stderr surfaced via ERROR, no crash, callback not invoked..."
nvim -u init.lua --headless -c "lua
local ok, err = pcall(function()
  local notified = {}
  local orig = vim.notify
  vim.notify = function(msg, level) table.insert(notified, { msg = msg, level = level }) end

  local http = require('tetravim.util.http')
  local cb_called = false
  http.jq_filter('{\"a\":1}', 'this is not valid jq (((', function()
    cb_called = true
  end)

  vim.wait(5000, function()
    for _, n in ipairs(notified) do
      if n.level == vim.log.levels.ERROR then return true end
    end
    return false
  end, 50)
  vim.notify = orig

  assert(not cb_called, 'callback must not be invoked on a jq syntax error')
  local saw_err = false
  for _, n in ipairs(notified) do
    if n.level == vim.log.levels.ERROR then saw_err = true end
  end
  assert(saw_err, 'expected an ERROR notification carrying jq stderr for a syntax error')
end)
if not ok then
  io.stderr:write('FAIL: ' .. tostring(err) .. '\n')
  vim.cmd('cquit 1')
else
  print('OK: jq syntax error surfaced via ERROR notification, no crash')
end
" -c "qa!"

echo "[3/3] Functional: <leader>ahj's actual callback jq-filters the current buffer into a real, non-floating split..."
nvim -u init.lua --headless -c "lua
local ok, err = pcall(function()
  require('tetravim.core.keymaps')
  local maps = vim.api.nvim_get_keymap('n')
  local hj = nil
  for _, m in ipairs(maps) do
    if m.lhs:match('ahj\$') then hj = m end
  end
  assert(hj and type(hj.callback) == 'function', '<leader>ahj keymap has no callback function')

  vim.cmd('enew')
  vim.api.nvim_buf_set_lines(0, 0, -1, false, { '{\"a\":1,\"b\":2}' })
  vim.bo.modified = false

  local orig_input = vim.ui.input
  vim.ui.input = function(_, cb) cb('.b') end

  local win_count_before = #vim.api.nvim_list_wins()
  hj.callback()
  vim.wait(5000, function() return #vim.api.nvim_list_wins() > win_count_before end, 20)
  vim.ui.input = orig_input

  assert(#vim.api.nvim_list_wins() > win_count_before, '<leader>ahj must open a new window')
  local win = vim.api.nvim_get_current_win()
  local cfg = vim.api.nvim_win_get_config(win)
  assert(cfg.relative == '', 'result window must be a real split, not floating')

  local buf = vim.api.nvim_win_get_buf(win)
  local text = table.concat(vim.api.nvim_buf_get_lines(buf, 0, -1, false), '\n')
  assert(vim.trim(text) == '2', 'expected filtered result \"2\" in the new split, got: ' .. vim.inspect(text))
end)
if not ok then
  io.stderr:write('FAIL: ' .. tostring(err) .. '\n')
  vim.cmd('cquit 1')
else
  print('OK: <leader>ahj callback opened a real split with the jq-filtered result')
end
" -c "qa!"

echo ""
echo "✔ HTTP Client (SPEC-3.2) real-binary steps PASSED."
echo ""
echo "NOT covered by this script (requires a live kulala-core backend / real"
echo "network request, unavailable in this sandbox) -- verify manually per"
echo "spec-3-2's Verification section:"
echo "  - <leader>ahr executing a request against a live endpoint and"
echo "    kulala.nvim rendering the response in a persistent split"
echo "  - kulala-core's first-run auto-download (triggered by its own setup())"
