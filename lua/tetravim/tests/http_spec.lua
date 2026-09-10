-- HTTP Client & REST API Explorer (SPEC-3.2) -- engine + wiring tests.
--
-- Migrated from scripts/validate-http.sh: every step that is pure Lua /
-- filesystem (module shape, kulala.nvim plugin-spec introspection, the whole
-- OpenAPI-spec -> .http generation matrix, the simulated missing-jq guard,
-- <leader>ah keymap registration, ftplugin/http.lua buffer-local settings)
-- now lives here. What stays in the shell script needs a real `jq` binary
-- (valid-filter / syntax-error stderr surfacing) or a live kulala-core
-- backend.

describe("tetravim HTTP client (SPEC-3.2)", function()
  local openapi = require("tetravim.util.openapi")
  local http = require("tetravim.util.http")

  local function read(path)
    local fh = assert(io.open(path, "r"))
    local body = fh:read("*a")
    fh:close()
    return body
  end

  local tmp
  local spec_json, spec_yaml, spec_with_refs, spec_with_server_var, nonexistent_spec

  before_each(function()
    tmp = vim.fn.tempname()
    vim.fn.mkdir(tmp, "p")

    spec_json = tmp .. "/spec.json"
    vim.fn.writefile({
      "{",
      '  "openapi": "3.0.0",',
      '  "servers": [{"url": "https://api.example.com"}],',
      '  "paths": {',
      '    "/users": {',
      '      "get": {"operationId": "listUsers"},',
      '      "post": {"operationId": "createUser"}',
      "    },",
      '    "/users/{id}": {',
      '      "get": {"summary": "Get a user"}',
      "    }",
      "  }",
      "}",
    }, spec_json)

    spec_yaml = tmp .. "/spec.yaml"
    vim.fn.writefile({
      "openapi: 3.0.0",
      "paths:",
      "  /users:",
      "    get:",
      "      operationId: listUsers",
    }, spec_yaml)

    spec_with_refs = tmp .. "/spec-with-refs.json"
    vim.fn.writefile({
      "{",
      '  "openapi": "3.0.0",',
      '  "servers": [{"url": "https://api.example.com"}],',
      '  "paths": {',
      '    "/legacy": {"$ref": "#/components/pathItems/legacy"},',
      '    "/orders": {',
      '      "get": {"operationId": "listOrders"},',
      '      "post": {"$ref": "#/components/x-ops/createOrder"}',
      "    }",
      "  }",
      "}",
    }, spec_with_refs)

    spec_with_server_var = tmp .. "/spec-with-server-var.json"
    vim.fn.writefile({
      "{",
      '  "openapi": "3.0.0",',
      '  "servers": [{"url": "https://{environment}.example.com"}],',
      '  "paths": {',
      '    "/ping": {',
      '      "get": {"operationId": "ping"}',
      "    }",
      "  }",
      "}",
    }, spec_with_server_var)

    nonexistent_spec = tmp .. "/does-not-exist.json"
  end)

  after_each(function()
    pcall(vim.fn.delete, tmp, "rf")
  end)

  local function capture_notify(fn)
    local notified = {}
    local orig = vim.notify
    vim.notify = function(msg, level)
      table.insert(notified, { msg = msg, level = level })
    end
    local ok, result = pcall(fn)
    vim.notify = orig
    assert(ok, result)
    return result, notified
  end

  local function has_warn(notified, pat)
    for _, n in ipairs(notified) do
      local msg = tostring(n.msg):lower()
      if n.level == vim.log.levels.WARN and (not pat or msg:match(pat)) then
        return true
      end
    end
    return false
  end

  describe("module + plugin-spec wiring (static)", function()
    it("openapi/http expose the required entry points", function()
      assert.is_function(openapi.generate_http_from_spec)
      assert.is_function(http.jq_filter)
    end)

    it("tools-http.lua references kulala", function()
      assert.is_truthy(read("lua/tetravim/plugins/tools-http.lua"):match("kulala"))
    end)

    it("kulala.nvim spec forces a persistent split and lazy-loads on ft=http", function()
      local spec = require("tetravim.plugins.tools-http")
      assert.are.equal("mistweaverco/kulala.nvim", spec[1][1])
      assert.is_true(vim.tbl_contains(spec[1].ft, "http"))
      assert.is_table(spec[1].opts)
      assert.is_table(spec[1].opts.ui)
      assert.are.equal("split", spec[1].opts.ui.display_mode)
      assert.is_function(spec[1].config)
    end)
  end)

  describe("generate_http_from_spec", function()
    it("emits one .http request block per operation with method/url/headers", function()
      local text = openapi.generate_http_from_spec(spec_json)
      assert.is_string(text)

      local blocks = 0
      for _ in text:gmatch("HTTP/1%.1") do
        blocks = blocks + 1
      end
      assert.are.equal(3, blocks)

      assert.is_truthy(text:match("GET https://api%.example%.com/users HTTP/1%.1"))
      assert.is_truthy(text:match("POST https://api%.example%.com/users HTTP/1%.1"))
      assert.is_truthy(text:match("GET https://api%.example%.com/users/{id} HTTP/1%.1"))
      assert.is_truthy(text:match("Accept: application/json"))
      assert.is_truthy(text:match("Content%-Type: application/json"))
    end)

    it("skips a whole-path-item $ref and an operation-level $ref, each with a warning", function()
      local text, notified = capture_notify(function()
        return openapi.generate_http_from_spec(spec_with_refs)
      end)

      assert.is_string(text)
      assert.is_truthy(text:match("listOrders"))
      assert.is_falsy(text:match("/legacy"))

      local blocks = 0
      for _ in text:gmatch("HTTP/1%.1") do
        blocks = blocks + 1
      end
      assert.are.equal(1, blocks)

      local saw_path_ref, saw_op_ref = false, false
      for _, n in ipairs(notified) do
        local msg = tostring(n.msg):lower()
        if n.level == vim.log.levels.WARN and msg:match("%$ref") and msg:match("legacy") then
          saw_path_ref = true
        end
        if n.level == vim.log.levels.WARN and msg:match("%$ref") and msg:match("orders") then
          saw_op_ref = true
        end
      end
      assert.is_true(saw_path_ref)
      assert.is_true(saw_op_ref)
    end)

    it("carries an unresolved server-URL {variable} through literally, with a warning", function()
      local text, notified = capture_notify(function()
        return openapi.generate_http_from_spec(spec_with_server_var)
      end)

      assert.is_string(text)
      assert.is_truthy(text:match("GET https://{environment}%.example%.com/ping HTTP/1%.1"))

      local saw = false
      for _, n in ipairs(notified) do
        local msg = tostring(n.msg):lower()
        if n.level == vim.log.levels.WARN and msg:match("template") and msg:match("environment") then
          saw = true
        end
      end
      assert.is_true(saw)
    end)

    it("returns nil with a JSON-only warning for a YAML spec", function()
      local text, notified = capture_notify(function()
        return openapi.generate_http_from_spec(spec_yaml)
      end)
      assert.is_nil(text)
      assert.is_true(has_warn(notified, "json"))
    end)

    it("returns nil with a warning for a missing/unreadable spec", function()
      local text, notified = capture_notify(function()
        return openapi.generate_http_from_spec(nonexistent_spec)
      end)
      assert.is_nil(text)
      assert.is_true(has_warn(notified))
    end)
  end)

  describe("jq_filter", function()
    it("surfaces a clear ERROR with an install hint when jq is missing (simulated)", function()
      local notified = {}
      local orig_notify = vim.notify
      vim.notify = function(msg, level)
        table.insert(notified, { msg = msg, level = level })
      end
      local orig_executable = vim.fn.executable
      vim.fn.executable = function(name)
        if name == "jq" then
          return 0
        end
        return orig_executable(name)
      end

      local cb_called = false
      local ok, err = pcall(function()
        http.jq_filter("{}", ".", function()
          cb_called = true
        end)
      end)

      vim.fn.executable = orig_executable
      vim.notify = orig_notify
      assert(ok, err)

      assert.is_false(cb_called)
      local msg
      for _, n in ipairs(notified) do
        if n.level == vim.log.levels.ERROR then
          msg = n.msg
        end
      end
      assert.is_not_nil(msg)
      assert.is_truthy(tostring(msg):lower():match("install"))
    end)
  end)

  describe("<leader>ah keymap group", function()
    it("registers run / generate-from-OpenAPI / jq-filter", function()
      require("tetravim.core.keymaps")
      local maps = vim.api.nvim_get_keymap("n")
      local function find(suffix)
        for _, m in ipairs(maps) do
          if m.lhs:match(suffix .. "$") then
            return m
          end
        end
        return nil
      end
      assert.is_not_nil(find("ahr"))
      assert.is_not_nil(find("aho"))
      assert.is_not_nil(find("ahj"))
    end)

    it("<leader>aho generates .http content into a real (non-floating) split with filetype=http", function()
      require("tetravim.core.keymaps")
      local maps = vim.api.nvim_get_keymap("n")
      local ho
      for _, m in ipairs(maps) do
        if m.lhs:match("aho$") then
          ho = m
        end
      end
      assert.is_function(ho and ho.callback)

      local orig_input = vim.ui.input
      vim.ui.input = function(_, cb)
        cb(spec_json)
      end

      local win_count_before = #vim.api.nvim_list_wins()
      local ok, err = pcall(ho.callback)
      vim.wait(5000, function()
        return #vim.api.nvim_list_wins() > win_count_before
      end, 20)
      vim.ui.input = orig_input
      assert(ok, err)

      assert.is_true(#vim.api.nvim_list_wins() > win_count_before)
      local win = vim.api.nvim_get_current_win()
      assert.are.equal("", vim.api.nvim_win_get_config(win).relative)

      local buf = vim.api.nvim_win_get_buf(win)
      assert.are.equal("http", vim.bo[buf].filetype)
      local text = table.concat(vim.api.nvim_buf_get_lines(buf, 0, -1, false), "\n")
      assert.is_truthy(text:match("GET https://api%.example%.com/users HTTP/1%.1"))
    end)
  end)

  describe("ftplugin/http.lua", function()
    it("applies buffer-local settings to a .http buffer", function()
      vim.cmd("new")
      local buf = vim.api.nvim_get_current_buf()
      vim.bo[buf].filetype = "http"

      assert.are.equal("http", vim.bo[buf].filetype)
      assert.are.equal(2, vim.bo[buf].shiftwidth)
      assert.is_true(vim.bo[buf].expandtab)
      assert.are.equal("# %s", vim.bo[buf].commentstring)

      local src = read("ftplugin/http.lua")
      assert.is_truthy(src:match("comments%s*="))
      assert.is_truthy(src:match("###"))
      assert.is_truthy(src:match("[^#]#[^#]"))

      vim.api.nvim_buf_delete(buf, { force = true })
    end)
  end)
end)
