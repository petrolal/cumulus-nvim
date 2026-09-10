local coverage = require("tetravim.util.coverage")

describe("Test Coverage Module", function()
  local sample_xml = [[<?xml version="1.0" encoding="UTF-8" standalone="yes"?>
<!DOCTYPE report PUBLIC "-//JACOCO//DTD Report 1.1//EN" "report.dtd">
<report name="demo-project">
  <package name="com/example/demo">
    <class name="com/example/demo/DemoService" sourcefilename="DemoService.java">
      <method name="calculate" desc="()V" line="10">
        <counter type="INSTRUCTION" missed="0" covered="5"/>
        <counter type="LINE" missed="0" covered="1"/>
      </method>
    </class>
    <sourcefile name="DemoService.java">
      <line nr="10" mi="0" ci="5" mb="0" cb="0"/>
      <line nr="12" mi="4" ci="0" mb="0" cb="0"/>
      <line nr="15" mi="0" ci="3" mb="1" cb="1"/>
      <counter type="INSTRUCTION" missed="4" covered="8"/>
      <counter type="BRANCH" missed="1" covered="1"/>
      <counter type="LINE" missed="1" covered="2"/>
    </sourcefile>
  </package>
</report>]]

  it("should expose all required public APIs", function()
    assert.is_function(coverage.load)
    assert.is_function(coverage.clear)
    assert.is_function(coverage.toggle)
    assert.is_function(coverage.summary)
    assert.is_function(coverage.parse)
    assert.is_function(coverage.parse_xml)
    assert.is_function(coverage.find_report_file)
    assert.is_function(coverage.apply_to_buffer)
    assert.is_function(coverage.apply_to_all_buffers)
  end)

  it("should parse JaCoCo XML into covered, uncovered, and partial lines", function()
    local res, err = coverage.parse_xml(sample_xml)
    assert.is_nil(err)
    assert.is_table(res)
    assert.is_table(res.summary)
    assert.equals(3, res.summary.lines_total)
    assert.equals(1, res.summary.lines_covered)
    assert.equals(1, res.summary.lines_missed)
    assert.equals(1, res.summary.lines_partial)
    assert.equals(33.33, res.summary.coverage_pct)

    assert.is_table(res.files["com/example/demo/DemoService.java"])
    local file_rec = res.files["com/example/demo/DemoService.java"]
    assert.equals("covered", file_rec.lines[10])
    assert.equals("uncovered", file_rec.lines[12])
    assert.equals("partial", file_rec.lines[15])

    assert.equals(1, #file_rec.covered_lines)
    assert.equals(10, file_rec.covered_lines[1])
    assert.equals(1, #file_rec.missed_lines)
    assert.equals(12, file_rec.missed_lines[1])
    assert.equals(1, #file_rec.partial_lines)
    assert.equals(15, file_rec.partial_lines[1])

    -- Entries array format for backwards compatibility
    assert.equals(1, #res.entries)
    assert.equals("com/example/demo/DemoService.java", res.entries[1].file)
  end)

  it("should handle multi-package and multi-sourcefile reports", function()
    local multi_xml = [[<?xml version="1.0" encoding="UTF-8"?>
<report name="multi-module">
  <package name="org.example.pkg1">
    <sourcefile name="ServiceA.java">
      <line nr="5" mi="0" ci="2" mb="0" cb="0"/>
    </sourcefile>
  </package>
  <package name="org/example/pkg2">
    <sourcefile name="ServiceB.kt">
      <line nr="20" mi="3" ci="0" mb="0" cb="0"/>
      <line nr="21" mi="0" ci="2" mb="2" cb="2"/>
    </sourcefile>
  </package>
</report>]]
    local res, err = coverage.parse_xml(multi_xml)
    assert.is_nil(err)
    assert.equals(3, res.summary.lines_total)
    assert.equals(1, res.summary.lines_covered)
    assert.equals(1, res.summary.lines_missed)
    assert.equals(1, res.summary.lines_partial)
    assert.is_table(res.files["org/example/pkg1/ServiceA.java"])
    assert.is_table(res.files["org/example/pkg2/ServiceB.kt"])
    assert.equals(2, #res.entries)
  end)

  it("should handle error edge cases gracefully without throwing", function()
    -- Non-existent file
    local res1, err1 = coverage.parse("/tmp/non_existent_jacoco_file_xyz.xml")
    assert.is_nil(res1)
    assert.is_string(err1)

    -- Empty XML content
    local res2, err2 = coverage.parse_xml("")
    assert.is_nil(res2)
    assert.is_string(err2)

    -- Malformed non-XML string
    local res3, err3 = coverage.parse_xml("this is not xml at all")
    assert.is_nil(res3)
    assert.is_string(err3)
  end)

  it("should place signs and virtual text on a matching buffer and support clear/toggle", function()
    local cov_ns = vim.api.nvim_create_namespace("tetravim_coverage")
    local function wait_applied()
      vim.wait(2000, function()
        return not coverage.is_loading
      end, 10)
    end
    local function vt_count(buf)
      local marks = vim.api.nvim_buf_get_extmarks(buf, cov_ns, 0, -1, { details = true })
      local n, rows = 0, {}
      for _, m in ipairs(marks) do
        if m[4] and m[4].virt_text then
          n = n + 1
          rows[m[2] + 1] = true
        end
      end
      return n, rows
    end

    -- Create a temporary XML file
    local tmp_xml = vim.fn.tempname() .. ".xml"
    local f = io.open(tmp_xml, "w")
    f:write(sample_xml)
    f:close()

    -- Create a buffer matching DemoService.java
    local bufnr = vim.api.nvim_create_buf(false, true)
    local test_buf_name = "/workspace/src/main/java/com/example/demo/DemoService.java"
    vim.api.nvim_buf_set_name(bufnr, test_buf_name)
    local lines = {}
    for i = 1, 20 do
      table.insert(lines, "line " .. i)
    end
    vim.api.nvim_buf_set_lines(bufnr, 0, -1, false, lines)

    -- Load coverage (overlay application is chunked/async)
    local ok, res = coverage.load(tmp_xml)
    assert.is_true(ok)
    assert.is_true(coverage.is_visible)
    wait_applied()

    -- Check signs placed
    local placed = vim.fn.sign_getplaced(bufnr, { group = "tetravim_coverage_signs" })
    assert.is_table(placed)
    assert.is_table(placed[1].signs)
    local sign_lines = {}
    for _, s in ipairs(placed[1].signs) do
      sign_lines[s.lnum] = s.name
    end
    assert.equals("TetraVimCoverageCovered", sign_lines[10])
    assert.equals("TetraVimCoverageUncovered", sign_lines[12])
    assert.equals("TetraVimCoveragePartial", sign_lines[15])

    -- Check end-of-line virtual text (missed & partial lines only)
    local vt_n, vt_rows = vt_count(bufnr)
    assert.equals(2, vt_n)
    assert.is_true(vt_rows[12])
    assert.is_true(vt_rows[15])

    -- Summary API
    local s = coverage.summary()
    assert.is_table(s)
    assert.equals(3, s.lines_total)

    -- Toggle coverage off
    coverage.toggle()
    assert.is_false(coverage.is_visible)
    local placed_after_toggle = vim.fn.sign_getplaced(bufnr, { group = "tetravim_coverage_signs" })
    assert.equals(0, #placed_after_toggle[1].signs)

    -- Toggle coverage back on
    coverage.toggle()
    assert.is_true(coverage.is_visible)
    wait_applied()
    local placed_restored = vim.fn.sign_getplaced(bufnr, { group = "tetravim_coverage_signs" })
    assert.equals(3, #placed_restored[1].signs)

    -- Clear coverage completely
    coverage.clear(true)
    assert.is_false(coverage.is_visible)
    assert.is_nil(coverage.last_coverage)
    local placed_after_clear = vim.fn.sign_getplaced(bufnr, { group = "tetravim_coverage_signs" })
    assert.equals(0, #placed_after_clear[1].signs)
    assert.equals(0, (vt_count(bufnr)))

    -- Cleanup
    vim.api.nvim_buf_delete(bufnr, { force = true })
    os.remove(tmp_xml)
  end)
end)

-- Migrated from scripts/validate-test-coverage.sh (SPEC-1.3). Steps [1] item 2
-- and [2] (parse/signs/virt-text/toggle/clear/errors) are covered by the
-- describe block above; ported here are the neotest lazy-spec shape + which-key
-- groups + JVM keymap registration + user-command round-trip (step [1] items
-- 1,3,4,5,6 and step [2] item 7) and the degraded neotest key handlers (step
-- [3] -- every handler is pcall(require,"neotest")-guarded, so it exercises the
-- "not available" branch cleanly in the plenary child).
describe("SPEC-1.3 test runner wiring (migrated from validate-test-coverage.sh)", function()
  local tools_test = require("tetravim.plugins.tools-test")
  local neotest_spec = tools_test[1]

  local function key_map()
    local t = {}
    for _, k in ipairs(neotest_spec.keys or {}) do
      t[k[1]] = k[2]
    end
    return t
  end

  it("tools-test declares neotest + neotest-java + neotest-scala, ft-gated on java/scala", function()
    assert.is_table(neotest_spec)
    assert.are.equal("nvim-neotest/neotest", neotest_spec[1])

    local dep_names = {}
    for _, dep in ipairs(neotest_spec.dependencies or {}) do
      dep_names[type(dep) == "table" and dep[1] or dep] = true
    end
    assert.is_true(dep_names["rcasia/neotest-java"], "missing rcasia/neotest-java dependency")
    assert.is_true(dep_names["stevanmilic/neotest-scala"], "missing stevanmilic/neotest-scala dependency")

    local ft = {}
    for _, f in ipairs(neotest_spec.ft or {}) do
      ft[f] = true
    end
    assert.is_true(ft.java)
    assert.is_true(ft.scala)
    -- Kotlin is handled outside neotest (ftplugin/kotlin.lua -> jvm_test).
    assert.is_falsy(ft.kotlin)
  end)

  it("exposes <leader>tr/tf/ts/to/td as callable key handlers", function()
    local keys = key_map()
    for _, lhs in ipairs({ "<leader>tr", "<leader>tf", "<leader>ts", "<leader>to", "<leader>td" }) do
      assert.is_function(keys[lhs], lhs .. " missing in tools-test keys")
    end
  end)

  it("neotest key handlers run without error when neotest is absent (degraded path)", function()
    local keys = key_map()
    local orig_notify = vim.notify
    vim.notify = function() end
    vim.cmd("enew")
    assert.has_no.errors(function()
      keys["<leader>ts"]()
      keys["<leader>to"]()
      keys["<leader>tr"]()
      keys["<leader>tf"]()
      keys["<leader>td"]()
    end)
    vim.notify = orig_notify
  end)

  it("jvm.whichkey_spec() carries the <leader>jt / <leader>jc groups", function()
    local jvm = require("tetravim.util.jvm")
    local groups = {}
    for _, item in ipairs(jvm.whichkey_spec()) do
      groups[item[1]] = item.group
    end
    assert.are.equal("test runner", groups["<leader>jt"])
    assert.are.equal("code coverage", groups["<leader>jc"])
  end)

  it("ui-whichkey global spec registers <leader>t as 'test runner'", function()
    local wk = require("tetravim.plugins.ui-whichkey")
    local opts = wk[1].opts(nil, { spec = {} })
    local groups = {}
    for _, item in ipairs(opts.spec) do
      if item[1] and item.group then
        groups[item[1]] = item.group
      end
    end
    assert.are.equal("test runner", groups["<leader>t"])
  end)

  it("jvm.setup_keymaps() registers the <leader>jt* / <leader>jc* leaves", function()
    local jvm = require("tetravim.util.jvm")
    jvm.setup_keymaps()
    for _, lhs in ipairs({
      "<leader>jtt",
      "<leader>jtc",
      "<leader>jta",
      "<leader>jts",
      "<leader>jto",
      "<leader>jtd",
      "<leader>jcl",
      "<leader>jcx",
      "<leader>jct",
      "<leader>jcs",
    }) do
      assert.are_not.equal("", vim.fn.maparg(lhs, "n"), lhs .. " not registered")
    end
  end)

  it("defines the :TetraVimCoverage* user commands and they round-trip", function()
    for _, cmd in ipairs({
      "TetraVimCoverageLoad",
      "TetraVimCoverageClear",
      "TetraVimCoverageToggle",
      "TetraVimCoverageSummary",
    }) do
      assert.are.equal(2, vim.fn.exists(":" .. cmd), ":" .. cmd .. " not defined")
    end

    local tmp_xml = vim.fn.tempname() .. ".xml"
    local fh = assert(io.open(tmp_xml, "w"))
    fh:write([[<?xml version="1.0"?>
<report name="cmd-test">
  <package name="com/x">
    <sourcefile name="X.java"><line nr="1" mi="0" ci="1" mb="0" cb="0"/></sourcefile>
  </package>
</report>]])
    fh:close()

    vim.cmd("TetraVimCoverageLoad " .. tmp_xml)
    assert.is_true(coverage.is_visible)
    vim.wait(2000, function()
      return not coverage.is_loading
    end, 10)
    vim.cmd("TetraVimCoverageToggle")
    assert.is_false(coverage.is_visible)
    vim.cmd("TetraVimCoverageClear")
    assert.is_nil(coverage.last_coverage)
    os.remove(tmp_xml)
  end)
end)
