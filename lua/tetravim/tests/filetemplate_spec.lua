-- New File from Template (IDEA-style New) -- engine shape & behaviour tests

describe("tetravim.util.filetemplate", function()
  local ft = require("tetravim.util.filetemplate")

  it("exposes the public engine API", function()
    assert.is_table(ft)
    assert.is_function(ft.new_file)
    assert.is_function(ft.create)
    assert.is_function(ft.render)
    assert.is_function(ft.derive_package)
    assert.is_function(ft.all_templates)
    assert.is_function(ft.load_user_templates)
    assert.is_function(ft.builtin_count)
    assert.is_table(ft.builtin)
  end)

  it("ships a broad built-in catalogue (Java/Kotlin/Scala/web/devops)", function()
    assert.is_true(ft.builtin_count() >= 30)
    for _, id in ipairs({
      "java.class",
      "java.interface",
      "java.enum",
      "java.record",
      "kt.class",
      "kt.data",
      "scala.case-class",
      "web.html",
      "web.xhtml",
      "devops.dockerfile",
    }) do
      assert.is_table(ft.builtin[id], "missing built-in template: " .. id)
      assert.is_function(ft.builtin[id].body)
    end
  end)

  describe("derive_package", function()
    it("derives a package from a Maven/Gradle java source layout", function()
      assert.are.equal("com.example.app", ft.derive_package("/proj/src/main/java/com/example/app"))
      assert.are.equal("com.example.app", ft.derive_package("/proj/src/test/java/com/example/app/"))
    end)

    it("derives a package from a kotlin source layout", function()
      assert.are.equal("com.acme.svc", ft.derive_package("/proj/src/main/kotlin/com/acme/svc"))
    end)

    it("returns empty for non-source directories", function()
      assert.are.equal("", ft.derive_package("/proj/src/main/resources/db/migration"))
      assert.are.equal("", ft.derive_package("/proj/scripts"))
      assert.are.equal("", ft.derive_package("/proj/src/main/java"))
    end)
  end)

  describe("render", function()
    it("emits a package declaration and class name for a Java class", function()
      local content, row, col = ft.render(ft.builtin["java.class"], {
        name = "OrderService",
        package = "com.example.orders",
      })
      assert.is_truthy(content:match("package com%.example%.orders;"))
      assert.is_truthy(content:match("public class OrderService {"))
      -- ${cursor} marker is stripped and its position reported
      assert.is_falsy(content:match("%${cursor}"))
      assert.is_number(row)
      assert.is_number(col)
      assert.is_true(row >= 1)
    end)

    it("omits the package line outside a source root", function()
      local content = ft.render(ft.builtin["java.interface"], { name = "Repo", package = "" })
      assert.is_falsy(content:match("^package"))
      assert.is_truthy(content:match("public interface Repo {"))
    end)

    it("uses package-without-semicolon for Kotlin", function()
      local content = ft.render(ft.builtin["kt.data"], { name = "Point", package = "geo" })
      assert.is_truthy(content:match("package geo\n"))
      assert.is_falsy(content:match("package geo;"))
      assert.is_truthy(content:match("data class Point%("))
    end)

    it("interpolates the title into an HTML5 scaffold", function()
      local content = ft.render(ft.builtin["web.html"], { name = "Landing" })
      assert.is_truthy(content:match("<!DOCTYPE html>"))
      assert.is_truthy(content:match("<title>Landing</title>"))
    end)
  end)

  describe("scaffold", function()
    local tmp

    before_each(function()
      tmp = vim.fn.tempname()
      vim.fn.mkdir(tmp, "p")
    end)

    after_each(function()
      pcall(vim.fn.delete, tmp, "rf")
    end)

    it("writes a Java class to disk with a package derived from the target dir", function()
      local dir = tmp .. "/src/main/java/com/demo"
      vim.fn.mkdir(dir, "p")
      local path, row, col = ft.scaffold(ft.builtin["java.class"], "Widget", dir, tmp)
      assert.are.equal(dir .. "/Widget.java", path)
      assert.is_number(row)
      assert.is_number(col)
      local written = table.concat(vim.fn.readfile(path), "\n")
      assert.is_truthy(written:match("package com%.demo;"))
      assert.is_truthy(written:match("public class Widget {"))
    end)

    it("expands a dotted FQN in the name field into nested directories", function()
      local dir = tmp .. "/src/main/java"
      vim.fn.mkdir(dir, "p")
      local path = ft.scaffold(ft.builtin["kt.class"], "com.acme.Thing", dir, tmp)
      assert.are.equal(dir .. "/com/acme/Thing.kt", path)
      local written = table.concat(vim.fn.readfile(path), "\n")
      assert.is_truthy(written:match("package com%.acme\n"))
      assert.is_truthy(written:match("class Thing {"))
    end)

    it("refuses to overwrite an existing file", function()
      local path = tmp .. "/Dup.java"
      vim.fn.writefile({ "// keep me" }, path)
      local ok, err = ft.scaffold(ft.builtin["java.class"], "Dup", tmp, tmp)
      assert.is_nil(ok)
      assert.are.equal("exists", err)
      assert.are.equal("// keep me", table.concat(vim.fn.readfile(path), "\n"))
    end)

    it("honours a fixed_name template (Dockerfile) ignoring the entered value", function()
      local path = ft.scaffold(ft.builtin["devops.dockerfile"], "Dockerfile", tmp, tmp)
      assert.are.equal(tmp .. "/Dockerfile", path)
      assert.is_truthy(table.concat(vim.fn.readfile(path), "\n"):match("^FROM "))
    end)
  end)

  describe("skeletons_for", function()
    it("matches templates by extension, filetype tag and fixed name", function()
      local by_ext = ft.skeletons_for("java", "", "Foo")
      assert.is_true(#by_ext >= 3)
      local ids = vim.tbl_map(function(t)
        return t.id
      end, by_ext)
      assert.is_true(vim.tbl_contains(ids, "java.class"))

      local by_ft = ft.skeletons_for("", "kotlin", "Foo")
      assert.is_true(#by_ft >= 3)

      local fixed = ft.skeletons_for("", "dockerfile", "Dockerfile")
      local fixed_ids = vim.tbl_map(function(t)
        return t.id
      end, fixed)
      assert.is_true(vim.tbl_contains(fixed_ids, "devops.dockerfile"))
    end)

    it("returns nothing for an unrecognised type", function()
      assert.are.equal(0, #ft.skeletons_for("bin", "", "blob"))
    end)

    it("orders exact extension matches before language-tag matches", function()
      local list = ft.skeletons_for("css", "", "main")
      assert.are.equal("web.css", list[1].id)
    end)
  end)

  describe("offer_skeleton", function()
    local tmp, orig_select

    before_each(function()
      tmp = vim.fn.tempname()
      vim.fn.mkdir(tmp .. "/src/main/java/com/demo", "p")
      orig_select = vim.ui.select
    end)

    after_each(function()
      vim.ui.select = orig_select
      pcall(vim.fn.delete, tmp, "rf")
    end)

    it("fills a new empty buffer with the chosen skeleton", function()
      vim.ui.select = function(items, _, cb)
        -- items[1] is "(no template)"; pick the first real template
        cb(items[2])
      end
      local path = tmp .. "/src/main/java/com/demo/Gadget.java"
      local buf = vim.api.nvim_create_buf(true, false)
      vim.api.nvim_buf_set_name(buf, path)
      vim.bo[buf].filetype = "java"
      ft.offer_skeleton(buf)
      local body = table.concat(vim.api.nvim_buf_get_lines(buf, 0, -1, false), "\n")
      assert.is_truthy(body:match("package com%.demo;"))
      assert.is_truthy(body:match("%a") and body:match("Gadget"))
      vim.api.nvim_buf_delete(buf, { force = true })
    end)

    it("declines silently when the picker returns (no template)", function()
      vim.ui.select = function(items, _, cb)
        cb(items[1])
      end
      local buf = vim.api.nvim_create_buf(true, false)
      vim.api.nvim_buf_set_name(buf, tmp .. "/src/main/java/com/demo/Empty.java")
      vim.bo[buf].filetype = "java"
      ft.offer_skeleton(buf)
      assert.are.same({ "" }, vim.api.nvim_buf_get_lines(buf, 0, -1, false))
      vim.api.nvim_buf_delete(buf, { force = true })
    end)

    it("never prompts for a non-empty buffer or an unknown type", function()
      local seen = false
      vim.ui.select = function(_, _, cb)
        seen = true
        cb(nil)
      end

      local nonempty = vim.api.nvim_create_buf(true, false)
      vim.api.nvim_buf_set_name(nonempty, tmp .. "/src/main/java/com/demo/Filled.java")
      vim.bo[nonempty].filetype = "java"
      vim.api.nvim_buf_set_lines(nonempty, 0, -1, false, { "// already here" })
      ft.offer_skeleton(nonempty)

      local unknown = vim.api.nvim_create_buf(true, false)
      vim.api.nvim_buf_set_name(unknown, tmp .. "/notes.bin")
      ft.offer_skeleton(unknown)

      assert.is_false(seen)
      vim.api.nvim_buf_delete(nonempty, { force = true })
      vim.api.nvim_buf_delete(unknown, { force = true })
    end)
  end)

  it("new_file() opens the picker without error from any buffer", function()
    local orig = vim.ui.select
    local opened
    vim.ui.select = function(items, opts, cb)
      opened = { n = #items, prompt = opts and opts.prompt }
      cb(nil)
    end
    local okc = pcall(ft.new_file)
    vim.ui.select = orig
    assert.is_true(okc)
    assert.is_table(opened)
    assert.is_true(opened.n >= 30)
  end)

  it("all_templates() tags each entry with its id and required fields", function()
    for _, t in ipairs(ft.all_templates()) do
      assert.is_string(t.id)
      assert.is_string(t.label)
      assert.is_string(t.category)
      assert.is_string(t.ext)
    end
  end)

  -- Migrated from scripts/validate-filetemplate.sh steps [1/6] (wiring markers)
  -- and [5/6] (user template discovery). The rest of that script -- scaffold,
  -- derive_package, overwrite guard, fixed_name, BufNewFile skeleton -- is
  -- already covered by the describe blocks above.
  describe("keymap / command / health wiring (static)", function()
    local function read(path)
      local fh = assert(io.open(path, "r"))
      local body = fh:read("*a")
      fh:close()
      return body
    end

    it("core/keymaps.lua dispatches into filetemplate via :TetraVimNewFile and <leader>fn", function()
      local km = read("lua/tetravim/core/keymaps.lua")
      assert.is_truthy(km:match("filetemplate"))
      assert.is_truthy(km:match("TetraVimNewFile"))
      assert.is_truthy(km:match("<leader>fn"))
    end)

    it("the healthcheck carries the New File from Template section", function()
      assert.is_truthy(require("tetravim.tests.helpers").health_source():match("New File from Template"))
    end)
  end)

  describe("user templates", function()
    local tmp, orig_user_dir

    before_each(function()
      tmp = vim.fn.tempname()
      vim.fn.mkdir(tmp, "p")
      orig_user_dir = ft.user_dir
    end)

    after_each(function()
      ft.user_dir = orig_user_dir
      pcall(vim.fn.delete, tmp, "rf")
    end)

    it("discovers a user template dir, parses its directive and expands ${NAME}/${PACKAGE}", function()
      vim.fn.writefile({
        "<!-- tetravim: label=DDD_Aggregate langs=java -->",
        "package ${PACKAGE};",
        "",
        "public final class ${NAME} {",
        "    private ${NAME}() {}",
        "}",
      }, tmp .. "/Aggregate.java")
      ft.user_dir = function()
        return tmp
      end

      local loaded = ft.load_user_templates()
      local tpl = loaded["user.Aggregate.java"]
      assert.is_table(tpl, "user template not discovered; keys: " .. vim.inspect(vim.tbl_keys(loaded)))
      assert.are.equal("DDD Aggregate", tpl.label)
      assert.are.equal("java", tpl.ext)

      local content = ft.render(tpl, { name = "Order", package = "com.example" })
      assert.is_truthy(content:match("package com%.example;"))
      assert.is_truthy(content:match("public final class Order {"))
      assert.is_truthy(content:match("private Order%(%) {}"))
      assert.is_falsy(content:match("tetravim:"))
    end)
  end)
end)
