-- Unit tests for tetravim.util.quality.sonar (Epic 6, Story 6.1)
--
-- Covers the pure `sonar-project.properties` parser (settings_from_properties
-- / project_key), the FILETYPES contract, and the
-- missing-`sonarlint-language-server` behaviour of language_server_cmd.
-- `vim.fn.executable` is monkeypatched -- nothing on the real $PATH is
-- consulted.

describe("tetravim.util.quality.sonar", function()
  local sonar = require("tetravim.util.quality.sonar")

  local orig_executable
  before_each(function()
    orig_executable = vim.fn.executable
  end)
  after_each(function()
    vim.fn.executable = orig_executable
  end)

  describe("FILETYPES", function()
    it("covers java, kotlin and scala", function()
      assert.are.same({ "java", "kotlin", "scala" }, sonar.FILETYPES)
    end)
  end)

  describe("settings_from_properties", function()
    it("parses key=value pairs, trimming whitespace and skipping comments/blanks", function()
      local text = table.concat({
        "# SonarQube project config",
        "",
        "sonar.projectKey = com.example:my-service ",
        "sonar.qualitygate.wait=true",
        "! bang comment",
        "sonar.host.url: https://sonar.example.com",
      }, "\n")
      local settings = sonar.settings_from_properties(text)
      assert.are.equal("com.example:my-service", settings["sonar.projectKey"])
      assert.are.equal("true", settings["sonar.qualitygate.wait"])
      assert.are.equal("https://sonar.example.com", settings["sonar.host.url"])
      assert.is_nil(settings["# SonarQube project config"])
    end)

    it("returns an empty table for empty / nil input", function()
      assert.are.same({}, sonar.settings_from_properties(""))
      assert.are.same({}, sonar.settings_from_properties(nil))
    end)
  end)

  describe("project_key", function()
    it("extracts sonar.projectKey", function()
      assert.are.equal("k", sonar.project_key("sonar.projectKey=k\nsonar.foo=bar"))
    end)

    it("is nil when absent", function()
      assert.is_nil(sonar.project_key("sonar.foo=bar"))
    end)
  end)

  describe("language_server_cmd", function()
    it("returns nil when sonarlint-language-server is not executable", function()
      vim.fn.executable = function(name)
        if name == "sonarlint-language-server" then
          return 0
        end
        return orig_executable(name)
      end
      assert.is_nil(sonar.language_server_cmd())
    end)

    it("starts with the binary and -stdio when it is executable", function()
      vim.fn.executable = function(name)
        if name == "sonarlint-language-server" then
          return 1
        end
        return orig_executable(name)
      end
      local cmd = sonar.language_server_cmd()
      assert.is_table(cmd)
      assert.are.equal("sonarlint-language-server", cmd[1])
      assert.are.equal("-stdio", cmd[2])
    end)
  end)

  describe("find_project_settings", function()
    it("returns nil when no sonar-project.properties exists at the root", function()
      assert.is_nil(sonar.find_project_settings(vim.fn.tempname()))
    end)

    it("reads and parses an on-disk properties file", function()
      local dir = vim.fn.tempname()
      vim.fn.mkdir(dir, "p")
      vim.fn.writefile({ "sonar.projectKey=disk-key", "sonar.sources=src" }, dir .. "/sonar-project.properties")
      local settings = sonar.find_project_settings(dir)
      assert.are.equal("disk-key", settings["sonar.projectKey"])
      assert.are.equal("src", settings["sonar.sources"])
    end)

    it("walks upward from a nested module directory to the project root", function()
      local root = vim.fn.tempname()
      vim.fn.mkdir(root .. "/module-a/src/main", "p")
      vim.fn.writefile({ "sonar.projectKey=upward-key" }, root .. "/sonar-project.properties")
      local settings = sonar.find_project_settings(root .. "/module-a/src/main")
      assert.are.equal("upward-key", settings["sonar.projectKey"])
    end)
  end)

  -- ------------------------------------------------------------------------
  -- Project-wide analysis (Story 6.1 extension)
  -- ------------------------------------------------------------------------

  describe("choose_backend", function()
    it("picks 'cli' only when a host URL is declared AND sonar-scanner is callable", function()
      assert.are.equal("cli", sonar.choose_backend({ ["sonar.host.url"] = "https://s.example.com" }, true))
    end)

    it("falls back to 'sweep' without a host URL", function()
      assert.are.equal("sweep", sonar.choose_backend({ ["sonar.projectKey"] = "k" }, true))
      assert.are.equal("sweep", sonar.choose_backend({ ["sonar.host.url"] = "   " }, true))
    end)

    it("falls back to 'sweep' when sonar-scanner is missing", function()
      assert.are.equal("sweep", sonar.choose_backend({ ["sonar.host.url"] = "https://s.example.com" }, false))
    end)

    it("tolerates a nil settings map", function()
      assert.are.equal("sweep", sonar.choose_backend(nil, true))
    end)
  end)

  describe("parse_report_task", function()
    it("splits on the first '=' so URL values survive intact", function()
      local map = sonar.parse_report_task(table.concat({
        "projectKey=com.example:svc",
        "serverUrl=https://sonar.example.com",
        "dashboardUrl=https://sonar.example.com/dashboard?id=com.example%3Asvc",
        "ceTaskUrl=https://sonar.example.com/api/ce/task?id=AY-abc123",
      }, "\n"))
      assert.are.equal("com.example:svc", map.projectKey)
      assert.are.equal("https://sonar.example.com/dashboard?id=com.example%3Asvc", map.dashboardUrl)
      assert.are.equal("https://sonar.example.com/api/ce/task?id=AY-abc123", map.ceTaskUrl)
    end)

    it("returns an empty table for empty / nil input", function()
      assert.are.same({}, sonar.parse_report_task(""))
      assert.are.same({}, sonar.parse_report_task(nil))
    end)
  end)

  describe("report_task_path", function()
    it("points at .scannerwork/report-task.txt under the given root", function()
      assert.are.equal("/proj/.scannerwork/report-task.txt", sonar.report_task_path("/proj"))
    end)
  end)

  describe("has_scanner", function()
    it("reflects whether sonar-scanner is executable", function()
      vim.fn.executable = function(name)
        if name == "sonar-scanner" then
          return 1
        end
        return orig_executable(name)
      end
      assert.is_true(sonar.has_scanner())
      vim.fn.executable = function(name)
        if name == "sonar-scanner" then
          return 0
        end
        return orig_executable(name)
      end
      assert.is_false(sonar.has_scanner())
    end)
  end)

  describe("is_sweep_source", function()
    it("accepts java/kt/kts/scala sources", function()
      assert.is_true(sonar.is_sweep_source("/p/src/main/java/com/x/Foo.java"))
      assert.is_true(sonar.is_sweep_source("/p/src/main/kotlin/Bar.kt"))
      assert.is_true(sonar.is_sweep_source("/p/build.gradle.kts"))
      assert.is_true(sonar.is_sweep_source("/p/src/main/scala/Baz.scala"))
    end)

    it("rejects other extensions", function()
      assert.is_false(sonar.is_sweep_source("/p/src/Foo.py"))
      assert.is_false(sonar.is_sweep_source("/p/README.md"))
      assert.is_false(sonar.is_sweep_source("/p/no-extension"))
    end)

    it("rejects sources under build-output / VCS trees", function()
      assert.is_false(sonar.is_sweep_source("/p/build/generated/Foo.java"))
      assert.is_false(sonar.is_sweep_source("/p/target/classes/Bar.java"))
      assert.is_false(sonar.is_sweep_source("/p/.git/x/Baz.kt"))
      assert.is_false(sonar.is_sweep_source("/p/node_modules/pkg/Q.scala"))
    end)
  end)

  describe("collect_sources", function()
    it("returns sorted, de-duplicated, build-tree-filtered sources under root", function()
      local root = vim.fn.tempname()
      vim.fn.mkdir(root .. "/src/main/java", "p")
      vim.fn.mkdir(root .. "/build/generated", "p")
      vim.fn.writefile({ "class B {}" }, root .. "/src/main/java/B.java")
      vim.fn.writefile({ "class A {}" }, root .. "/src/main/java/A.java")
      vim.fn.writefile({ "fun x() {}" }, root .. "/src/main/App.kt")
      vim.fn.writefile({ "class G {}" }, root .. "/build/generated/G.java")
      local got = sonar.collect_sources(root)
      assert.are.same({
        root .. "/src/main/App.kt",
        root .. "/src/main/java/A.java",
        root .. "/src/main/java/B.java",
      }, got)
    end)
  end)

  describe("is_sonar_diagnostic", function()
    it("matches on a sonar* source", function()
      assert.is_true(sonar.is_sonar_diagnostic({ source = "sonarlint" }))
      assert.is_true(sonar.is_sonar_diagnostic({ source = "SonarQube" }))
    end)

    it("matches on a sonarlint namespace name when the source is absent", function()
      assert.is_true(sonar.is_sonar_diagnostic({}, "vim.lsp.sonarlint.1.-1"))
    end)

    it("rejects unrelated diagnostics", function()
      assert.is_false(sonar.is_sonar_diagnostic({ source = "checkstyle" }, "vim.lsp.jdtls.1"))
      assert.is_false(sonar.is_sonar_diagnostic("not a table"))
    end)
  end)

  describe("summarize", function()
    it("totals findings, buckets by severity, and ranks rules by count then id", function()
      local s = sonar.summarize({
        { severity = 1, code = "java:S1234" },
        { severity = 2, code = "java:S1234" },
        { severity = 2, code = "java:S0001" },
        { severity = 3, code = "java:S1234" },
        { severity = 2, user_data = { code = "java:S9999" } },
      })
      assert.are.equal(5, s.total)
      assert.are.equal(1, s.by_severity.ERROR)
      assert.are.equal(3, s.by_severity.WARN)
      assert.are.equal(1, s.by_severity.INFO)
      assert.are.equal("java:S1234", s.rules[1].code)
      assert.are.equal(3, s.rules[1].count)
      -- equal-count rules fall back to lexical id order
      assert.are.equal("java:S0001", s.rules[2].code)
      assert.are.equal("java:S9999", s.rules[3].code)
    end)

    it("handles an empty / nil list", function()
      assert.are.same({ total = 0, by_severity = {}, rules = {} }, sonar.summarize(nil))
    end)
  end)
end)

