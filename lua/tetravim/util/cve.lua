-- TetraVim Dependency Vulnerability / CVE Scanning (Epic 6, Story 6.2)
--
-- An async `osv-scanner` wrapper modeled in shape on util/grpc.lua's
-- `run()`: an `executable` guard with an install hint, an explicit
-- `timeout`, a timeout-code branch, a `vim.schedule`d callback, and
-- `ui.notify_err` with captured stderr on a genuine failure. osv-scanner
-- itself is a real binary shelled out via `vim.system` -- no advisory-feed
-- or version-range logic is reimplemented in Lua beyond walking its JSON
-- report.
--
-- `parse_results`, `remediation_hint`, `locate_coordinate` and
-- `build_diagnostics` are pure: they turn the JSON report into a sorted,
-- de-duplicated finding list, human-readable upgrade hints, and
-- `vim.diagnostic` entries anchored to the offending dependency line in the
-- build file -- the same read-and-transform discipline as util/grpc.lua's
-- pure output walkers.

local ui = require("tetravim.util.ui")

local M = {}

-- A dependency tree can be large and osv-scanner resolves it against the
-- OSV.dev feeds, so give it a longer leash than the gRPC calls -- but still
-- a hard ceiling so a hung network call cannot leave the async scan running
-- forever with no feedback. Override per call via `scan(target, cb, { timeout_ms })`
-- or globally via `require('tetravim.util.cve').OSV_TIMEOUT_MS = ...`.
M.OSV_TIMEOUT_MS = 45000

local INSTALL_HINT = "`osv-scanner` is not installed or not on $PATH. Install it (e.g. `brew install osv-scanner`, "
  .. "`go install github.com/google/osv-scanner/cmd/osv-scanner@latest`, or a release from "
  .. "https://github.com/google/osv-scanner/releases) to scan Maven/Gradle dependencies for known CVEs."

--- Whether `osv-scanner` is callable; notifies with an install hint if not.
---@return boolean
local function has_osv_scanner()
  if vim.fn.executable("osv-scanner") ~= 1 then
    ui.notify_err(INSTALL_HINT)
    return false
  end
  return true
end

-- ---------------------------------------------------------------------------
-- Pure JSON report walkers (no advisory logic).
-- ---------------------------------------------------------------------------

--- Parse an `osv-scanner --format json` report into a sorted,
--- de-duplicated list of vulnerable packages:
---   { package, ecosystem, current_version, vuln_ids[], fixed_versions[], summary }
--- `vuln_ids` prefer a `CVE-…` alias over the raw OSV/GHSA id when one is
--- present. Malformed / empty input yields `{}` (a clean "nothing found"),
--- never an error.
---@param json_text string
---@return { package: string, ecosystem: string, current_version: string, vuln_ids: string[], fixed_versions: string[], summary: string }[]
function M.parse_results(json_text)
  local ok, decoded = pcall(vim.json.decode, json_text or "")
  if not ok or type(decoded) ~= "table" then
    return {}
  end

  local by_pkg = {}
  for _, result in ipairs(decoded.results or {}) do
    for _, pkg in ipairs(result.packages or {}) do
      local p = pkg.package or {}
      local name = p.name or "?"
      local entry = by_pkg[name]
        or {
          package = name,
          ecosystem = p.ecosystem or "",
          current_version = p.version or "",
          vuln_ids = {},
          fixed_versions = {},
          summary = "",
        }

      local seen_ids = {}
      for _, id in ipairs(entry.vuln_ids) do
        seen_ids[id] = true
      end
      local seen_fixed = {}
      for _, fv in ipairs(entry.fixed_versions) do
        seen_fixed[fv] = true
      end

      -- First pass: map every id/alias in an advisory's alias-group to a
      -- single canonical id (a `CVE-…` form preferred) so the same advisory
      -- reported under both a GHSA id and its CVE alias de-dupes to one.
      local canonical = {}
      for _, v in ipairs(pkg.vulnerabilities or {}) do
        local group = {}
        if v.id then
          table.insert(group, v.id)
        end
        for _, alias in ipairs(v.aliases or {}) do
          table.insert(group, alias)
        end
        local preferred
        for _, member in ipairs(group) do
          if tostring(member):match("^CVE%-") then
            preferred = member
            break
          end
        end
        preferred = preferred or group[1]
        if preferred then
          for _, member in ipairs(group) do
            local existing = canonical[member]
            if not existing or (tostring(preferred):match("^CVE%-") and not tostring(existing):match("^CVE%-")) then
              canonical[member] = preferred
            end
          end
        end
      end

      for _, v in ipairs(pkg.vulnerabilities or {}) do
        local primary = canonical[v.id] or v.id
        for _, alias in ipairs(v.aliases or {}) do
          if tostring(alias):match("^CVE%-") then
            primary = canonical[alias] or alias
            break
          end
        end
        if primary and not seen_ids[primary] then
          seen_ids[primary] = true
          table.insert(entry.vuln_ids, primary)
        end
        if entry.summary == "" and type(v.summary) == "string" then
          entry.summary = v.summary
        end
        for _, aff in ipairs(v.affected or {}) do
          for _, range in ipairs(aff.ranges or {}) do
            for _, event in ipairs(range.events or {}) do
              if event.fixed and event.fixed ~= "" and not seen_fixed[event.fixed] then
                seen_fixed[event.fixed] = true
                table.insert(entry.fixed_versions, event.fixed)
              end
            end
          end
        end
      end

      by_pkg[name] = entry
    end
  end

  local out = {}
  for _, entry in pairs(by_pkg) do
    table.sort(entry.vuln_ids)
    table.sort(entry.fixed_versions)
    table.insert(out, entry)
  end
  table.sort(out, function(a, b)
    return a.package < b.package
  end)
  return out
