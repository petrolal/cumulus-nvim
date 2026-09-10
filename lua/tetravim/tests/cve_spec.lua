-- Unit tests for tetravim.util.quality.cve (Epic 6, Story 6.2)
--
-- Covers the pure JSON report walkers (parse_results / remediation_hint /
-- locate_coordinate / build_diagnostics), the missing-`osv-scanner`
-- executable guard, scan command-array construction, and the async result
-- branches (clean, vulns-found, timeout, generic error). `vim.system` is
-- always monkeypatched -- no real binary is ever spawned.

describe("tetravim.util.quality.cve", function()
  local cve = require("tetravim.util.quality.cve")

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
      if name == "osv-scanner" then
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

  -- A representative osv-scanner --format json report: two vulnerable Maven
  -- packages, one with a published fix, one without; a CVE alias to prefer
  -- over the raw GHSA id; a duplicate advisory id to de-dupe.
  local REPORT = vim.json.encode({
    results = {
      {
        source = { path = "/proj/pom.xml", type = "lockfile" },
        packages = {
          {
            package = { name = "com.fasterxml.jackson.core:jackson-databind", version = "2.9.8", ecosystem = "Maven" },
            vulnerabilities = {
              {
                id = "GHSA-aaaa-bbbb-cccc",
                summary = "Deserialization of untrusted data",
                aliases = { "CVE-2020-1234" },
                affected = {
                  { ranges = { { type = "ECOSYSTEM", events = { { introduced = "0" }, { fixed = "2.9.10" } } } } },
                },
              },
              { id = "GHSA-aaaa-bbbb-cccc", aliases = {}, affected = {} },
            },
          },
          {
            package = { name = "org.example:legacy-lib", version = "1.0.0", ecosystem = "Maven" },
            vulnerabilities = {
              { id = "OSV-2021-9999", summary = "No fix available", aliases = {}, affected = {} },
            },
          },
        },
      },
    },
  })

  describe("parse_results", function()
    it("returns a sorted, de-duplicated finding list preferring CVE aliases", function()
      local findings = cve.parse_results(REPORT)
      assert.are.equal(2, #findings)
      -- sorted by package name
      assert.are.equal("com.fasterxml.jackson.core:jackson-databind", findings[1].package)
      assert.are.equal("org.example:legacy-lib", findings[2].package)

      assert.are.equal("2.9.8", findings[1].current_version)
      assert.are.same({ "CVE-2020-1234" }, findings[1].vuln_ids)
      assert.are.same({ "2.9.10" }, findings[1].fixed_versions)

      assert.are.same({ "OSV-2021-9999" }, findings[2].vuln_ids)
      assert.are.same({}, findings[2].fixed_versions)
    end)

    it("returns {} for malformed / empty input, never erroring", function()
      assert.are.same({}, cve.parse_results("{ not json ]"))
      assert.are.same({}, cve.parse_results(""))
      assert.are.same({}, cve.parse_results(nil))
    end)

    it("returns {} for a clean report with no results", function()
      assert.are.same({}, cve.parse_results(vim.json.encode({ results = {} })))
    end)
  end)

  describe("remediation_hint", function()
    it("names the coordinate, advisory ids and the upgrade target when a fix exists", function()
      local hint = cve.remediation_hint({
        package = "org.foo:bar",
        current_version = "1.2.3",
        vuln_ids = { "CVE-2021-1", "CVE-2021-2" },
        fixed_versions = { "1.2.4", "2.0.0" },
      })
      assert.is_truthy(hint:find("org.foo:bar 1.2.3", 1, true))
      assert.is_truthy(hint:find("CVE-2021-1, CVE-2021-2", 1, true))
      assert.is_truthy(hint:find("1.2.4 / 2.0.0", 1, true))
    end)

    it("says no fix is published when fixed_versions is empty", function()
      local hint =
        cve.remediation_hint({ package = "org.foo:bar", current_version = "1.0", vuln_ids = {}, fixed_versions = {} })
      assert.is_truthy(hint:lower():find("no fixed version", 1, true))
    end)
  end)

  describe("locate_coordinate", function()
    it("matches the full group:artifact coordinate", function()
      local lines = { "dependencies {", "  implementation 'com.foo:bar:1.2.3'", "}" }
      assert.are.equal(2, cve.locate_coordinate(lines, "com.foo:bar"))
    end)

    it("falls back to the bare artifact id (Maven <artifactId>)", function()
      local lines =
        { "<dependency>", "  <groupId>com.foo</groupId>", "  <artifactId>bar</artifactId>", "</dependency>" }
      assert.are.equal(3, cve.locate_coordinate(lines, "com.foo:bar"))
    end)

    it("returns nil when nothing matches", function()
      assert.is_nil(cve.locate_coordinate({ "nothing here" }, "com.foo:bar"))
    end)
  end)

  describe("build_diagnostics", function()
    it("anchors a WARN diagnostic to the offending line, or line 1 when unlocatable", function()
      local lines = { "<project>", "  <artifactId>jackson-databind</artifactId>", "</project>" }
      local findings = cve.parse_results(REPORT)
      local diags = cve.build_diagnostics(lines, findings)
      assert.are.equal(2, #diags)
      -- jackson-databind is on line 2 -> lnum 1 (0-indexed)
      assert.are.equal(1, diags[1].lnum)
      assert.are.equal(vim.diagnostic.severity.WARN, diags[1].severity)
      assert.are.equal("osv-scanner", diags[1].source)
      assert.are.equal("CVE-2020-1234", diags[1].code)
      -- legacy-lib is not in the build file -> anchored to line 1 (lnum 0)
      assert.are.equal(0, diags[2].lnum)
    end)
  end)

  describe("scan_command", function()
    it("uses --lockfile for a regular file", function()
      assert.are.same({ "osv-scanner", "--format", "json", "--lockfile", "pom.xml" }, cve.scan_command("pom.xml"))
    end)
  end)

  describe("executable guard", function()
    it("fires for scan when osv-scanner is absent -- no process spawned", function()
      vim.fn.executable = function(name)
        if name == "osv-scanner" then
          return 0
        end
        return orig_executable(name)
      end

      cve.scan("pom.xml", function() end)

      assert.are.equal(0, #system_calls)
      local msg = last_error()
      assert.is_truthy(msg)
      assert.is_truthy(tostring(msg):lower():match("install"))
      assert.is_truthy(tostring(msg):match("osv%-scanner"))
    end)

    it("refuses an empty target before spawning", function()
      cve.scan("", function() end)
      assert.are.equal(0, #system_calls)
      assert.is_truthy(last_error())
    end)
  end)

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

    it("passes parsed findings to the callback on a clean (code 0) exit", function()
      local got
      cve.scan("pom.xml", function(findings)
        got = findings
      end)
      assert.is_true(system_calls[1].opts.timeout > 0)
      captured_cb({ code = 0, signal = 0, stdout = vim.json.encode({ results = {} }), stderr = "" })
      assert.are.same({}, got)
      assert.is_nil(last_error())
    end)

    it("treats a code-1 exit as 'vulnerabilities found', not an error", function()
      local got
      cve.scan("pom.xml", function(findings)
        got = findings
      end)
      captured_cb({ code = 1, signal = 0, stdout = REPORT, stderr = "" })
      assert.are.equal(2, #got)
      assert.is_nil(last_error())
    end)

    it("timeout (code 124 + signal) -> notify_err says timed out, callback gets (nil, err)", function()
      local findings_arg, err_arg, called = "sentinel", nil, false
      cve.scan("pom.xml", function(findings, err)
        called, findings_arg, err_arg = true, findings, err
      end)
      captured_cb({ code = 124, signal = 15, stdout = "", stderr = "" })
      assert.is_true(called)
      assert.is_nil(findings_arg)
      assert.is_truthy(tostring(err_arg):lower():match("timed out"))
      assert.is_truthy(tostring(last_error()):lower():match("timed out"))
    end)

    it("a generic nonzero exit -> notify_err surfaces stderr, callback gets (nil, err)", function()
      local findings_arg, err_arg, called = "sentinel", nil, false
      cve.scan("pom.xml", function(findings, err)
        called, findings_arg, err_arg = true, findings, err
      end)
      captured_cb({ code = 127, signal = 0, stdout = "", stderr = "unsupported lockfile" })
      assert.is_true(called)
      assert.is_nil(findings_arg)
      assert.is_truthy(tostring(err_arg):match("unsupported lockfile"))
      assert.is_truthy(tostring(last_error()):match("unsupported lockfile"))
    end)

    it("a code-1 exit with no parseable report is a failure, not an all-clear", function()
      local findings_arg, err_arg, called = "sentinel", nil, false
      cve.scan("pom.xml", function(findings, err)
        called, findings_arg, err_arg = true, findings, err
      end)
      captured_cb({ code = 1, signal = 0, stdout = "not json at all", stderr = "" })
      assert.is_true(called)
      assert.is_nil(findings_arg)
      assert.is_truthy(tostring(err_arg):lower():match("osv%-scanner failed"))
    end)
  end)

  describe("render_report", function()
    it("states the all-clear for an empty / nil finding list", function()
      assert.is_truthy(cve.render_report({}, "/proj"):match("No known vulnerabilities found"))
      assert.is_truthy(cve.render_report(nil, "/proj"):match("No known vulnerabilities found"))
      assert.is_truthy(cve.render_report({}, "/proj"):match("# root: /proj"))
    end)

    it("lists every finding with its coordinate, ecosystem and remediation hint", function()
      local findings = cve.parse_results(REPORT)
      local text = cve.render_report(findings, "/proj")
      assert.is_truthy(text:match("# osv%-scanner: 2 vulnerable package%(s%)"))
      assert.is_truthy(text:find("* com.fasterxml.jackson.core:jackson-databind@2.9.8 [Maven]", 1, true))
      assert.is_truthy(text:find("* org.example:legacy-lib@1.0.0 [Maven]", 1, true))
      -- the remediation hint line names the upgrade target
      assert.is_truthy(text:find("2.9.10", 1, true))
      -- the vulnerability summary is echoed
      assert.is_truthy(text:find("Deserialization of untrusted data", 1, true))
    end)

    it("falls back to '?' for a finding missing version / ecosystem", function()
      local text = cve.render_report({
        { package = "org.foo:bar", current_version = "", ecosystem = "", vuln_ids = {}, fixed_versions = {} },
      }, "/proj")
      assert.is_truthy(text:find("* org.foo:bar@? [?]", 1, true))
    end)
  end)

  describe("project_scan", function()
    local orig_schedule, captured_cb

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
      for _, b in ipairs(vim.api.nvim_list_bufs()) do
        if vim.api.nvim_buf_is_valid(b) and vim.fs.basename(vim.api.nvim_buf_get_name(b)):match("^tetravim%-cve%-") then
          pcall(vim.api.nvim_buf_delete, b, { force = true })
        end
      end
    end)

    it("scans a directory (osv-scanner -r) with a >= 120s timeout", function()
      cve.project_scan(vim.fn.getcwd())
      assert.are.equal(1, #system_calls)
      assert.are.same({ "osv-scanner", "--format", "json", "-r", vim.fn.getcwd() }, system_calls[1].cmd)
      assert.is_true(system_calls[1].opts.timeout >= 120000)
    end)

    it("renders the findings into a persistent 'tetravim-cve-*' split", function()
      cve.project_scan(vim.fn.getcwd())
      captured_cb({ code = 1, signal = 0, stdout = REPORT, stderr = "" })
      local rendered
      for _, b in ipairs(vim.api.nvim_list_bufs()) do
        if vim.fs.basename(vim.api.nvim_buf_get_name(b)):match("^tetravim%-cve%-") then
          rendered = table.concat(vim.api.nvim_buf_get_lines(b, 0, -1, false), "\n")
        end
      end
      assert.is_truthy(rendered)
      assert.is_truthy(rendered:find("jackson-databind", 1, true))
    end)

    it("leaves no split and does not error when the scan fails", function()
      cve.project_scan(vim.fn.getcwd())
      captured_cb({ code = 127, signal = 0, stdout = "", stderr = "boom" })
      for _, b in ipairs(vim.api.nvim_list_bufs()) do
        assert.is_falsy(vim.fs.basename(vim.api.nvim_buf_get_name(b)):match("^tetravim%-cve%-"))
      end
    end)
  end)
end)
