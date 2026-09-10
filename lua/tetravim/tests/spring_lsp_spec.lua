-- lua/tetravim/tests/spring_lsp_spec.lua
--
-- Covers tetravim.util.jvm.spring_lsp -- the Spring Boot LS `workspace/symbol`
-- bridge tetravim.util.jvm.spring prefers over its ripgrep/Tree-sitter scan when the
-- STS4 server is attached. The live-client paths degrade to cb(nil); only the
-- pure `workspace/symbol` name parsers are unit-tested here.

local sl = require("tetravim.util.jvm.spring_lsp")

describe("tetravim.util.jvm.spring_lsp", function()
  describe("parse_endpoint_symbol", function()
    it('verb baked into the annotation: @GetMapping("/greeting")', function()
      local ep = sl.parse_endpoint_symbol('@GetMapping("/greeting")')
      assert.are.equal("GET", ep.http_method)
      assert.are.equal("/greeting", ep.path)
    end)

    it("@PostMapping with extra attributes still parses", function()
      local ep = sl.parse_endpoint_symbol('@PostMapping("/api/users",produces="application/json")')
      assert.are.equal("POST", ep.http_method)
      assert.are.equal("/api/users", ep.path)
    end)

    it("@RequestMapping with no verb -> ANY", function()
      local ep = sl.parse_endpoint_symbol('@RequestMapping("/base")')
      assert.are.equal("ANY", ep.http_method)
      assert.are.equal("/base", ep.path)
    end)

    it("older `@<path> -- GET,POST` form", function()
      local ep = sl.parse_endpoint_symbol("@/legacy -- GET,POST")
      assert.are.equal("GET", ep.http_method)
      assert.are.equal("/legacy", ep.path)
    end)

    it("path-only form -> ANY", function()
      local ep = sl.parse_endpoint_symbol("@/ping")
      assert.are.equal("ANY", ep.http_method)
      assert.are.equal("/ping", ep.path)
    end)

    it("empty path in annotation normalises to /", function()
      local ep = sl.parse_endpoint_symbol('@GetMapping("")')
      assert.are.equal("/", ep.path)
    end)

    it("returns nil on junk", function()
      assert.is_nil(sl.parse_endpoint_symbol(""))
      assert.is_nil(sl.parse_endpoint_symbol(nil))
      assert.is_nil(sl.parse_endpoint_symbol("not a symbol"))
    end)
  end)

  describe("parse_bean_symbol", function()
    it("parenthesised type: @+ 'greetingController' (com.example.GreetingController)", function()
      local b = sl.parse_bean_symbol("@+ 'greetingController' (com.example.GreetingController)")
      assert.are.equal("greetingController", b.bean_name)
      assert.are.equal("com.example.GreetingController", b.class_name)
    end)

    it("bare type", function()
      local b = sl.parse_bean_symbol("@+ 'dataSource' javax.sql.DataSource")
      assert.are.equal("dataSource", b.bean_name)
      assert.are.equal("javax.sql.DataSource", b.class_name)
    end)

    it("id only -> empty class_name", function()
      local b = sl.parse_bean_symbol("@+ 'objectMapper'")
      assert.are.equal("objectMapper", b.bean_name)
      assert.are.equal("", b.class_name)
    end)

    it("returns nil on junk", function()
      assert.is_nil(sl.parse_bean_symbol(""))
      assert.is_nil(sl.parse_bean_symbol(nil))
      assert.is_nil(sl.parse_bean_symbol("@+ no quotes here"))
    end)
  end)

  describe("live-client guards (no STS4 attached in the busted child)", function()
    it("available() is false and client() is nil", function()
      assert.is_nil(sl.client())
      assert.is_false(sl.available())
    end)

    it("query_endpoints / query_beans resolve to nil without throwing", function()
      local got = { ep = "unset", bn = "unset" }
      sl.query_endpoints(function(list)
        got.ep = list
      end)
      sl.query_beans(function(list)
        got.bn = list
      end)
      vim.wait(500, function()
        return got.ep ~= "unset" and got.bn ~= "unset"
      end, 10)
      assert.is_nil(got.ep)
      assert.is_nil(got.bn)
    end)
  end)
end)
