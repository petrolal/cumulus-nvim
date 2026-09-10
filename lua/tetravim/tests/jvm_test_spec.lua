-- lua/tetravim/tests/jvm_test_spec.lua
--
-- Covers tetravim.util.jvm_test -- the in-repo Gradle/Maven runner Kotlin and
-- Groovy buffers route through (neotest-java is .java-only, neotest-scala is
-- .scala-only). Exercises: the `--tests` / `-Dtest=` filter derivation, the
-- line-scan nearest-symbol fallback, JUnit XML aggregation, and the degraded
-- "no build tool" path.

local jt = require("tetravim.util.jvm_test")

describe("tetravim.util.jvm_test", function()
  describe("build_command", function()
    local method_target =
      { scope = "method", package = "com.foo", class = "BarTest", method = "baz", filter = "com.foo.BarTest.baz" }
    local class_target = { scope = "class", package = "com.foo", class = "BarTest", filter = "com.foo.BarTest" }

    it("gradle: method -> --tests 'pkg.Class.method'", function()
      assert.are.equal(
        "./gradlew test --tests 'com.foo.BarTest.baz'",
        jt.build_command("gradle", "./gradlew", method_target)
      )
    end)

    it("gradle: class -> --tests 'pkg.Class'", function()
      assert.are.equal(
        "./gradlew test --tests 'com.foo.BarTest'",
        jt.build_command("gradle", "./gradlew", class_target)
      )
    end)

    it("gradle: nil target -> bare `test`", function()
      assert.are.equal("gradle test", jt.build_command("gradle", "gradle", nil))
    end)

    it("maven: method -> -Dtest='pkg.Class#method'", function()
      assert.are.equal("./mvnw test -Dtest='com.foo.BarTest#baz'", jt.build_command("maven", "./mvnw", method_target))
    end)

    it("maven: class -> -Dtest='pkg.Class'", function()
      assert.are.equal("mvn test -Dtest='com.foo.BarTest'", jt.build_command("maven", "mvn", class_target))
    end)

    it("package-less target still produces a usable filter", function()
      local t = { scope = "class", class = "BarTest", filter = "BarTest" }
      assert.are.equal("./gradlew test --tests 'BarTest'", jt.build_command("gradle", "./gradlew", t))
      assert.are.equal("mvn test -Dtest='BarTest'", jt.build_command("maven", "mvn", t))
    end)
  end)

  describe("parse_junit_string", function()
    local xml = [[<?xml version="1.0" encoding="UTF-8"?>
<testsuite name="com.foo.BarTest" tests="3" skipped="1" failures="1" errors="0" time="0.05">
  <testcase name="passes" classname="com.foo.BarTest" time="0.01"/>
  <testcase name="is skipped" classname="com.foo.BarTest" time="0"><skipped/></testcase>
  <testcase name="fails" classname="com.foo.BarTest" time="0.02">
    <failure message="expected:&lt;1&gt; but was:&lt;2&gt;" type="org.opentest4j.AssertionFailedError">stacktrace here</failure>
  </testcase>
</testsuite>]]

    it("aggregates the testsuite counters", function()
      local agg = jt.parse_junit_string(xml)
      assert.are.equal(3, agg.total)
      assert.are.equal(1, agg.failures)
      assert.are.equal(0, agg.errors)
      assert.are.equal(1, agg.skipped)
    end)

    it("classifies each testcase and unescapes the failure message", function()
      local agg = jt.parse_junit_string(xml)
      assert.are.equal(3, #agg.cases)
      local by_name = {}
      for _, c in ipairs(agg.cases) do
        by_name[c.name] = c
      end
      assert.are.equal("passed", by_name["passes"].status)
      assert.are.equal("skipped", by_name["is skipped"].status)
      assert.are.equal("failure", by_name["fails"].status)
      assert.is_truthy(by_name["fails"].message:match("expected:<1> but was:<2>"))
    end)

    it("folds multiple suites into one aggregate", function()
      local agg = jt.parse_junit_string(xml)
      jt.parse_junit_string(
        '<testsuite name="x" tests="2" skipped="0" failures="0" errors="0"><testcase name="a" classname="x"/><testcase name="b" classname="x"/></testsuite>',
        agg
      )
      assert.are.equal(5, agg.total)
      assert.are.equal(1, agg.failures)
      assert.are.equal(5, #agg.cases)
    end)

    it("tolerates empty / junk input without throwing", function()
      assert.has_no.errors(function()
        jt.parse_junit_string("")
        jt.parse_junit_string("not xml at all")
        jt.parse_junit_string(nil)
      end)
    end)
  end)

  describe("_nearest_via_linescan", function()
    local function scratch(lines, cursor_row)
      local buf = vim.api.nvim_create_buf(false, true)
      vim.api.nvim_buf_set_lines(buf, 0, -1, false, lines)
      vim.api.nvim_set_current_buf(buf)
      vim.api.nvim_win_set_cursor(0, { cursor_row, 0 })
      return buf
    end

    it("finds the enclosing Kotlin class + backticked fun name", function()
      local buf = scratch({
        "package com.foo.bar",
        "",
        "class BarTest {",
        "    @Test",
        "    fun `does a thing`() {",
        "        assertEquals(1, 1)",
        "    }",
        "}",
      }, 6)
      local class_name, func_name = jt._nearest_via_linescan(buf)
      assert.are.equal("BarTest", class_name)
      assert.are.equal("does a thing", func_name)
      vim.api.nvim_buf_delete(buf, { force = true })
    end)

    it("finds a plain `fun name()` above the cursor", function()
      local buf = scratch({
        "object Helpers {",
        "  fun computes() {",
        "    val x = 1",
        "  }",
        "}",
      }, 3)
      local class_name, func_name = jt._nearest_via_linescan(buf)
      assert.are.equal("Helpers", class_name)
      assert.are.equal("computes", func_name)
      vim.api.nvim_buf_delete(buf, { force = true })
    end)
  end)

  describe("derive_target", function()
    it("builds a method-scoped target from a Kotlin buffer", function()
      local buf = vim.api.nvim_create_buf(false, true)
      vim.api.nvim_buf_set_name(buf, vim.fn.tempname() .. "/BarTest.kt")
      vim.bo[buf].filetype = "kotlin"
      vim.bo[buf].buftype = ""
      vim.api.nvim_buf_set_lines(buf, 0, -1, false, {
        "package com.foo.bar",
        "",
        "class BarTest {",
        "    @Test",
        "    fun `does a thing`() {",
        "        assertEquals(1, 1)",
        "    }",
        "}",
      })
      vim.api.nvim_set_current_buf(buf)
      vim.api.nvim_win_set_cursor(0, { 6, 0 })

      local target, err = jt.derive_target(buf)
      assert.is_nil(err)
      assert.are.equal("method", target.scope)
      assert.are.equal("BarTest", target.class)
      assert.are.equal("com.foo.bar", target.package)
      assert.are.equal("does a thing", target.method)
      assert.are.equal("com.foo.bar.BarTest.does a thing", target.filter)
      vim.api.nvim_buf_delete(buf, { force = true })
    end)

    it("whole_file drops the method and keeps the class", function()
      local buf = vim.api.nvim_create_buf(false, true)
      vim.api.nvim_buf_set_name(buf, vim.fn.tempname() .. "/BarTest.kt")
      vim.bo[buf].filetype = "kotlin"
      vim.bo[buf].buftype = ""
      vim.api.nvim_buf_set_lines(buf, 0, -1, false, {
        "package com.foo",
        "class BarTest {",
        "  fun a() {}",
        "}",
      })
      vim.api.nvim_set_current_buf(buf)
      vim.api.nvim_win_set_cursor(0, { 3, 0 })

      local target = jt.derive_target(buf, { whole_file = true })
      assert.are.equal("class", target.scope)
      assert.are.equal("com.foo.BarTest", target.filter)
      assert.is_nil(target.method)
      vim.api.nvim_buf_delete(buf, { force = true })
    end)

    it("rejects a scratch buffer with no file name", function()
      local buf = vim.api.nvim_create_buf(false, true)
      vim.api.nvim_set_current_buf(buf)
      local target, err = jt.derive_target(buf)
      assert.is_nil(target)
      assert.is_string(err)
      vim.api.nvim_buf_delete(buf, { force = true })
    end)
  end)

  describe("result_files", function()
    it("returns a table and never throws on a missing root", function()
      assert.are.same({}, jt.result_files("gradle", ""))
      assert.is_table(jt.result_files("maven", "/nonexistent/path/xyz"))
    end)
  end)

  describe("run_nearest degraded path", function()
    it("notifies instead of throwing when no build tool is found", function()
      local buf = vim.api.nvim_create_buf(false, true)
      -- A .kt file under a directory with no pom.xml / build.gradle anywhere.
      vim.api.nvim_buf_set_name(buf, "/tmp/tetravim-no-project-" .. tostring(vim.loop.hrtime()) .. "/Foo.kt")
      vim.bo[buf].filetype = "kotlin"
      vim.bo[buf].buftype = ""
      vim.api.nvim_buf_set_lines(buf, 0, -1, false, { "package x", "class FooTest { fun a() {} }" })
      vim.api.nvim_set_current_buf(buf)
      vim.api.nvim_win_set_cursor(0, { 2, 0 })

      local orig = vim.notify
      vim.notify = function() end
      assert.has_no.errors(function()
        jt.run_nearest(buf)
      end)
      vim.notify = orig
      vim.api.nvim_buf_delete(buf, { force = true })
    end)
  end)
end)