end

--- A one-line, actionable remediation hint for a `parse_results` finding:
--- names the vulnerable coordinate + advisory ids and, when the feed
--- published a fix, the version(s) to upgrade to.
---@param finding { package: string, current_version: string, vuln_ids: string[], fixed_versions: string[] }
---@return string
function M.remediation_hint(finding)
  finding = finding or {}
  local ids = table.concat(finding.vuln_ids or {}, ", ")
  if ids == "" then
    ids = "known advisory"
  end
  local coord = (finding.package or "?") .. " " .. (finding.current_version or "?")
  if finding.fixed_versions and #finding.fixed_versions > 0 then
    return string.format(
      "%s is vulnerable (%s). Upgrade to %s or later.",
      coord,
      ids,
      table.concat(finding.fixed_versions, " / ")
    )
  end
  return string.format(
    "%s is vulnerable (%s). No fixed version is published yet -- apply a mitigation or drop the dependency.",
    coord,
    ids
  )
end

--- 1-indexed line in `lines` (a build file's contents) that declares
--- `package_name`. Matches the full `group:artifact` coordinate first, then
--- the bare artifact id (how Maven `pom.xml` spells it in `<artifactId>`).
--- Returns nil when nothing matches -- the caller anchors the diagnostic to
--- line 1 in that case.
---@param lines string[]
---@param package_name string
---@return integer|nil
function M.locate_coordinate(lines, package_name)
  lines = lines or {}
  package_name = package_name or ""
  local group, artifact = package_name:match("^(.-):(.+)$")

  -- First choice: the full `group:artifact` coordinate on one line
  -- (gradle short form, or a Maven line that spells both out).
  if package_name ~= "" then
    for i, line in ipairs(lines) do
      if line:find(package_name, 1, true) then
        return i
      end
    end
  end

  -- Fallback: the bare artifact id (how Maven `pom.xml` spells it in
  -- `<artifactId>`). A build file can declare several artifacts that share a
  -- short name across different groups, so when a groupId is known, prefer an
  -- artifact line whose surrounding block (±4 lines) also names that group.
  if artifact and artifact ~= "" and artifact ~= package_name then
    local first_match
    for i, line in ipairs(lines) do
      if line:find(artifact, 1, true) then
        first_match = first_match or i
        if group and group ~= "" then
          for j = math.max(1, i - 4), math.min(#lines, i + 4) do
            if lines[j]:find(group, 1, true) then
              return i
            end
          end
        else
          return i
        end
      end
    end
    if first_match then
      return first_match
    end
  end

  return nil
end

-- ---------------------------------------------------------------------------
-- Diagnostics.
-- ---------------------------------------------------------------------------

local NS = vim.api.nvim_create_namespace("tetravim_cve")

--- The diagnostic namespace CVE findings are published under.
---@return integer
function M.namespace()
  return NS
end

--- Turn `parse_results` findings into `vim.diagnostic` entries anchored to
--- each vulnerable dependency's line in `lines`. Pure.
---@param lines string[]
---@param findings table[]
---@return vim.Diagnostic[]
function M.build_diagnostics(lines, findings)
  local diags = {}
  for _, finding in ipairs(findings or {}) do
    local lnum = M.locate_coordinate(lines, finding.package)
    table.insert(diags, {
      lnum = (lnum or 1) - 1,
      col = 0,
      severity = vim.diagnostic.severity.WARN,
      source = "osv-scanner",
      code = (finding.vuln_ids or {})[1],
      message = M.remediation_hint(finding),
    })
  end
  return diags
end

--- Publish CVE findings as diagnostics on `bufnr` (default: current
--- buffer). Returns the diagnostic list that was set.
---@param bufnr integer|nil
---@param findings table[]
---@return vim.Diagnostic[]
function M.publish_diagnostics(bufnr, findings)
  bufnr = bufnr or vim.api.nvim_get_current_buf()
  local lines = vim.api.nvim_buf_get_lines(bufnr, 0, -1, false)
  local diags = M.build_diagnostics(lines, findings)
  vim.diagnostic.set(NS, bufnr, diags)
  return diags
end

--- Clear this module's CVE diagnostics from `bufnr` (default: current buffer).
---@param bufnr integer|nil
function M.clear_diagnostics(bufnr)
  vim.diagnostic.reset(NS, bufnr or vim.api.nvim_get_current_buf())
end

-- ---------------------------------------------------------------------------
-- Async scan.
-- ---------------------------------------------------------------------------

--- The osv-scanner command array for `target`: `--lockfile <file>` for a
--- regular file (a `pom.xml` / `build.gradle`), `-r <dir>` for a directory.
---@param target string
---@return string[]
function M.scan_command(target)
  local stat = vim.uv.fs_stat(target)
  if stat and stat.type == "directory" then
    return { "osv-scanner", "--format", "json", "-r", target }
  end
  return { "osv-scanner", "--format", "json", "--lockfile", target }
end

--- Scan `target` (a Maven/Gradle build file or a project directory) for
--- known CVEs asynchronously, never blocking the UI. `cb(findings)` fires
--- with a `parse_results` list on a successful scan -- including the
--- vulnerabilities-found case (osv-scanner exits 1 but still prints a valid
--- report). On timeout or a genuine error the failure is notified via
--- `ui.notify_err` and `cb(nil, message)` is invoked so a caller can leave
--- any existing diagnostics untouched rather than acting on a stale result.
---@param target string
---@param cb fun(findings: table[]|nil, err: string|nil)|nil
---@param opts? { timeout_ms?: integer }
function M.scan(target, cb, opts)
  if not has_osv_scanner() then
    if type(cb) == "function" then
      cb(nil, "osv-scanner is not installed")
    end
    return
  end
  if type(target) ~= "string" or vim.trim(target) == "" then
    ui.notify_err("osv-scanner: no target path to scan")
    if type(cb) == "function" then
      cb(nil, "no target path to scan")
    end
    return
  end

  local timeout_ms = (opts and opts.timeout_ms) or M.OSV_TIMEOUT_MS

  local function fail(msg)
    ui.notify_err(msg)
    if type(cb) == "function" then
      cb(nil, msg)
    end
  end

  vim.system(M.scan_command(target), { text = true, timeout = timeout_ms }, function(out)
    vim.schedule(function()
      -- vim.system() reports a timeout-triggered kill via code=124/signal.
      if out.code == 124 and out.signal and out.signal ~= 0 then
        fail("osv-scanner timed out after " .. (timeout_ms / 1000) .. "s")
        return
      end
      -- osv-scanner exits 0 when clean and 1 when it FOUND vulnerabilities;
      -- both carry a valid JSON report on stdout. Any other code is a real
      -- error (bad flags, unparsable manifest, network failure...).
      if out.code == 0 or out.code == 1 then
        local decoded_ok, decoded = pcall(vim.json.decode, out.stdout or "")
        if not decoded_ok or type(decoded) ~= "table" or decoded.results == nil then
          -- An exit code that claims "clean" or "vulns found" but carries no
          -- parseable report is a real failure, not an all-clear.
          local detail = out.stderr
          if not detail or detail == "" then
            detail = "exit code " .. tostring(out.code) .. " with no parseable JSON report"
          end
          fail("osv-scanner failed: " .. detail)
          return
        end
        if type(cb) == "function" then
          cb(M.parse_results(out.stdout or ""))
        end
        return
      end
      local detail = out.stderr
      if not detail or detail == "" then
        detail = out.stdout or ("osv-scanner exited with code " .. tostring(out.code))
      end
      fail("osv-scanner failed: " .. detail)
    end)
  end)
end

-- ---------------------------------------------------------------------------
-- Project-wide scan (<leader>xvp).
-- ---------------------------------------------------------------------------
--
-- `osv-scanner -r <cwd>` walks every manifest / lockfile in the tree. The
-- findings span many files, so -- like util/lint.lua's project pass -- the
-- report renders into a reused persistent split rather than as buffer
-- diagnostics anchored to one build file.

--- Drop `text` into a reused persistent split (mirrors util/lint.lua's
--- `open_in_split`: an unlisted nofile scratch buffer, never a float).
---@param text string
---@param name_hint string
local function open_in_split(text, name_hint)
  local target_win
  for _, win in ipairs(vim.api.nvim_tabpage_list_wins(0)) do
    local bufname = vim.api.nvim_buf_get_name(vim.api.nvim_win_get_buf(win))
    if vim.fs.basename(bufname):match("^" .. vim.pesc(name_hint) .. "%-") then
      target_win = win
      break
    end
  end

  if target_win and vim.api.nvim_win_is_valid(target_win) then
    vim.api.nvim_set_current_win(target_win)
  else
    vim.cmd("botright vsplit")
  end

  local bufnr = vim.api.nvim_create_buf(false, true)
  vim.api.nvim_win_set_buf(0, bufnr)
  vim.api.nvim_buf_set_lines(bufnr, 0, -1, false, vim.split(text, "\n", { plain = true }))
  vim.bo[bufnr].buftype = "nofile"
  vim.bo[bufnr].bufhidden = "wipe"
  vim.bo[bufnr].swapfile = false
  vim.bo[bufnr].filetype = "log"
  vim.bo[bufnr].modified = false
  pcall(vim.api.nvim_buf_set_name, bufnr, name_hint .. "-" .. tostring(bufnr))
end

--- Render `parse_results` findings as a plain-text report. Pure.
---@param findings table[]|nil
---@param root string
---@return string
function M.render_report(findings, root)
  findings = findings or {}
  local lines = {
    ("# TetraVim CVE scan -- %s"):format(os.date("%Y-%m-%d %H:%M:%S")),
    ("# root: %s"):format(root),
    ("# osv-scanner: %d vulnerable package(s)"):format(#findings),
    "",
  }
  if #findings == 0 then
    table.insert(lines, "No known vulnerabilities found.")
    return table.concat(lines, "\n")
  end
  for _, f in ipairs(findings) do
    local version = (f.current_version ~= nil and f.current_version ~= "") and f.current_version or "?"
    local eco = (f.ecosystem ~= nil and f.ecosystem ~= "") and f.ecosystem or "?"
    table.insert(lines, ("* %s@%s [%s]"):format(f.package or "?", version, eco))
    table.insert(lines, "    " .. M.remediation_hint(f))
    if f.summary and f.summary ~= "" then
      table.insert(lines, "    " .. f.summary)
    end
    table.insert(lines, "")
  end
  return table.concat(lines, "\n")
end

--- Scan the whole project directory (`osv-scanner -r`) for known CVEs and
--- render the report in a persistent split. The buffer-scoped twin is
--- `scan(<build file>, ...)` + `publish_diagnostics`.
---@param root? string  defaults to the current working directory
function M.project_scan(root)
  root = (type(root) == "string" and vim.trim(root) ~= "") and root or vim.fn.getcwd()
  ui.notify_info("Scanning project dependencies for known CVEs (osv-scanner -r)...")
  M.scan(root, function(findings, _err)
    if not findings then
      return -- scan() already notified the failure
    end
    open_in_split(M.render_report(findings, root), "tetravim-cve")
    if #findings == 0 then
      ui.notify_info("osv-scanner: no known vulnerabilities in the project")
    else
      ui.notify_warn(("osv-scanner: %d vulnerable package(s) in the project -- see the report split"):format(#findings))
    end
  end, { timeout_ms = math.max(M.OSV_TIMEOUT_MS, 120000) })
end

return M
