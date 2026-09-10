-- Tests for tetravim.util.jvm.build
local build = require("tetravim.util.jvm.build")

describe("tetravim.util.jvm.build", function()
  it("exposes detect and find_subprojects", function()
    assert.is_function(build.detect)
    assert.is_function(build.find_subprojects)
  end)

  it("detects maven project when given path to pom.xml directory", function()
    local tmp = vim.fn.tempname()
    vim.fn.mkdir(tmp, "p")
    vim.fn.writefile({ "<project></project>" }, tmp .. "/pom.xml")

    local tool, root = build.detect(tmp)
    assert.are.same("maven", tool)
    assert.are.same(tmp, root)

    vim.fn.delete(tmp, "rf")
  end)

  it("detects gradle project when given path to build.gradle.kts directory", function()
    local tmp = vim.fn.tempname()
    vim.fn.mkdir(tmp, "p")
    vim.fn.writefile({ "// gradle" }, tmp .. "/build.gradle.kts")

    local tool, root = build.detect(tmp)
    assert.are.same("gradle", tool)
    assert.are.same(tmp, root)

    vim.fn.delete(tmp, "rf")
  end)

  it("detects project from active buffer file path", function()
    local tmp = vim.fn.tempname()
    local src_dir = tmp .. "/src/main/java"
    vim.fn.mkdir(src_dir, "p")
    vim.fn.writefile({ "<project></project>" }, tmp .. "/pom.xml")
    local test_file = src_dir .. "/App.java"
    vim.fn.writefile({ "class App {}" }, test_file)

    -- Switch to buffer
    local buf = vim.fn.bufadd(test_file)
    vim.fn.bufload(buf)
    local orig_buf = vim.api.nvim_get_current_buf()
    vim.api.nvim_set_current_buf(buf)

    local tool, root = build.detect()
    assert.are.same("maven", tool)
    assert.are.same(tmp, root)

    vim.api.nvim_set_current_buf(orig_buf)
    vim.api.nvim_buf_delete(buf, { force = true })
    vim.fn.delete(tmp, "rf")
  end)

  it("detects project from oil:// URI buffer", function()
    local tmp = vim.fn.tempname()
    vim.fn.mkdir(tmp, "p")
    vim.fn.writefile({ "// gradle" }, tmp .. "/build.gradle")

    local tool, root = build.detect("oil://" .. tmp .. "/")
    assert.are.same("gradle", tool)
    assert.are.same(tmp, root)

    vim.fn.delete(tmp, "rf")
  end)

  it("finds subprojects in immediate child directories", function()
    local tmp = vim.fn.tempname()
    local p1 = tmp .. "/sub-mvn"
    local p2 = tmp .. "/sub-gradle"
    local p3 = tmp .. "/not-a-project"
    vim.fn.mkdir(p1, "p")
    vim.fn.mkdir(p2, "p")
    vim.fn.mkdir(p3, "p")

    vim.fn.writefile({ "<project></project>" }, p1 .. "/pom.xml")
    vim.fn.writefile({ "// gradle" }, p2 .. "/build.gradle")

    local subs = build.find_subprojects(tmp)
    assert.are.same(2, #subs)

    local map = {}
    for _, s in ipairs(subs) do
      map[s.name] = s.tool
    end
    assert.are.same("maven", map["sub-mvn"])
    assert.are.same("gradle", map["sub-gradle"])

    vim.fn.delete(tmp, "rf")
  end)
end)
