-- TetraVim SonarQube / SonarLint helpers (Epic 6, Story 6.1)
--
-- Resolves everything the SonarLint language server needs to attach for
-- Java / Kotlin / Scala buffers: the Mason-installed `sonarlint-language-server`
-- binary, its bundled analyzer jars, and any project-specific quality
-- profile declared in a `sonar-project.properties` at the project root.
--
-- `settings_from_properties` / `project_key` are pure text parsers (the
-- same read-and-transform discipline as util/grpc.lua's output walkers) --
-- no rule logic, no analysis, and no SonarLint protocol is reimplemented
-- here; that all lives in the language server.

local M = {}

-- The filetypes the SonarLint LS is wired for. Scala rules only work in
-- SonarQube connected mode (no free standalone analyzer is bundled) -- it
-- is still listed so a connected-mode project gets diagnostics.
M.FILETYPES = { "java", "kotlin", "scala" }

--- The Mason package directory for the SonarLint language server.
---@return string
function M.mason_pkg_root()
  return vim.fn.stdpath("data") .. "/mason/packages/sonarlint-language-server"
end

--- Whether the `sonarlint-language-server` binary is callable.
---@return boolean
function M.has_language_server()
  return vim.fn.executable("sonarlint-language-server") == 1
end

--- Sorted list of the analyzer jars bundled with the Mason package
--- (`extension/analyzers/*.jar` -- sonarjava, sonarkotlin, ...). Empty when
--- the package is not installed; the LS then falls back to connected-mode
--- analyzers or its own defaults.
---@return string[]
function M.analyzer_paths()
  local dir = M.mason_pkg_root() .. "/extension/analyzers"
  local jars = vim.fn.glob(dir .. "/*.jar", true, true)
  if type(jars) ~= "table" then
    jars = {}
  end
  table.sort(jars)
  return jars
end

-- Whether to pass the Mason-bundled analyzer jars explicitly via `-analyzers`.
-- The SonarLint LS discovers its bundled analyzers on its own; we only pass
-- them when this is set so a future Mason package layout change (jars moved,
-- renamed, or an incompatible `-analyzers` contract) degrades to the LS's own
-- discovery instead of a hard cmd error. Flip to false to opt out.
M.USE_BUNDLED_ANALYZERS = true

--- The full `sonarlint-language-server` command array (`-stdio`, plus
--- `-analyzers <jar>...` when any are bundled and `USE_BUNDLED_ANALYZERS` is
--- set), or nil when the binary is absent.
---@return string[]|nil
function M.language_server_cmd()
  if not M.has_language_server() then
    return nil
  end
  local cmd = { "sonarlint-language-server", "-stdio" }
  local jars = M.USE_BUNDLED_ANALYZERS and M.analyzer_paths() or {}
  if #jars > 0 then
    table.insert(cmd, "-analyzers")
    for _, jar in ipairs(jars) do
      table.insert(cmd, jar)
    end
  end
  return cmd
end

--- Parse a `sonar-project.properties` text blob into a flat key/value map.
--- `#` / `!` comment lines and blank lines are skipped; keys and values are
--- trimmed; both `key=value` and `key:value` separators are accepted. Pure
--- -- no file IO.
---@param text string
---@return table<string, string>
function M.settings_from_properties(text)
  local out = {}
  for _, raw in ipairs(vim.split(text or "", "\n", { plain = true })) do
    local line = vim.trim(raw)
    if line ~= "" and not line:match("^[#!]") then
      local k, v = line:match("^([^=:]+)[=:](.*)$")
      if k and vim.trim(k) ~= "" then
        out[vim.trim(k)] = vim.trim(v)
      end
    end
  end
  return out
end

--- The `sonar.projectKey` declared in a properties blob, or nil.
---@param text string
---@return string|nil
function M.project_key(text)
  return M.settings_from_properties(text)["sonar.projectKey"]
end

--- Locate + parse the nearest `sonar-project.properties`, searching `root`
--- (default: cwd) and then every parent directory up to the filesystem root
--- -- a monorepo commonly keeps it a level or two above the buffer's module.
--- Returns the settings map, or nil when no file is found / it is unreadable.
---@param root string|nil
---@return table<string, string>|nil
function M.find_project_settings(root)
  root = root or vim.fn.getcwd()
  local found = vim.fs.find("sonar-project.properties", {
    path = root,
    upward = true,
    type = "file",
    limit = 1,
  })
  local path = found[1]
  if not path then
    return nil
  end
  local ok, lines = pcall(vim.fn.readfile, path)
  if not ok then
    return nil
  end
  return M.settings_from_properties(table.concat(lines, "\n"))
end

-- ===========================================================================
-- Project-wide analysis (Story 6.1 extension)
-- ===========================================================================
--
-- The SonarLint LS wired in lsp-sonarlint.lua only analyses files that are
-- actually open. Whole-codebase coverage is offered two ways, mirroring the
-- shell-out + persistent-split discipline of util/lint.lua's `project_run`:
--
--   * "cli"   -- shell out to the official `sonar-scanner` against a
--                `sonar-project.properties` that declares `sonar.host.url`
--                (SonarQube connected mode). Renders the scanner log and the
--                dashboard task URL in a persistent split.
--   * "sweep" -- server-free. Load every Java/Kotlin/Scala source into a
--                hidden buffer, let the already-configured SonarLint LS
--                analyse each, then aggregate every finding into the
--                quickfix list plus a summary split.
--
-- `project_scan()` picks automatically: "cli" when a host URL is declared
-- and `sonar-scanner` is callable, "sweep" otherwise. Everything is
-- pcall/executable-guarded and degrades to a single `ui.notify_*` call.

--- Whether the official `sonar-scanner` CLI is callable.
---@return boolean
function M.has_scanner()
  return vim.fn.executable("sonar-scanner") == 1
end

--- Which project-wide backend applies given the resolved properties map and
--- whether `sonar-scanner` is on $PATH. Pure.
---@param settings table<string, string>|nil
---@param has_scanner boolean
---@return "cli"|"sweep"
function M.choose_backend(settings, has_scanner)
  if has_scanner and type(settings) == "table" and vim.trim(settings["sonar.host.url"] or "") ~= "" then
    return "cli"
  end
  return "sweep"
end

-- A full-project scanner run resolves the analysis server-side; give it a
-- long leash but still a hard ceiling. Override per call via
-- `scan_cli(root, cb, { timeout_ms = ... })`.
M.SCANNER_TIMEOUT_MS = 600000

--- Path to the report descriptor `sonar-scanner` drops after a successful
--- run (`dashboardUrl`, `ceTaskUrl`, ...).
---@param root string|nil
---@return string
function M.report_task_path(root)
  return (root or vim.fn.getcwd()) .. "/.scannerwork/report-task.txt"
end

--- Parse a `report-task.txt` blob into a flat map. Its lines are strictly
--- `key=value` and the values are URLs that themselves contain `=`, so this
--- splits on the FIRST `=` only (unlike `settings_from_properties`, which
--- also accepts `:` -- a URL scheme separator). Pure -- no file IO.
---@param text string
---@return table<string, string>
function M.parse_report_task(text)
  local out = {}
  for _, raw in ipairs(vim.split(text or "", "\n", { plain = true })) do
    local k, v = vim.trim(raw):match("^([^=]+)=(.*)$")
    if k and vim.trim(k) ~= "" then
      out[vim.trim(k)] = vim.trim(v)
    end
  end
  return out
end

--- Run `sonar-scanner` in `root` asynchronously (never blocks the UI).
--- `cb(result, err)` fires on `vim.schedule` with, on success:
---   { code, timed_out, stdout, stderr, dashboard_url?, ce_task_url? }
--- and on a missing binary `cb(nil, msg)`. A non-zero `code` is left for the
--- caller to surface -- the scanner exits non-zero on a failed quality gate,
--- which is still a completed analysis.
---@param root string|nil
---@param cb fun(result: table|nil, err: string|nil)|nil
---@param opts? { timeout_ms?: integer }
function M.scan_cli(root, cb, opts)
  root = root or vim.fn.getcwd()
  if not M.has_scanner() then
    if type(cb) == "function" then
      cb(nil, "sonar-scanner is not installed or not on $PATH")
    end
    return
  end
  local timeout = (opts and opts.timeout_ms) or M.SCANNER_TIMEOUT_MS
  vim.system({ "sonar-scanner" }, { cwd = root, text = true, timeout = timeout }, function(res)
    vim.schedule(function()
      local report
      local ok, lines = pcall(vim.fn.readfile, M.report_task_path(root))
      if ok and type(lines) == "table" then
        report = M.parse_report_task(table.concat(lines, "\n"))
      end
      if type(cb) == "function" then
        cb({
          code = res.code or -1,
          timed_out = (res.code == 124 and res.signal and res.signal ~= 0) or false,
          stdout = res.stdout or "",
          stderr = res.stderr or "",
          dashboard_url = report and report["dashboardUrl"] or nil,
          ce_task_url = report and report["ceTaskUrl"] or nil,
        })
      end
    end)
  end)
end

-- --------------------------------------------------------------------------
-- Server-free sweep.
-- --------------------------------------------------------------------------

-- Source extensions the SonarLint LS analyses standalone, mapped to the
-- filetype its `sonarlint.nvim` FileType autocmd keys on.
M.SWEEP_EXT_FT = { java = "java", kt = "kotlin", kts = "kotlin", scala = "scala" }

-- Build-output / VCS / tooling trees never worth analysing.
M.SWEEP_SKIP_DIRS = { "build", "target", "out", "bin", ".git", "node_modules", ".gradle", ".idea", ".scannerwork" }

-- Cap the number of buffers a single sweep will open, and how long to wait
-- for the LS to finish publishing before aggregating what it has.
M.SWEEP_MAX_FILES = 1000
M.SWEEP_TIMEOUT_MS = 120000
M.SWEEP_SETTLE_MS = 800

--- Whether `path` is a source file the sweep should feed to the LS (right
--- extension, not under a build-output tree). Pure.
---@param path string
---@return boolean
function M.is_sweep_source(path)
  path = path or ""
  local ext = path:match("%.([%w]+)$")
  if not ext or not M.SWEEP_EXT_FT[ext] then
    return false
  end
  for _, seg in ipairs(M.SWEEP_SKIP_DIRS) do
    if path:find("[/\\]" .. vim.pesc(seg) .. "[/\\]") then
      return false
    end
  end
  return true
end

--- Every Java/Kotlin/Scala source under `root` the sweep would analyse,
--- sorted and de-duplicated.
---@param root string|nil
---@return string[]
function M.collect_sources(root)
  root = root or vim.fn.getcwd()
  local seen, files = {}, {}
  for ext in pairs(M.SWEEP_EXT_FT) do
    local matches = vim.fn.globpath(root, "**/*." .. ext, false, true)
    if type(matches) == "table" then
      for _, f in ipairs(matches) do
        if not seen[f] and M.is_sweep_source(f) then
          seen[f] = true
          files[#files + 1] = f
        end
      end
    end
  end
  table.sort(files)
  return files
end

--- Whether a diagnostic (optionally tagged with the name of the namespace it
--- came from) was produced by SonarLint. Pure.
---@param d table
---@param ns_name string|nil
---@return boolean
function M.is_sonar_diagnostic(d, ns_name)
  if type(d) ~= "table" then
    return false
  end
  if type(d.source) == "string" and d.source:lower():find("sonar", 1, true) then
    return true
  end
  if type(ns_name) == "string" and ns_name:lower():find("sonarlint", 1, true) then
    return true
  end
  return false
end

--- Roll a flat diagnostic list up into `{ total, by_severity, rules[] }`
--- where `rules` is sorted by descending count then rule id. Pure.
---@param diags table[]
---@return { total: integer, by_severity: table<string, integer>, rules: { code: string, count: integer }[] }
function M.summarize(diags)
  local names = { [1] = "ERROR", [2] = "WARN", [3] = "INFO", [4] = "HINT" }
  local by_severity, by_rule = {}, {}
  for _, d in ipairs(diags or {}) do
    local sev = names[d.severity] or "WARN"
    by_severity[sev] = (by_severity[sev] or 0) + 1
    local code = d.code or (type(d.user_data) == "table" and d.user_data.code) or "(no rule)"
    by_rule[tostring(code)] = (by_rule[tostring(code)] or 0) + 1
  end
  local rules = {}
  for code, count in pairs(by_rule) do
    rules[#rules + 1] = { code = code, count = count }
  end
  table.sort(rules, function(a, b)
    if a.count ~= b.count then
      return a.count > b.count
    end
    return a.code < b.code
  end)
  return { total = #(diags or {}), by_severity = by_severity, rules = rules }
end

--- Drop `text` into a reused persistent split -- the same unlisted `nofile`
--- scratch-buffer discipline as util/lint.lua's `open_in_split` and
--- keymaps.lua's `tetravim_http_open_in_split`, never a float.
---@param text string
---@param name_hint string
local function open_report_split(text, name_hint)
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

--- Render the outcome of a `scan_cli` run into the shared persistent split.
---@param root string
---@param result table
function M.render_cli_report(root, result)
  local lines = {
    ("# TetraVim Sonar scan (sonar-scanner) -- %s"):format(os.date("%Y-%m-%d %H:%M:%S")),
    ("# root: %s   exit: %d%s"):format(root, result.code, result.timed_out and " (TIMED OUT)" or ""),
  }
  if result.dashboard_url then
    lines[#lines + 1] = ("# dashboard: %s"):format(result.dashboard_url)
  end
  if result.ce_task_url then
    lines[#lines + 1] = ("# ce task:   %s"):format(result.ce_task_url)
  end
  lines[#lines + 1] = ""
  local out = vim.trim((result.stdout or "") .. "\n" .. (result.stderr or ""))
  for l in vim.gsplit(out == "" and "(no output)" or out, "\n", { plain = true }) do
    lines[#lines + 1] = l
  end
  open_report_split(table.concat(lines, "\n"), "tetravim-sonar")
end

--- Analyse every Java/Kotlin/Scala source under `root` with the SonarLint LS
--- and aggregate the findings into the quickfix list + a summary split.
--- Server-free. `cb(summary, err)` fires on completion.
---@param root string|nil
---@param cb fun(summary: table|nil, err: string|nil)|nil
---@param opts? { timeout_ms?: integer, max_files?: integer }
function M.sweep(root, cb, opts)
  local ui = require("tetravim.util.ui")
  root = root or vim.fn.getcwd()
  opts = opts or {}

  if not M.has_language_server() then
    ui.notify_err(
      "sonarlint-language-server not found -- run :MasonInstall sonarlint-language-server for a project sweep"
    )
    if type(cb) == "function" then
      cb(nil, "sonarlint-language-server missing")
    end
    return
  end

  -- Force the ft-lazy sonarlint.nvim bridge to load now so its FileType
  -- autocmd exists before we replay FileType for the swept buffers.
  pcall(function()
    require("lazy").load({ plugins = { "sonarlint.nvim" } })
  end)
  if not pcall(require, "sonarlint") then
    ui.notify_err("sonarlint.nvim is not available -- run :Lazy sync")
    if type(cb) == "function" then
      cb(nil, "sonarlint.nvim missing")
    end
    return
  end

  local files = M.collect_sources(root)
  local max_files = opts.max_files or M.SWEEP_MAX_FILES
  local truncated = #files > max_files
  if truncated then
    files = vim.list_slice(files, 1, max_files)
  end
  if #files == 0 then
    ui.notify_warn("Sonar sweep: no Java/Kotlin/Scala sources under " .. root)
    if type(cb) == "function" then
      cb(M.summarize({}))
    end
    return
  end

  ui.notify_info(("Sonar sweep: analysing %d file(s)%s..."):format(#files, truncated and " (capped)" or ""))

  -- Load every target into a buffer and replay FileType so sonarlint.nvim
  -- attaches its LS. Track the buffers we created so they can be wiped after.
  local bufs, created = {}, {}
  for _, file in ipairs(files) do
    local existed = vim.fn.bufloaded(file) == 1
    local buf = vim.fn.bufadd(file)
    if not existed then
      pcall(vim.fn.bufload, buf)
      created[buf] = true
    end
    if vim.bo[buf].filetype == "" then
      local ext = file:match("%.([%w]+)$")
      vim.bo[buf].filetype = M.SWEEP_EXT_FT[ext] or ""
    end
    pcall(vim.api.nvim_exec_autocmds, "FileType", { buffer = buf, modeline = false })
    bufs[#bufs + 1] = buf
  end

  local function collect()
    local ns_names = {}
    for id, meta in pairs(vim.diagnostic.get_namespaces()) do
      ns_names[id] = meta and meta.name or nil
    end
    local all, items = {}, {}
    for _, buf in ipairs(bufs) do
      if vim.api.nvim_buf_is_valid(buf) then
        for _, d in ipairs(vim.diagnostic.get(buf)) do
          if M.is_sonar_diagnostic(d, ns_names[d.namespace]) then
            all[#all + 1] = d
            items[#items + 1] = {
              filename = vim.api.nvim_buf_get_name(buf),
              lnum = (d.lnum or 0) + 1,
              col = (d.col or 0) + 1,
              text = ("[%s] %s"):format(d.code or "?", (d.message or ""):gsub("%s+", " ")),
              type = d.severity == vim.diagnostic.severity.ERROR and "E" or "W",
            }
          end
        end
      end
    end
    return all, items
  end

  -- Poll until the finding count holds steady across two ticks or the hard
  -- timeout elapses, then aggregate and clean up.
  local timeout_ms = opts.timeout_ms or M.SWEEP_TIMEOUT_MS
  local elapsed, last_count, stable = 0, -1, 0
  local timer = assert(vim.uv.new_timer())

  local function finish()
    if timer:is_closing() then
      return
    end
    timer:stop()
    timer:close()
    local diags, items = collect()
    for buf in pairs(created) do
      if vim.api.nvim_buf_is_valid(buf) and #vim.fn.win_findbuf(buf) == 0 then
        pcall(vim.api.nvim_buf_delete, buf, { force = true })
      end
    end
    local summary = M.summarize(diags)
    vim.fn.setqflist({}, " ", { title = "SonarLint project sweep", items = items })

    local report = {
      ("# TetraVim Sonar sweep -- %s"):format(os.date("%Y-%m-%d %H:%M:%S")),
      ("# root: %s"):format(root),
      ("# files analysed: %d%s"):format(#files, truncated and (" (capped at %d)"):format(max_files) or ""),
      ("# findings: %d  (E:%d  W:%d  I:%d)"):format(
        summary.total,
        summary.by_severity.ERROR or 0,
        summary.by_severity.WARN or 0,
        summary.by_severity.INFO or 0
      ),
      "# quickfix list populated -- :copen to browse every finding",
      "",
      "## Top rules",
    }
    if #summary.rules == 0 then
      report[#report + 1] = "(no SonarLint findings)"
    end
    for i, r in ipairs(summary.rules) do
      if i > 40 then
        break
      end
      report[#report + 1] = ("  %5d  %s"):format(r.count, r.code)
    end
    open_report_split(table.concat(report, "\n"), "tetravim-sonar")
    ui.notify_info(("Sonar sweep: %d finding(s) across %d file(s) -- :copen"):format(summary.total, #files))
    if type(cb) == "function" then
      cb(summary)
    end
  end

  timer:start(
    M.SWEEP_SETTLE_MS,
    M.SWEEP_SETTLE_MS,
    vim.schedule_wrap(function()
      elapsed = elapsed + M.SWEEP_SETTLE_MS
      local diags = collect()
      if #diags == last_count then
        stable = stable + 1
      else
        stable = 0
        last_count = #diags
      end
      -- Require at least one non-empty observation before trusting a steady
      -- zero, so a slow LS start is not mistaken for a clean project.
      if (stable >= 2 and (last_count > 0 or elapsed >= 8000)) or elapsed >= timeout_ms then
        finish()
      end
    end)
  )
end

--- Auto-select the backend and run a whole-codebase Sonar analysis.
---@param root string|nil
function M.project_scan(root)
  local ui = require("tetravim.util.ui")
  root = root or vim.fn.getcwd()
  local settings = M.find_project_settings(root)
  local backend = M.choose_backend(settings, M.has_scanner())

  if backend == "cli" then
    ui.notify_info(
      "Sonar: running sonar-scanner against " .. (settings["sonar.host.url"] or "the configured server") .. "..."
    )
    M.scan_cli(root, function(result, err)
      if not result then
        ui.notify_err("sonar-scanner: " .. (err or "failed"))
        return
      end
      M.render_cli_report(root, result)
      if result.timed_out then
        ui.notify_err(("sonar-scanner timed out after %ds"):format(M.SCANNER_TIMEOUT_MS / 1000))
      elseif result.code == 0 then
        ui.notify_info("sonar-scanner finished" .. (result.dashboard_url and (" -- " .. result.dashboard_url) or ""))
      else
        ui.notify_warn(("sonar-scanner exited %d -- see the report split"):format(result.code))
      end
    end)
    return
  end

  M.sweep(root)
end

-- User commands (mirrors util/coverage.lua's register-on-require pattern).
-- `:TetraVimSonarScan` auto-selects; the two explicit forms force a backend.
pcall(vim.api.nvim_create_user_command, "TetraVimSonarScan", function()
  M.project_scan()
end, { desc = "Sonar: analyse the whole codebase (auto backend)" })

pcall(vim.api.nvim_create_user_command, "TetraVimSonarSweep", function()
  M.sweep()
end, { desc = "Sonar: server-free SonarLint sweep of every JVM source -> quickfix" })

pcall(vim.api.nvim_create_user_command, "TetraVimSonarScanner", function()
  local ui = require("tetravim.util.ui")
  local root = vim.fn.getcwd()
  ui.notify_info("Sonar: running sonar-scanner...")
  M.scan_cli(root, function(result, err)
    if not result then
      ui.notify_err("sonar-scanner: " .. (err or "failed"))
      return
    end
    M.render_cli_report(root, result)
    ui.notify_info(
      result.code == 0 and "sonar-scanner finished"
        or ("sonar-scanner exited " .. result.code .. " -- see report split")
    )
  end)
end, { desc = "Sonar: run sonar-scanner (SonarQube connected mode)" })

return M