-- Migrated from scripts/validate-6.sh steps [2/6] and [5/6]: the cve / lint /
-- sonar function surface, the :TetraVimSonar* commands, the plugin / keymap /
-- whichkey / mason / bootstrap wiring markers, the <leader>x keymaps and the two
-- Epic 6 :checkhealth sections. The functional CVE report parsing / scan
-- branches (steps [3]-[4]) are already covered in cve_spec.lua, and the pure
-- sonar parser / backend selection above.
describe("Epic 6 module surface + wiring (static)", function()
  local sonar = require("tetravim.util.quality.sonar")
  local function read(path)
    local fh = assert(io.open(path, "r"))
    local body = fh:read("*a")
    fh:close()
    return body
  end

  it("util/cve exposes the documented function surface", function()
    local cve = require("tetravim.util.quality.cve")
    for _, fn in ipairs({
      "scan",
      "scan_command",
      "parse_results",
      "remediation_hint",
      "locate_coordinate",
      "build_diagnostics",
      "publish_diagnostics",
      "clear_diagnostics",
      "project_scan",
      "render_report",
    }) do
      assert.are.equal("function", type(cve[fn]), "util/cve missing " .. fn)
    end
    assert.is_truthy(cve.render_report({}, "/x"):match("No known vulnerabilities"))
  end)

  it("util/lint exposes lint_now / fix_now / project_run / project_plan + buffer_fix_argv", function()
    local lint = require("tetravim.util.edit.lint")
    for _, fn in ipairs({ "lint_now", "fix_now", "project_run", "project_plan" }) do
      assert.are.equal("function", type(lint[fn]), "util/lint missing " .. fn)
    end
    assert.are.equal("table", type(lint.buffer_fix_argv))
    assert.are.equal("function", type(lint.buffer_fix_argv.java))
  end)

  it("util/sonar exposes its full function surface", function()
    for _, fn in ipairs({
      "language_server_cmd",
      "analyzer_paths",
      "settings_from_properties",
      "project_key",
      "find_project_settings",
      "has_language_server",
      "has_scanner",
      "choose_backend",
      "parse_report_task",
      "report_task_path",
      "is_sweep_source",
      "collect_sources",
      "is_sonar_diagnostic",
      "summarize",
      "scan_cli",
      "sweep",
      "project_scan",
    }) do
      assert.are.equal("function", type(sonar[fn]), "util/sonar missing " .. fn)
    end
  end)

  it("util/sonar registers :TetraVimSonarScan / Sweep / Scanner", function()
    for _, cmd in ipairs({ "TetraVimSonarScan", "TetraVimSonarSweep", "TetraVimSonarScanner" }) do
      assert.are.equal(2, vim.fn.exists(":" .. cmd), "missing :" .. cmd)
    end
  end)

  it("lsp-sonarlint.lua references sonarlint.nvim and pcall-guards its setup", function()
    local body = read("lua/tetravim/plugins/lsp-sonarlint.lua")
    assert.is_truthy(body:match("sonarlint%.nvim"))
    assert.is_truthy(body:match("pcall"))
  end)

  it("tools-mason.lua ensures sonarlint-language-server", function()
    assert.is_truthy(read("lua/tetravim/plugins/tools-mason.lua"):match("sonarlint%-language%-server"))
  end)

  it("ui-whichkey.lua registers the <leader>x group", function()
    assert.is_truthy(read("lua/tetravim/plugins/ui-whichkey.lua"):match('"<leader>x"'))
  end)

  it("bootstrap.sh installs osv-scanner and the sonar-scanner CLI", function()
    local body = read("bootstrap.sh")
    assert.is_truthy(body:match("osv%-scanner"))
    assert.is_truthy(body:match("sonarqube%-scanner"))
  end)

  it("core/keymaps.lua binds every <leader>x quality/security key", function()
    require("tetravim.core.keymaps")
    local maps = vim.api.nvim_get_keymap("n")
    -- nvim_get_keymap returns lhs with <leader> already resolved, so match the
    -- trailing suffix (this mirrors scripts/validate-6.sh step [5]).
    local function bound(suffix)
      for _, m in ipairs(maps) do
        if m.lhs:match(vim.pesc(suffix) .. "$") then
          return true
        end
      end
      return false
    end
    for _, k in ipairs({ "xdb", "xdp", "xlb", "xlf", "xlp", "xlF", "xsb", "xsp", "xvb", "xvp", "xvc" }) do
      assert.is_true(bound(k), "<leader>" .. k .. " not bound")
    end
  end)

  it("health.check emits the SonarLint and CVE sections", function()
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

    local joined = table.concat(sections, "\n")
    assert.is_truthy(joined:match("SonarLint"))
    assert.is_truthy(joined:match("CVE"))
  end)
end)
