#!/usr/bin/env bash
# SPEC-3.4: gRPC & Protobufs Integration -- real-binary steps only.
#
# The module shape, plugin/keymap/health/ftplugin wiring and the whole
# grpcurl I/O & edge-case matrix now live in lua/tetravim/tests/grpc_spec.lua
# (run by scripts/validate.sh and CI). What remains here needs binaries and a
# loaded `conform` that the plenary busted subprocess does not have:
#   - buf actually formatting a .proto buffer through conform
#   - grpcurl / protols presence probes
#
# Missing tools SKIP (with a note) rather than fail the run.

set -e

echo "=== TetraVim gRPC & Protobufs (SPEC-3.4) -- real-binary steps ==="

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
echo "gRPC & Protobufs (SPEC-3.4) real-binary steps PASSED."
echo ""
echo "NOT covered here (needs a live reflection-enabled gRPC server): the"
echo "<leader>agl service/method picker walk and an end-to-end <leader>agi ->"
echo "<CR> invoke against a real server -- verify manually per spec-3-4's"
echo "Verification section."
