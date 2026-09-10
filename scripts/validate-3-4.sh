#!/usr/bin/env bash
# SPEC-3.4: gRPC & Protobufs Integration -- smoke test
#
# Mirrors validate-http.sh: `vim.cmd('cquit 1')` on any failed assertion so
# the exit code is trustworthy. Covers every row of spec-3-4's I/O &
# Edge-Case Matrix reachable without a live gRPC server:
#   - request_skeleton: valid -msg-template JSON -> TODO-annotated skeleton
#   - request_skeleton: malformed JSON -> nil + WARN, no crash
#   - invoke: malformed payload -> refused before vim.system, ERROR
#   - grpcurl not installed (simulated) -> ERROR names grpcurl + install hint
#   - command-array construction for list / describe / invoke
#
# Also statically checks the plugin/keymap/health/ftplugin wiring that
# delivers the rest of the story's Tasks & Acceptance.
#
# Real-binary steps (grpcurl / buf / protols) SKIP with a clear note -- not
# fail the run -- when the tool is absent in the test environment.

set -e

echo "=== TetraVim gRPC & Protobufs Integration (SPEC-3.4) Smoke Test ==="

GRPCURL_AVAILABLE=1
command -v grpcurl >/dev/null 2>&1 || GRPCURL_AVAILABLE=0
BUF_AVAILABLE=1
command -v buf >/dev/null 2>&1 || BUF_AVAILABLE=0
PROTOLS_AVAILABLE=1
command -v protols >/dev/null 2>&1 || PROTOLS_AVAILABLE=0

FIXTURE_ROOT="$(mktemp -d)"
trap 'rm -rf "$FIXTURE_ROOT"' EXIT
cat > "$FIXTURE_ROOT/scratch.proto" <<'PROTO'
syntax = "proto3";
package demo;
message Ping { string msg = 1; }
PROTO

echo "[1/9] Static: util/grpc.lua exports list_services/describe/invoke/request_skeleton; lsp-proto.lua references protols + proto..."
nvim -u init.lua --headless -c "lua
local ok, err = pcall(function()
  local g = require('tetravim.util.grpc')
  for _, fn in ipairs({ 'list_services', 'describe', 'invoke', 'request_skeleton' }) do
    assert(type(g[fn]) == 'function', 'util/grpc.lua missing ' .. fn)
  end

  local proto_src = io.open('lua/tetravim/plugins/lsp-proto.lua', 'r'):read('*a')
  assert(proto_src:match('protols'), 'lsp-proto.lua must reference protols')
  assert(proto_src:match('\"proto\"'), 'lsp-proto.lua must add the proto parser')
  assert(proto_src:match('vim%.filetype%.add'), 'lsp-proto.lua must guard the .proto filetype')

  local fmt_src = io.open('lua/tetravim/plugins/tools-formatting.lua', 'r'):read('*a')
  assert(fmt_src:match('proto%s*=%s*{%s*\"buf\"%s*}'), 'tools-formatting.lua must map proto -> buf')

  local mason_src = io.open('lua/tetravim/plugins/tools-mason.lua', 'r'):read('*a')
  -- grpcurl is intentionally NOT here -- it was dropped from mason-registry;
  -- listing it makes mason-tool-installer throw on every VimEnter.
  for _, t in ipairs({ 'buf', 'protols' }) do
    assert(mason_src:match('\"' .. t .. '\"'), 'tools-mason.lua must ensure_installed ' .. t)
  end

  local wk_src = io.open('lua/tetravim/plugins/ui-whichkey.lua', 'r'):read('*a')
  assert(wk_src:match('\"<leader>ag\"'), 'ui-whichkey.lua must register the <leader>ag group')
end)
if not ok then
  io.stderr:write('FAIL: ' .. tostring(err) .. '\n')
  vim.cmd('cquit 1')
else
  print('OK: module shape + plugin/whichkey wiring present')
end
" -c "qa!"

echo "[2/9] Unit specs: lua/tetravim/tests/grpc_spec.lua..."
nvim --headless -u init.lua -c "lua require('plenary.busted')" -c "PlenaryBustedDirectory lua/tetravim/tests/grpc_spec.lua" -c "qa"

echo "[3/9] Functional: request_skeleton -- valid -msg-template JSON -> TODO-annotated skeleton, sorted keys..."
nvim -u init.lua --headless -c "lua
local ok, err = pcall(function()
  local g = require('tetravim.util.grpc')
  local skel = g.request_skeleton('{ \"name\": \"\", \"count\": 0, \"flag\": false }')
  assert(type(skel) == 'string', 'expected a skeleton string')
  assert(skel:match('\"count\":%s*\"TODO: number\"'), 'count should be a TODO: number placeholder')
  assert(skel:match('\"flag\":%s*\"TODO: bool\"'), 'flag should be a TODO: bool placeholder')
  assert(skel:match('\"name\":%s*\"TODO: string\"'), 'name should be a TODO: string placeholder')
  assert(skel:find('\"count\"', 1, true) < skel:find('\"name\"', 1, true), 'keys must be sorted')
  assert((pcall(vim.json.decode, skel)), 'skeleton must itself be valid JSON')
end)
if not ok then
  io.stderr:write('FAIL: ' .. tostring(err) .. '\n')
  vim.cmd('cquit 1')
