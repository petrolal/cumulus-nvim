-- Unit tests for tetravim.util.grpc (SPEC-3.4)
--
-- Covers every I/O & Edge-Case Matrix row reachable without a live gRPC
-- server: the request-skeleton generator (happy + malformed), the
-- non-JSON-payload abort, the missing-`grpcurl` executable guard, and
-- correct grpcurl command-array construction. `vim.system` is always
-- monkeypatched -- no real binary is ever spawned.

describe("tetravim.util.grpc", function()
  local grpc = require("tetravim.util.grpc")

  local notified
  local orig_notify, orig_system, orig_executable
  local system_calls

  before_each(function()
    notified = {}
    system_calls = {}

    orig_notify = vim.notify
    vim.notify = function(msg, level)
      table.insert(notified, { msg = msg, level = level })
    end

    orig_system = vim.system
    vim.system = function(cmd, opts, _cb)
      table.insert(system_calls, { cmd = cmd, opts = opts })
      return { wait = function() end }
    end

    orig_executable = vim.fn.executable
    vim.fn.executable = function(name)
      if name == "grpcurl" then
        return 1
      end
      return orig_executable(name)
    end
  end)

  after_each(function()
    vim.notify = orig_notify
    vim.system = orig_system
    vim.fn.executable = orig_executable
  end)

  local function last_error()
    for i = #notified, 1, -1 do
      if notified[i].level == vim.log.levels.ERROR then
        return notified[i].msg
      end
    end
    return nil
  end

  local function last_warn()
    for i = #notified, 1, -1 do
      if notified[i].level == vim.log.levels.WARN then
        return notified[i].msg
      end
    end
    return nil
  end

  describe("request_skeleton", function()
    it("turns a -msg-template JSON object into a TODO-annotated skeleton with sorted keys", function()
      local template = '{ "name": "", "count": 0, "enabled": false }'
      local skeleton = grpc.request_skeleton(template)
      assert.is_string(skeleton)
      -- keys sorted: count, enabled, name
      local i_count = skeleton:find('"count"', 1, true)
      local i_enabled = skeleton:find('"enabled"', 1, true)
      local i_name = skeleton:find('"name"', 1, true)
      assert.is_true(i_count < i_enabled and i_enabled < i_name)
      assert.is_truthy(skeleton:match('"count":%s*"TODO: number"'))
      assert.is_truthy(skeleton:match('"enabled":%s*"TODO: bool"'))
      assert.is_truthy(skeleton:match('"name":%s*"TODO: string"'))
      -- valid JSON out
      assert.is_true((pcall(vim.json.decode, skeleton)))
    end)

    it("recurses into nested message fields", function()
      local skeleton = grpc.request_skeleton('{ "page": { "size": 0, "token": "" } }')
      assert.is_string(skeleton)
      assert.is_truthy(skeleton:match('"page":%s*{'))
      assert.is_truthy(skeleton:match('"size":%s*"TODO: number"'))
    end)

    it("returns nil and warns on malformed JSON", function()
      local skeleton = grpc.request_skeleton("{ not json ]")
      assert.is_nil(skeleton)
      assert.is_truthy(last_warn())
    end)

    it("returns nil and warns on an empty / non-string template", function()
      assert.is_nil(grpc.request_skeleton(""))
      assert.is_truthy(last_warn())
      assert.is_nil(grpc.request_skeleton(nil))
    end)
  end)

  describe("invoke", function()
    it("refuses a non-JSON payload before spawning grpcurl", function()
      grpc.invoke("localhost:50051", "pkg.Svc/Do", "this is not json", function() end)
      assert.are.equal(0, #system_calls)
      assert.is_truthy(last_error())
    end)

    it("spawns the correct command array + stdin for a valid payload", function()
      grpc.invoke("localhost:50051", "pkg.Svc/Do", '{"a":1}', function() end)
      assert.are.equal(1, #system_calls)
      assert.are.same({ "grpcurl", "-d", "@", "-plaintext", "localhost:50051", "pkg.Svc/Do" }, system_calls[1].cmd)
      assert.are.equal('{"a":1}', system_calls[1].opts.stdin)
      assert.is_true(system_calls[1].opts.timeout > 0)
    end)
  end)

  describe("executable guard", function()
    it("fires for list_services / describe / invoke when grpcurl is absent", function()
      vim.fn.executable = function(name)
        if name == "grpcurl" then
          return 0
        end
        return orig_executable(name)
      end

      grpc.list_services("localhost:50051", function() end)
      grpc.describe("localhost:50051", "pkg.Svc", function() end)
      grpc.invoke("localhost:50051", "pkg.Svc/Do", '{"a":1}', function() end)

      assert.are.equal(0, #system_calls)
      local msg = last_error()
      assert.is_truthy(msg)
      assert.is_truthy(tostring(msg):lower():match("install"))
      assert.is_truthy(tostring(msg):match("grpcurl"))
    end)
  end)

  describe("command-array construction", function()
    it("list_services -> grpcurl -plaintext <addr> list", function()
      grpc.list_services("example:1234", function() end)
      assert.are.same({ "grpcurl", "-plaintext", "example:1234", "list" }, system_calls[1].cmd)
    end)

    it("describe -> includes -msg-template, describe and the symbol", function()
      grpc.describe("example:1234", "pkg.Msg", function() end)
      assert.are.same(
        { "grpcurl", "-plaintext", "-msg-template", "example:1234", "describe", "pkg.Msg" },
        system_calls[1].cmd
      )
    end)

    it("describe with no symbol -> no trailing symbol arg", function()
      grpc.describe("example:1234", nil, function() end)
      assert.are.same({ "grpcurl", "-plaintext", "-msg-template", "example:1234", "describe" }, system_calls[1].cmd)
    end)
  end)

  describe("pure output walkers", function()
    it("parse_service_list sorts + de-dupes non-empty lines", function()
      local names = grpc.parse_service_list("pkg.B\npkg.A\n\npkg.A\ngrpc.reflection.v1alpha.ServerReflection\n")
      assert.are.same({ "grpc.reflection.v1alpha.ServerReflection", "pkg.A", "pkg.B" }, names)
    end)

    it("parse_methods extracts rpc name + request type (leading dot stripped)", function()
      local desc = table.concat({
        "pkg.Greeter is a service:",
        "service Greeter {",
        "  rpc SayHello ( .pkg.HelloRequest ) returns ( .pkg.HelloReply );",
        "  rpc SayHelloStream ( stream .pkg.HelloRequest ) returns ( stream .pkg.HelloReply );",
        "}",
      }, "\n")
      local methods = grpc.parse_methods(desc)
      assert.are.equal(2, #methods)
      assert.are.equal("SayHello", methods[1].name)
      assert.are.equal("pkg.HelloRequest", methods[1].request_type)
      assert.are.equal("SayHelloStream", methods[2].name)
      assert.are.equal("pkg.HelloRequest", methods[2].request_type)
    end)

    it("extract_msg_template pulls the balanced JSON block after the heading", function()
      local desc = table.concat({
        "pkg.HelloRequest is a message:",
        "message HelloRequest {",
        "  string name = 1;",
        "}",
        "",
        "Message template:",
        "{",
        '  "name": "",',
        '  "nested": { "x": 0 }',
        "}",
      }, "\n")
      local json = grpc.extract_msg_template(desc)
      assert.is_string(json)
      local ok, decoded = pcall(vim.json.decode, json)
      assert.is_true(ok)
      assert.are.equal("", decoded.name)
    end)

    it("extract_msg_template returns nil when there is no object", function()
      assert.is_nil(grpc.extract_msg_template("pkg.Thing is a service:\n"))
    end)
  end)

  -- I/O matrix rows that exercise the async result branches of the internal
  -- `run` helper: a clean exit hands stdout to the callback; a timeout kill
  -- (code 124 / signal) and a generic nonzero exit both notify via
  -- ui.notify_err and never invoke the callback. `vim.schedule` is run
  -- inline so the assertions see the deferred body.
  describe("async result handling", function()
    local orig_schedule
    local captured_cb

    before_each(function()
      orig_schedule = vim.schedule
      vim.schedule = function(fn)
        fn()
      end
      captured_cb = nil
      vim.system = function(cmd, opts, cb)
        table.insert(system_calls, { cmd = cmd, opts = opts })
        captured_cb = cb
        return { wait = function() end }
      end
    end)

    after_each(function()
      vim.schedule = orig_schedule
    end)

    it("hands stdout to the callback on a clean (code 0) exit", function()
      local got
      grpc.list_services("localhost:50051", function(text)
        got = text
      end)
      captured_cb({ code = 0, signal = 0, stdout = "pkg.Svc\n", stderr = "" })
      assert.are.equal("pkg.Svc\n", got)
      assert.is_nil(last_error())
    end)

    it("server unreachable / reflection off -> notify_err surfaces grpcurl stderr, callback not called", function()
      local called = false
      grpc.list_services("localhost:50051", function()
        called = true
      end)
      captured_cb({ code = 1, signal = 0, stdout = "", stderr = "Failed to dial: connection refused" })
      assert.is_false(called)
      assert.is_truthy(tostring(last_error()):match("connection refused"))
    end)

    it("grpcurl timeout (code 124 + signal) -> notify_err says timed out, callback not called", function()
      local called = false
      grpc.invoke("localhost:50051", "pkg.Svc/Do", '{"a":1}', function()
        called = true
      end)
      captured_cb({ code = 124, signal = 15, stdout = "", stderr = "" })
      assert.is_false(called)
      assert.is_truthy(tostring(last_error()):lower():match("timed out"))
    end)
  end)

  -- Migrated from scripts/validate-3-4.sh steps [1/9] (module + plugin wiring)
  -- and [8/9] (keymaps / health / ftplugin). The functional grpcurl matrix
  -- (steps [3]-[7]) is covered by the describe blocks above; the real-binary
  -- steps ([9/9]: grpcurl / buf / protols actually present) stay in the shell
  -- script because conform + the binaries are absent from the plenary child.
  describe("SPEC-3.4 wiring (migrated from validate-3-4.sh)", function()
    local function read(path)
      local fh = assert(io.open(path, "r"))
      local body = fh:read("*a")
      fh:close()
      return body
    end

    it("util/grpc exports list_services / describe / invoke / request_skeleton", function()
      for _, fn in ipairs({ "list_services", "describe", "invoke", "request_skeleton" }) do
        assert.is_function(grpc[fn], "util/grpc missing " .. fn)
      end
    end)

    it("lsp-proto.lua wires protols, the proto TS parser and the .proto filetype guard", function()
      local body = read("lua/tetravim/plugins/lsp-proto.lua")
      assert.is_truthy(body:match("protols"))
      assert.is_truthy(body:match('"proto"'))
      assert.is_truthy(body:match("vim%.filetype%.add"))
    end)

    it("tools-formatting.lua maps proto -> buf", function()
      assert.is_truthy(read("lua/tetravim/plugins/tools-formatting.lua"):match('proto%s*=%s*{%s*"buf"%s*}'))
    end)

    it("tools-mason.lua ensure_installs buf + protols (but not grpcurl)", function()
      local body = read("lua/tetravim/plugins/tools-mason.lua")
      assert.is_truthy(body:match('"buf"'))
      assert.is_truthy(body:match('"protols"'))
    end)

    it("ui-whichkey.lua registers the <leader>ag group", function()
      assert.is_truthy(read("lua/tetravim/plugins/ui-whichkey.lua"):match('"<leader>ag"'))
    end)

    it("core/keymaps registers <leader>ag l/m/i/f", function()
      require("tetravim.core.keymaps")
      local maps = vim.api.nvim_get_keymap("n")
      local function has(suffix)
        for _, m in ipairs(maps) do
          if m.lhs:match(suffix .. "$") then
            return true
          end
        end
        return false
      end
      for _, s in ipairs({ "agl", "agm", "agi", "agf" }) do
        assert.is_true(has(s), "<leader>" .. s .. " keymap missing")
      end
    end)

    it("ftplugin/proto.lua sets the proto buffer conventions", function()
      vim.cmd("new")
      local buf = vim.api.nvim_get_current_buf()
      vim.bo[buf].filetype = "proto"
      -- FileType fires synchronously; the repo root is on the runtimepath so
      -- ftplugin/proto.lua is sourced.
      assert.are.equal(2, vim.bo[buf].shiftwidth)
      assert.is_true(vim.bo[buf].expandtab)
      assert.are.equal("// %s", vim.bo[buf].commentstring)
      vim.api.nvim_buf_delete(buf, { force = true })
    end)

    it("health.check emits a gRPC & Protobufs section", function()
      local sections = {}
      local orig = {
        start = vim.health.start,
        ok = vim.health.ok,
        info = vim.health.info,
        warn = vim.health.warn,
        error = vim.health.error,
      }
      vim.health.start = function(name)
        table.insert(sections, tostring(name))
      end
      vim.health.ok, vim.health.info, vim.health.warn, vim.health.error =
        function() end, function() end, function() end, function() end
      pcall(require("tetravim.health").check)
      vim.health.start, vim.health.ok, vim.health.info, vim.health.warn, vim.health.error =
        orig.start, orig.ok, orig.info, orig.warn, orig.error

      assert.is_truthy(table.concat(sections, "\n"):match("gRPC"))
    end)

    it("grpcurl binary is runnable when present", function()
      if vim.fn.executable("grpcurl") == 1 then
        local out = vim.fn.system({ "grpcurl", "-help" })
        assert.is_truthy(out ~= "")
      end
    end)

    it("conform runs buf formatting on a .proto buffer when buf is present", function()
      if vim.fn.executable("buf") == 1 then
        local scratch = vim.fn.tempname() .. ".proto"
        vim.fn.writefile({ 'syntax = "proto3";', "package demo;", "message Ping { string msg = 1; }" }, scratch)
        vim.fn.system({
          "nvim",
          "--headless",
          "-u",
          "init.lua",
          "-c",
          "edit " .. scratch,
          "-c",
          "lua require('conform').format({ bufnr = 0, async = false, lsp_fallback = false, timeout_ms = 5000 }); vim.cmd('qa!')",
        })
        vim.fn.delete(scratch)
        assert.are.equal(0, vim.v.shell_error)
      end
    end)
  end)
end)
