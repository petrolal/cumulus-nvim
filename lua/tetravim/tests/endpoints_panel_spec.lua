-- Endpoints panel (item 14) -- tetravim.util.endpoints_panel + tetravim.util.panel +
-- the OpenAPI spec-discovery / list-endpoints additions to tetravim.util.openapi.
--
-- Behavioural assertions that need an attached Spring Boot LS or a live project
-- scan are NOT exercised here (the busted child has no LSP client and no JVM
-- project); this covers the pure parse/shape surface plus the static wiring.

local function read(path)
  local fh = assert(io.open(path, "r"))
  local body = fh:read("*a")
  fh:close()
  return body
end

local function tmpdir()
  local d = vim.fn.tempname()
  vim.fn.mkdir(d, "p")
  return d
end

local function write(path, body)
  vim.fn.mkdir(vim.fn.fnamemodify(path, ":h"), "p")
  local fh = assert(io.open(path, "w"))
  fh:write(body)
  fh:close()
end

local SPEC = [[
{
  "openapi": "3.0.0",
  "info": { "title": "Demo", "version": "1.0" },
  "paths": {
    "/users": {
      "get": { "operationId": "listUsers", "summary": "List users" },
      "post": { "operationId": "createUser" }
    },
    "/users/{id}": {
      "get": { "operationId": "getUser" },
      "parameters": []
    }
  }
}
]]

describe("tetravim.util.openapi -- spec discovery + endpoint listing", function()
  local openapi = require("tetravim.util.openapi")

  it("exposes discover_specs and list_endpoints", function()
    assert.is_function(openapi.discover_specs)
    assert.is_function(openapi.list_endpoints)
  end)

  it("discover_specs finds conventional JSON spec filenames, skips vendored trees", function()
    local d = tmpdir()
    write(d .. "/openapi.json", SPEC)
    write(d .. "/api/petstore.openapi.json", SPEC)
    write(d .. "/node_modules/dep/swagger.json", SPEC)
    write(d .. "/target/generated/api-docs.json", SPEC)

    local found = openapi.discover_specs(d)
    assert.is_table(found)
    local names = {}
    for _, p in ipairs(found) do
      names[vim.fs.basename(p)] = true
      assert.is_falsy(p:match("/node_modules/"))
      assert.is_falsy(p:match("/target/"))
    end
    assert.is_true(names["openapi.json"])
    assert.is_true(names["petstore.openapi.json"])
  end)

  it("discover_specs is total on bad input", function()
    assert.are.same({}, openapi.discover_specs(nil))
    assert.are.same({}, openapi.discover_specs(""))
    assert.are.same({}, openapi.discover_specs("/no/such/dir/anywhere"))
  end)

  it("list_endpoints flattens paths x methods, skipping non-operation keys", function()
    local d = tmpdir()
    local p = d .. "/openapi.json"
    write(p, SPEC)

    local eps = openapi.list_endpoints(p)
    assert.are.equal(3, #eps) -- GET+POST /users, GET /users/{id}  (parameters key skipped)

    -- sorted by path then method
    assert.are.equal("/users", eps[1].path)
    assert.are.equal("GET", eps[1].http_method)
    assert.are.equal("listUsers", eps[1].operation_id)
    assert.are.equal("List users", eps[1].summary)
    assert.are.equal(p, eps[1].file)
    assert.is_true(eps[1].line >= 1)
    assert.are.equal("openapi", eps[1].source)

    assert.are.equal("POST", eps[2].http_method)
    assert.are.equal("/users/{id}", eps[3].path)
  end)

  it("list_endpoints is total on missing / YAML / non-JSON / pathless input", function()
    assert.are.same({}, openapi.list_endpoints(nil))
    assert.are.same({}, openapi.list_endpoints(""))
    assert.are.same({}, openapi.list_endpoints("/no/such/spec.json"))

    local d = tmpdir()
    write(d .. "/openapi.yaml", "openapi: 3.0.0\n")
    assert.are.same({}, openapi.list_endpoints(d .. "/openapi.yaml"))

    write(d .. "/broken.json", "{ not json ]")
    assert.are.same({}, openapi.list_endpoints(d .. "/broken.json"))
  end)
end)

describe("tetravim.util.panel", function()
  local panel = require("tetravim.util.panel")

  it("exposes render", function()
    assert.is_function(panel.render)
  end)

  it("renders a non-modifiable buffer with header + rows and binds q/r/<CR>", function()
    local selected
    local bufnr = panel.render({
      name_hint = "tetravim-panel-test",
      header = { "H1", "" },
      rows = {
        { text = "row-a", item = { id = "a" } },
        { text = "row-b", item = { id = "b" } },
      },
      refresh = function() end,
      on_select = function(item)
        selected = item
      end,
    })
    assert.is_number(bufnr)
    assert.is_false(vim.bo[bufnr].modifiable)

    local lines = vim.api.nvim_buf_get_lines(bufnr, 0, -1, false)
    assert.are.equal("H1", lines[1])
    assert.are.equal("row-a", lines[3])

    local function has_map(lhs)
      for _, m in ipairs(vim.api.nvim_buf_get_keymap(bufnr, "n")) do
        if m.lhs == lhs then
          return true
        end
      end
      return false
    end
    assert.is_true(has_map("q"))
    assert.is_true(has_map("r"))
    assert.is_true(has_map("<CR>"))

    pcall(vim.api.nvim_buf_delete, bufnr, { force = true })
  end)
end)

describe("tetravim.util.endpoints_panel", function()
  it("exposes open()", function()
    local endpoints = require("tetravim.util.endpoints_panel")
    assert.is_table(endpoints)
    assert.is_function(endpoints.open)
  end)

  it("open() does not throw with no Spring project / no specs in cwd", function()
    assert.has_no.errors(function()
      require("tetravim.util.endpoints_panel").open()
    end)
  end)
end)

describe("Endpoints panel -- static wiring", function()
  it("core/keymaps.lua binds <leader>ae to the endpoints panel", function()
    local body = read("lua/tetravim/core/keymaps.lua")
    assert.is_truthy(body:match('"<leader>ae"'))
    assert.is_truthy(body:match('require%("tetravim%.util%.endpoints_panel"%)%.open'))
    assert.is_truthy(body:match('desc = "Endpoints Panel"'))
  end)

  it("ui-whichkey.lua annotates <leader>ae", function()
    assert.is_truthy(read("lua/tetravim/plugins/ui-whichkey.lua"):match('"<leader>ae".-Endpoints Panel'))
  end)

  it("the healthcheck has the Endpoints Panel section", function()
    assert.is_truthy(require("tetravim.tests.helpers").health_source():match("TetraVim Endpoints Panel"))
  end)

  it("docs/ide-parity.md lists the Endpoints tool window with <leader>ae", function()
    local body = read("docs/ide-parity.md")
    assert.is_truthy(body:match("Endpoints tool window"))
    assert.is_truthy(body:match("<leader>ae"))
  end)
end)