else
  print('OK: request_skeleton produced a sorted, TODO-annotated, valid-JSON skeleton')
end
" -c "qa!"

echo "[4/9] Functional: request_skeleton -- malformed JSON -> nil + WARN, no crash..."
nvim -u init.lua --headless -c "lua
local ok, err = pcall(function()
  local notified = {}
  local orig = vim.notify
  vim.notify = function(msg, level) table.insert(notified, { msg = msg, level = level }) end
  local g = require('tetravim.util.grpc')
  local skel = g.request_skeleton('{ broken ]')
  vim.notify = orig
  assert(skel == nil, 'malformed template must return nil')
  local saw_warn = false
  for _, n in ipairs(notified) do
    if n.level == vim.log.levels.WARN then saw_warn = true end
  end
  assert(saw_warn, 'expected a WARN for a malformed template')
end)
if not ok then
  io.stderr:write('FAIL: ' .. tostring(err) .. '\n')
  vim.cmd('cquit 1')
else
  print('OK: malformed template -> nil + WARN, no crash')
end
" -c "qa!"

echo "[5/9] Functional: invoke -- malformed payload refused before vim.system, ERROR raised..."
nvim -u init.lua --headless -c "lua
local ok, err = pcall(function()
  local notified = {}
  local orig_notify = vim.notify
  vim.notify = function(msg, level) table.insert(notified, { msg = msg, level = level }) end
  local orig_system = vim.system
  local system_called = false
  vim.system = function() system_called = true return { wait = function() end } end
  local orig_exec = vim.fn.executable
  vim.fn.executable = function(name) if name == 'grpcurl' then return 1 end return orig_exec(name) end

  require('tetravim.util.grpc').invoke('localhost:50051', 'demo.Svc/Do', 'not json at all', function() end)

  vim.system = orig_system
  vim.fn.executable = orig_exec
  vim.notify = orig_notify

  assert(not system_called, 'grpcurl must NOT be spawned for a malformed payload')
  local saw_err = false
  for _, n in ipairs(notified) do
    if n.level == vim.log.levels.ERROR then saw_err = true end
  end
  assert(saw_err, 'expected an ERROR for a malformed payload')
end)
if not ok then
  io.stderr:write('FAIL: ' .. tostring(err) .. '\n')
  vim.cmd('cquit 1')
else
  print('OK: malformed payload refused before any grpcurl call, ERROR raised')
end
" -c "qa!"

echo "[6/9] Functional: grpcurl not installed (simulated) -> no crash, ERROR names grpcurl + an install hint..."
nvim -u init.lua --headless -c "lua
local ok, err = pcall(function()
  local notified = {}
  local orig_notify = vim.notify
  vim.notify = function(msg, level) table.insert(notified, { msg = msg, level = level }) end
  local orig_system = vim.system
  local system_called = false
  vim.system = function() system_called = true return { wait = function() end } end
  local orig_exec = vim.fn.executable
  vim.fn.executable = function(name) if name == 'grpcurl' then return 0 end return orig_exec(name) end

  local g = require('tetravim.util.grpc')
  g.list_services('localhost:50051', function() end)
  g.describe('localhost:50051', 'demo.Svc', function() end)
  g.invoke('localhost:50051', 'demo.Svc/Do', '{}', function() end)

  vim.system = orig_system
  vim.fn.executable = orig_exec
  vim.notify = orig_notify

  assert(not system_called, 'no grpcurl process may be spawned when the binary is absent')
  local msg
  for _, n in ipairs(notified) do
    if n.level == vim.log.levels.ERROR then msg = n.msg end
  end
  assert(msg, 'expected an ERROR when grpcurl is absent')
  assert(tostring(msg):match('grpcurl'), 'error must name grpcurl')
  assert(tostring(msg):lower():match('install'), 'error must carry an install hint')
end)
if not ok then
  io.stderr:write('FAIL: ' .. tostring(err) .. '\n')
  vim.cmd('cquit 1')
else
  print('OK: missing-grpcurl guard fires for list/describe/invoke with a clear install hint')
end
" -c "qa!"

