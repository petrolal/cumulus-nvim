-- Native Spring Boot Discovery -- static shape & parse tests

describe("Spring Boot Discovery", function()
  describe("Legacy engine purge", function()
    it("should have removed the tetravim.util.engine module entirely", function()
      assert.is_false(pcall(require, "tetravim.util.engine"))
    end)
  end)

  describe("Module shape", function()
    it("should expose public API on tetravim.util.spring", function()
      local spring = require("tetravim.util.spring")
      assert.is_table(spring)
      assert.is_function(spring.detect_root)
      assert.is_function(spring.find_main_class)
      assert.is_function(spring.detect_app)
      assert.is_function(spring.build_dap_config)
      assert.is_function(spring.find_endpoints)
      assert.is_function(spring.find_beans)
      assert.is_function(spring.decapitalize)
      assert.is_function(spring.norm_segment)
      assert.is_function(spring.join_paths)
      assert.is_function(spring._endpoints_in_content)
      assert.is_function(spring._beans_in_content)
    end)

    it("should expose public API on tetravim.util.spring-picker", function()
      local picker = require("tetravim.util.spring-picker")
      assert.is_table(picker)
      assert.is_function(picker.pick_endpoint)
      assert.is_function(picker.pick_bean)
      assert.is_function(picker.detect_app)
    end)

    it("should expose dedup_insert on tetravim.util.springboot-debug", function()
      local sb = require("tetravim.util.springboot-debug")
      assert.is_table(sb)
      assert.is_function(sb.launch_debug)
      assert.is_function(sb.setup_springboot_dap)
      assert.is_function(sb.dedup_insert)
    end)
  end)

  describe("AST parsing fixtures", function()
    local spring = require("tetravim.util.spring")

    it("should parse Spring MVC controller endpoints with @RestController and mappings", function()
      local content = [[
package com.example;
import org.springframework.web.bind.annotation.*;

@RestController
@RequestMapping("/api/v1")
public class UserController {
    @GetMapping("/users")
    public String getUsers() { return null; }

    @PostMapping(path = "/users")
    public String createUser() { return null; }

    @RequestMapping(value = "/custom", method = RequestMethod.DELETE)
    public void deleteCustom() {}
}
]]
      local eps = spring._endpoints_in_content(content, "java", "UserController.java")
      assert.are.equal(3, #eps)

      assert.are.equal("GET", eps[1].http_method)
      assert.are.equal("/api/v1/users", eps[1].path)
      assert.are.equal("UserController", eps[1].class_name)
      assert.are.equal("getUsers", eps[1].handler_name)
      assert.are.equal("UserController.java", eps[1].file)
      assert.is_number(eps[1].line)

      assert.are.equal("POST", eps[2].http_method)
      assert.are.equal("/api/v1/users", eps[2].path)
      assert.are.equal("createUser", eps[2].handler_name)

      assert.are.equal("DELETE", eps[3].http_method)
      assert.are.equal("/api/v1/custom", eps[3].path)
      assert.are.equal("deleteCustom", eps[3].handler_name)
    end)

    it("should parse JAX-RS resource endpoints with @Path and HTTP methods", function()
      local content = [[
package com.example;
import javax.ws.rs.*;

@Path("/api/v2")
public class JaxResource {
    @GET
    public String getAll() { return null; }

    @POST
    @Path("/item")
    public String createItem() { return null; }
}
]]
      local eps = spring._endpoints_in_content(content, "java", "JaxResource.java")
      assert.are.equal(2, #eps)

      assert.are.equal("GET", eps[1].http_method)
      assert.are.equal("/api/v2", eps[1].path)
      assert.are.equal("JaxResource", eps[1].class_name)
      assert.are.equal("getAll", eps[1].handler_name)

      assert.are.equal("POST", eps[2].http_method)
      assert.are.equal("/api/v2/item", eps[2].path)
      assert.are.equal("createItem", eps[2].handler_name)
    end)

    it("should parse @Service bean with constructor injection and decapitalize bean name", function()
      local content = [[
package com.example;
import org.springframework.stereotype.Service;

@Service
public class FooService {
    public FooService(Bar bar, Baz baz) {}
}
]]
      local beans = spring._beans_in_content(content, "java", "FooService.java")
      assert.are.equal(1, #beans)

      local b = beans[1]
      assert.are.equal("fooService", b.bean_name)
      assert.are.equal("FooService", b.class_name)
      assert.are.equal("FooService.java", b.file)
      assert.is_number(b.line)
      assert.are.same({ "bar", "baz" }, b.injected_deps)
    end)

    it("should parse @Repository interface with legitimately empty injected_deps", function()
      local content = [[
package com.example;
import org.springframework.stereotype.Repository;

@Repository
public interface UserRepository {
}
]]
      local beans = spring._beans_in_content(content, "java", "UserRepository.java")
      assert.are.equal(1, #beans)

      local b = beans[1]
      assert.are.equal("userRepository", b.bean_name)
      assert.are.equal("UserRepository", b.class_name)
      assert.are.same({}, b.injected_deps)
    end)

    it("should preserve leading all-caps run in decapitalize", function()
      assert.are.equal("fooService", spring.decapitalize("FooService"))
      assert.are.equal("bar", spring.decapitalize("Bar"))
      assert.are.equal("URLClassLoader", spring.decapitalize("URLClassLoader"))
      assert.are.equal("SQLDialect", spring.decapitalize("SQLDialect"))
    end)

    it("should parse Kotlin controller endpoints and beans with primary constructor", function()
      local ctrl_code = [[
package com.example

@RestController
@RequestMapping("/api/kt")
class KotlinController {
    @GetMapping("/hello")
    fun hello(): String = "hi"
}
]]
      local eps = spring._endpoints_in_content(ctrl_code, "kotlin", "KotlinController.kt")
      assert.are.equal(1, #eps)
      assert.are.equal("GET", eps[1].http_method)
      assert.are.equal("/api/kt/hello", eps[1].path)
      assert.are.equal("KotlinController", eps[1].class_name)
      assert.are.equal("hello", eps[1].handler_name)

      local bean_code = [[
package com.example

@Service
class KotlinService(
    val repo: UserRepository,
    val config: AppConfig
)
]]
      local beans = spring._beans_in_content(bean_code, "kotlin", "KotlinService.kt")
      assert.are.equal(1, #beans)
      assert.are.equal("kotlinService", beans[1].bean_name)
      assert.are.same({ "userRepository", "appConfig" }, beans[1].injected_deps)
    end)
  end)

  describe("DAP configuration deduplication", function()
    local sb = require("tetravim.util.springboot-debug")

    it("should deduplicate configs by non-nil name and allow multiple nil-named configs", function()
      local configs = {}
      sb.dedup_insert(configs, { name = "Spring Boot: App", type = "java" })
      sb.dedup_insert(configs, { name = "Spring Boot: App", type = "java" })
      assert.are.equal(1, #configs)

      sb.dedup_insert(configs, { name = "Spring Boot: App (attach)", type = "java" })
      assert.are.equal(2, #configs)

      -- Nil-named configs both insert
      sb.dedup_insert(configs, { type = "java", request = "launch" })
      sb.dedup_insert(configs, { type = "java", request = "launch" })
      assert.are.equal(4, #configs)
    end)
  end)

  describe("Graceful degradation (I/O Matrix Rows 7 & 8)", function()
    local spring = require("tetravim.util.spring")

    it("should warn and cb(nil) when rg and grep are both absent (Matrix row 7)", function()
      local orig_exec = vim.fn.executable
      vim.fn.executable = function(cmd)
        if cmd == "rg" or cmd == "grep" then
          return 0
        end
        return orig_exec(cmd)
      end

      local notified = {}
      local orig_notify = vim.notify
      vim.notify = function(msg, level)
        table.insert(notified, { msg = msg, level = level })
      end

      local called_cb = false
      local cb_val = "not_nil"
      spring.find_endpoints("/nonexistent", function(res)
        called_cb = true
        cb_val = res
      end)

      vim.wait(1000, function()
        return called_cb
      end, 10)

      vim.fn.executable = orig_exec
      vim.notify = orig_notify

      assert.is_true(called_cb)
      assert.is_nil(cb_val)
      assert.is_true(#notified >= 1)
      assert.are.equal(vim.log.levels.WARN, notified[1].level)
      assert.is_truthy(notified[1].msg:find("ripgrep or grep required for Spring discovery"))
    end)

    it("should warn and cb(nil) when Tree-sitter java parser is unavailable (Matrix row 8)", function()
      local orig_get_parser = vim.treesitter.get_string_parser
      vim.treesitter.get_string_parser = function(content, lang)
        if lang == "java" then
          error("no parser for 'java'")
        end
        return orig_get_parser(content, lang)
      end

      local notified = {}
      local orig_notify = vim.notify
      vim.notify = function(msg, level)
        table.insert(notified, { msg = msg, level = level })
      end

      local called_cb = false
      local cb_val = "not_nil"
      spring.find_endpoints("/some/root", function(res)
        called_cb = true
        cb_val = res
      end)

      vim.wait(1000, function()
        return called_cb
      end, 10)

      vim.treesitter.get_string_parser = orig_get_parser
      vim.notify = orig_notify

      assert.is_true(called_cb)
      assert.is_nil(cb_val)
      assert.is_true(#notified >= 1)
      assert.are.equal(vim.log.levels.WARN, notified[1].level)
      assert.is_truthy(notified[1].msg:find("Tree%-sitter java parser not available"))
    end)
  end)

  -- Migrated from scripts/validate-2-3.sh (steps [2/4], [3/4], [4/4]). Needs rg
  -- and the Tree-sitter java parser, both present in the plenary busted child.
  describe("Native discovery -- behavioral (DAP config + keymaps)", function()
    local spring_pkg = "tetravim.util.springboot-debug"
    local fixture, saved_cwd

    local function make_fixture()
      local root = vim.fn.tempname()
      vim.fn.mkdir(root .. "/src/main/java/com/example", "p")
      vim.fn.writefile({
        '<project xmlns="http://maven.apache.org/POM/4.0.0">',
        "  <modelVersion>4.0.0</modelVersion>",
        "  <groupId>com.example</groupId>",
        "  <artifactId>demo-app</artifactId>",
        "  <version>0.0.1-SNAPSHOT</version>",
        "</project>",
      }, root .. "/pom.xml")
      vim.fn.writefile({
        "package com.example;",
        "import org.springframework.boot.autoconfigure.SpringBootApplication;",
        "@SpringBootApplication",
        "public class DemoApplication {}",
      }, root .. "/src/main/java/com/example/DemoApplication.java")
      return root
    end

    before_each(function()
      fixture = make_fixture()
      saved_cwd = vim.fn.getcwd()
      package.loaded["dap"] = nil
    end)

    after_each(function()
      pcall(vim.fn.chdir, saved_cwd)
      vim.fn.delete(fixture, "rf")
      package.loaded["dap"] = nil
    end)

    it("setup_springboot_dap generates a launch + attach config and is idempotent", function()
      local fake_dap = { configurations = { java = {} } }
      package.loaded["dap"] = fake_dap

      local sb = require(spring_pkg)
      sb.setup_springboot_dap(fixture)
      vim.wait(5000, function()
        return #fake_dap.configurations.java == 2
      end, 50)

      assert.are.equal(2, #fake_dap.configurations.java)
      local launch, attach = fake_dap.configurations.java[1], fake_dap.configurations.java[2]
      assert.are.equal("launch", launch.request)
      assert.are.equal("com.example.DemoApplication", launch.mainClass)
      assert.are.equal("Spring Boot: demo-app", launch.name)
      assert.are.equal("attach", attach.request)
      assert.are.equal("Spring Boot: demo-app (attach)", attach.name)

      -- A second attach in the same project must not duplicate.
      sb.setup_springboot_dap(fixture)
      vim.wait(300, function()
        return false
      end, 50)
      assert.are.equal(2, #fake_dap.configurations.java)
    end)

    it("<leader>jse / <leader>jsb / <leader>jsd resolve and <leader>jsd notifies app details", function()
      vim.fn.chdir(fixture)
      require("tetravim.util.jvm").setup_keymaps()

      for _, lhs in ipairs({ "<leader>jse", "<leader>jsb", "<leader>jsd" }) do
        local m = vim.fn.maparg(lhs, "n", false, true)
        assert.is_table(m)
        assert.is_function(m.callback)
      end

      local notified = {}
      local orig_notify = vim.notify
      vim.notify = function(msg, level)
        table.insert(notified, { msg = msg, level = level })
      end
      vim.fn.maparg("<leader>jsd", "n", false, true).callback()
      vim.wait(5000, function()
        return #notified > 0
      end, 50)
      vim.notify = orig_notify

      assert.is_true(#notified >= 1)
      assert.are.equal(
        "Spring Boot: demo-app (maven) — com.example.DemoApplication",
        notified[1].msg
      )
    end)

    it("<leader>jrd (launch_debug) registers a config and calls dap.continue()", function()
      vim.fn.chdir(fixture)
      local continued = false
      package.loaded["dap"] = {
        configurations = { java = {} },
        continue = function()
          continued = true
        end,
      }

      require("tetravim.util.jvm").setup_keymaps()
      local m = vim.fn.maparg("<leader>jrd", "n", false, true)
      assert.is_table(m)
      assert.is_function(m.callback)
      m.callback()
      vim.wait(5000, function()
        return continued
      end, 50)

      assert.is_true(continued)
      local java = package.loaded["dap"].configurations.java
      assert.is_true(#java >= 1)
      assert.are.equal("Spring Boot: demo-app", java[1].name)
    end)
  end)
end)