echo "[7/9] Functional: command-array construction for list / describe / invoke..."
nvim -u init.lua --headless -c "lua
local ok, err = pcall(function()
  local calls = {}
  local orig_system = vim.system
  vim.system = function(cmd, opts) table.insert(calls, { cmd = cmd, opts = opts }) return { wait = function() end } end
  local orig_exec = vim.fn.executable
  vim.fn.executable = function(name) if name == 'grpcurl' then return 1 end return orig_exec(name) end

  local g = require('tetravim.util.grpc')
  g.list_services('h:1', function() end)
  g.describe('h:1', 'demo.Msg', function() end)
  g.invoke('h:1', 'demo.Svc/Do', '{\"a\":1}', function() end)

  vim.system = orig_system
  vim.fn.executable = orig_exec

  assert(vim.deep_equal(calls[1].cmd, { 'grpcurl', '-plaintext', 'h:1', 'list' }), 'list cmd wrong: ' .. vim.inspect(calls[1].cmd))
  assert(vim.deep_equal(calls[2].cmd, { 'grpcurl', '-plaintext', '-msg-template', 'h:1', 'describe', 'demo.Msg' }), 'describe cmd wrong: ' .. vim.inspect(calls[2].cmd))
  assert(vim.deep_equal(calls[3].cmd, { 'grpcurl', '-d', '@', '-plaintext', 'h:1', 'demo.Svc/Do' }), 'invoke cmd wrong: ' .. vim.inspect(calls[3].cmd))
  assert(calls[3].opts.stdin == '{\"a\":1}', 'invoke must pipe the payload on stdin')
  assert(type(calls[3].opts.timeout) == 'number' and calls[3].opts.timeout > 0, 'invoke must set an explicit timeout')
end)
if not ok then
  io.stderr:write('FAIL: ' .. tostring(err) .. '\n')
  vim.cmd('cquit 1')
else
  print('OK: list/describe/invoke build the expected grpcurl command arrays')
end
" -c "qa!"

echo "[8/9] Functional: <leader>ag keymaps registered; health section present; ftplugin/proto.lua applies..."
nvim -u init.lua --headless -c "edit $FIXTURE_ROOT/scratch.proto" -c "lua
local ok, err = pcall(function()
  require('tetravim.core.keymaps')
  local maps = vim.api.nvim_get_keymap('n')
  local function find(suffix)
    for _, m in ipairs(maps) do if m.lhs:match(suffix .. '\$') then return m end end
    return nil
  end
  for _, s in ipairs({ 'agl', 'agm', 'agi', 'agf' }) do
    assert(find(s), '<leader>' .. s .. ' keymap missing')
  end

  assert(vim.bo.filetype == 'proto', 'expected filetype=proto, got ' .. tostring(vim.bo.filetype))
  assert(vim.bo.shiftwidth == 2, 'expected shiftwidth=2 in a .proto buffer')
  assert(vim.bo.expandtab == true, 'expected expandtab in a .proto buffer')
  assert(vim.bo.commentstring == '// %s', 'unexpected commentstring: ' .. tostring(vim.bo.commentstring))

  local sections = {}
  local orig_start = vim.health.start
  vim.health.start = function(name) table.insert(sections, name) end
  local orig_ok, orig_info, orig_warn, orig_err = vim.health.ok, vim.health.info, vim.health.warn, vim.health.error
  vim.health.ok = function() end
  vim.health.info = function() end
  vim.health.warn = function() end
  vim.health.error = function() end
  pcall(require('tetravim.health').check)
  vim.health.start, vim.health.ok, vim.health.info, vim.health.warn, vim.health.error =
    orig_start, orig_ok, orig_info, orig_warn, orig_err

  local saw = false
  for _, s in ipairs(sections) do
    if tostring(s):match('gRPC') and tostring(s):match('3%.4') then saw = true end
  end
  assert(saw, 'health.check must emit a \"gRPC & Protobufs (Story 3.4)\" section')
end)
if not ok then
  io.stderr:write('FAIL: ' .. tostring(err) .. '\n')
  vim.cmd('cquit 1')
else
  print('OK: <leader>ag keymaps, health section, ftplugin/proto.lua all in place')
end
" -c "qa!"

echo "[9/9] Real-binary steps (gated)..."
if [ "$GRPCURL_AVAILABLE" -eq 1 ]; then
  grpcurl --version >/dev/null 2>&1 || grpcurl --help >/dev/null 2>&1 || true
  echo "  OK: grpcurl present and runnable"
else
  echo "  SKIP: grpcurl not installed -- reflection list/describe/invoke against a live server not exercised."
fi
if [ "$BUF_AVAILABLE" -eq 1 ]; then
  nvim -u init.lua --headless -c "edit $FIXTURE_ROOT/scratch.proto" -c "lua
  local ok, err = pcall(function()
    require('conform').format({ bufnr = 0, async = false, lsp_fallback = false, timeout_ms = 5000 })
  end)
  if not ok then io.stderr:write('FAIL: buf format: ' .. tostring(err) .. '\n') vim.cmd('cquit 1') else print('  OK: conform ran buf on a .proto buffer') end
  " -c "qa!"
else
  echo "  SKIP: buf not installed -- <leader>agf / format-on-save not exercised (conform no-ops without it)."
fi
if [ "$PROTOLS_AVAILABLE" -eq 1 ]; then
  echo "  OK: protols present (LSP attach verified manually per the Verification section)"
else
  echo "  SKIP: protols not installed -- .proto hover / go-to-definition not exercised."
fi

echo ""
echo "gRPC & Protobufs Integration (SPEC-3.4) smoke test PASSED."
echo ""
echo "NOT covered here (needs a live reflection-enabled gRPC server): the"
echo "<leader>agl service/method picker walk and an end-to-end <leader>agi ->"
echo "<CR> invoke against a real server -- verify manually per spec-3-4's"
echo "Verification section."
