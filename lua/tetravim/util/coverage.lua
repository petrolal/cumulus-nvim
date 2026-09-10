-- TetraVim Code Coverage Module (SPEC-1.3: Visual Test Runner & Coverage)
--
-- Native Lua JaCoCo XML coverage parser and buffer overlay manager.
-- Highlights covered, uncovered, and partially covered lines using signs
-- and end-of-line virtual text, without external binary dependencies.
--
-- Overlay application is chunked across the event loop (one buffer per
-- scheduled tick) so loading a large report never blocks the UI. Callers
-- that need to observe the applied state synchronously (tests, scripts)
-- can wait on `M.is_loading`.

local M = {}

local coverage_ns = vim.api.nvim_create_namespace("tetravim_coverage")
local SIGN_GROUP = "tetravim_coverage_signs"

M.last_coverage = nil
M.last_report_path = nil
M.is_visible = false
M.is_loading = false

-- Buffers whose overlay is already applied for the current report; reset
-- whenever coverage is (re)loaded or cleared so BufWinEnter re-applies once.
local applied_bufs = {}

-- Bumped on every apply_to_all_buffers() run and on clear(). The chunked
-- schedule_apply() walk captures the value current when it started and bails
-- as soon as it no longer matches, so a second load()/toggle() (or a clear)
-- landing mid-walk cleanly supersedes the in-flight chain instead of leaving
-- two overlapping chains racing to flip M.is_loading.
local apply_generation = 0

local function ensure_signs_defined()
  local hl_ok = vim.fn.hlexists("DiagnosticSignOk") == 1 and "DiagnosticSignOk" or "DiffAdd"
  local hl_err = vim.fn.hlexists("DiagnosticSignError") == 1 and "DiagnosticSignError" or "DiffDelete"
  local hl_warn = vim.fn.hlexists("DiagnosticSignWarn") == 1 and "DiagnosticSignWarn" or "DiffChange"

  vim.fn.sign_define("TetraVimCoverageCovered", { text = "▎", texthl = hl_ok })
  vim.fn.sign_define("TetraVimCoverageUncovered", { text = "▎", texthl = hl_err })
  vim.fn.sign_define("TetraVimCoveragePartial", { text = "▎", texthl = hl_warn })
end

local function vt_hl(preferred, fallback)
  return vim.fn.hlexists(preferred) == 1 and preferred or fallback
end

--- Discover standard JaCoCo XML report paths in workspace
---@param start_dir? string
---@return string|nil
function M.find_report_file(start_dir)
  start_dir = start_dir or vim.fn.getcwd()
  local candidates = {
    start_dir .. "/target/site/jacoco/jacoco.xml",
    start_dir .. "/build/reports/jacoco/test/jacocoTestReport.xml",
    start_dir .. "/target/site/jacoco-aggregate/jacoco.xml",
    start_dir .. "/build/reports/jacoco/test/jacoco.xml",
  }

  for _, path in ipairs(candidates) do
    if vim.fn.filereadable(path) == 1 then
      return path
    end
  end

  -- Bounded multi-module fallback: only look a fixed number of directory
  -- levels deep at the conventional report locations. This intentionally
  -- avoids the old "**/jacoco*.xml" recursive walk, which could traverse
  -- an entire (potentially huge) source tree on every invocation.
  local nested = {
    "/*/target/site/jacoco/jacoco.xml",
    "/*/build/reports/jacoco/test/jacocoTestReport.xml",
    "/*/*/target/site/jacoco/jacoco.xml",
    "/*/*/build/reports/jacoco/test/jacocoTestReport.xml",
  }
  for _, suffix in ipairs(nested) do
    for _, path in ipairs(vim.fn.glob(start_dir .. suffix, false, true)) do
      if vim.fn.filereadable(path) == 1 then
        return path
      end
    end
  end

  return nil
end

--- Parse JaCoCo XML string content into structured coverage data
---@param content string
---@param report_path? string
---@return table|nil result, string|nil error
function M.parse_xml(content, report_path)
  if not content or content:match("^%s*$") then
    return nil, "Empty JaCoCo XML file"
  end

  if not content:match("<report") and not content:match("<package") then
    return nil, "Invalid JaCoCo XML report: missing <report> root element"
  end

  local summary = {
    lines_total = 0,
    lines_covered = 0,
    lines_missed = 0,
    lines_partial = 0,
    coverage_pct = 0,
  }
  local files = {}
  local entries = {}

  local current_pkg = ""
  local current_file_rec = nil

  local function flush_current_file()
    if current_file_rec then
      files[current_file_rec.file] = current_file_rec
      table.insert(entries, current_file_rec)
      current_file_rec = nil
    end
  end

  for tag_name, attrs in content:gmatch("<(/?[%w_:-]+)(%s*[^>]*)>") do
    if tag_name == "package" then
      flush_current_file()
      local name = attrs:match('name="([^"]*)"') or ""
      current_pkg = name:gsub("%.", "/")
    elseif tag_name == "/package" then
      flush_current_file()
      current_pkg = ""
    elseif tag_name == "sourcefile" then
      flush_current_file()
      local sf_name = attrs:match('name="([^"]*)"') or ""
      local file_rel = (current_pkg ~= "" and (current_pkg .. "/") or "") .. sf_name
      current_file_rec = {
        package = current_pkg,
        sourcefile = sf_name,
        file = file_rel,
        lines = {},
        covered_lines = {},
        missed_lines = {},
        partial_lines = {},
        lines_total = 0,
        lines_covered = 0,
        lines_missed = 0,
        lines_partial = 0,
      }
    elseif tag_name == "/sourcefile" then
      flush_current_file()
    elseif tag_name == "line" and current_file_rec then
      local nr_str = attrs:match('nr="(%d+)"')
      if nr_str then
        local nr = tonumber(nr_str)
        local ci = tonumber(attrs:match('ci="(%d+)"')) or 0
        local mi = tonumber(attrs:match('mi="(%d+)"')) or 0
        local cb = tonumber(attrs:match('cb="(%d+)"')) or 0
        local mb = tonumber(attrs:match('mb="(%d+)"')) or 0

        -- Lines whose instruction and branch counters are all zero carry
        -- no coverage information (blank lines, comments, braces). JaCoCo
        -- does not count them, and neither do we -- including them here
        -- would misreport them as uncovered and skew the totals.
        local has_signal = ci > 0 or mi > 0 or cb > 0 or mb > 0
        if has_signal then
          local missed = mi > 0 or mb > 0
          local hit = ci > 0 or cb > 0

          local status
          if missed and hit then
            status = "partial"
            table.insert(current_file_rec.partial_lines, nr)
            current_file_rec.lines_partial = current_file_rec.lines_partial + 1
            summary.lines_partial = summary.lines_partial + 1
          elseif missed then
            status = "uncovered"
            table.insert(current_file_rec.missed_lines, nr)
            current_file_rec.lines_missed = current_file_rec.lines_missed + 1
            summary.lines_missed = summary.lines_missed + 1
          else
            -- hit only: fully covered instructions and/or branches with
            -- nothing missed -- this also covers the branch-only case
            -- (cb > 0, mb == 0, ci == 0, mi == 0).
            status = "covered"
            table.insert(current_file_rec.covered_lines, nr)
            current_file_rec.lines_covered = current_file_rec.lines_covered + 1
            summary.lines_covered = summary.lines_covered + 1
          end

          current_file_rec.lines[nr] = status
          current_file_rec.lines_total = current_file_rec.lines_total + 1
          summary.lines_total = summary.lines_total + 1
        end
      end
    end
  end

  flush_current_file()

  if summary.lines_total > 0 then
    summary.coverage_pct = math.floor((summary.lines_covered / summary.lines_total) * 10000 + 0.5) / 100
  else
    summary.coverage_pct = 0
  end

  -- A structurally valid report that yields no coverable lines almost
  -- always means the wrong file was picked or the report is stale/empty.
  -- Surface it instead of silently "loading" a blank overlay. Only warn
  -- when parsing a real file (report_path set), never for unit-test
  -- strings passed straight to parse_xml.
  if report_path and summary.lines_total == 0 then
    vim.schedule(function()
      vim.notify(
        "JaCoCo report parsed but contains no coverable lines: " .. report_path,
        vim.log.levels.WARN,
        { title = "TetraVim Coverage" }
      )
    end)
  end

  return {
    report_path = report_path,
    summary = summary,
    files = files,
    entries = entries,
  }
end

--- Parse JaCoCo XML report from file path
---@param file_path string
---@return table|nil result, string|nil error
function M.parse(file_path)
  if not file_path or file_path == "" or vim.fn.filereadable(file_path) == 0 then
    return nil, "Coverage file not found: " .. tostring(file_path)
  end

  local ok, lines = pcall(vim.fn.readfile, file_path)
  if not ok or not lines then
    return nil, "Failed to read coverage file: " .. tostring(file_path)
  end

  local content = table.concat(lines, "\n")
  return M.parse_xml(content, file_path)
end

--- Find coverage entry matching the given buffer
---@param bufnr number
---@return table|nil
local function find_file_rec_for_buf(bufnr)
  if not M.last_coverage or not M.last_coverage.files then
    return nil
  end

  local buf_name = vim.api.nvim_buf_get_name(bufnr):gsub("\\", "/")
  if buf_name == "" then
    return nil
  end

  -- Match only on the package-qualified path (e.g. "com/example/Foo.java").
  -- A bare-basename match ("Foo.java") is ambiguous: many projects have
  -- several source files with the same name in different packages, and it
  -- would overlay the wrong buffer's coverage.
  for file_rel, rec in pairs(M.last_coverage.files) do
    if buf_name == file_rel or vim.endswith(buf_name, "/" .. file_rel) then
      return rec
    end
  end

  return nil
end

--- Apply coverage signs and virtual-text overlay to a specific buffer
---@param bufnr number
function M.apply_to_buffer(bufnr)
  if not M.is_visible or not M.last_coverage then
    return
  end
  if not vim.api.nvim_buf_is_valid(bufnr) then
    return
  end

  local rec = find_file_rec_for_buf(bufnr)
  if not rec then
    return
  end

  ensure_signs_defined()

  -- Clear previous coverage signs and virtual text for this buffer
  vim.fn.sign_unplace(SIGN_GROUP, { buffer = bufnr })
  vim.api.nvim_buf_clear_namespace(bufnr, coverage_ns, 0, -1)

  local line_count = vim.api.nvim_buf_line_count(bufnr)

  local sign_map = {
    covered = "TetraVimCoverageCovered",
    uncovered = "TetraVimCoverageUncovered",
    partial = "TetraVimCoveragePartial",
  }

  -- Batch-place all signs in a single call. Clamp to the buffer's real
  -- line count: a JaCoCo report can reference lines past the end of a
  -- buffer that has since been edited, and an out-of-range lnum would
  -- otherwise abort the whole placement.
  local placements = {}
  for nr, status in pairs(rec.lines) do
    local sign = sign_map[status]
    if sign and nr >= 1 and nr <= line_count then
      table.insert(placements, {
        buffer = bufnr,
        group = SIGN_GROUP,
        lnum = nr,
        name = sign,
        priority = 10,
      })
    end
  end
  if #placements > 0 then
    pcall(vim.fn.sign_placelist, placements)
  end

  -- End-of-line virtual text for missed and partially covered lines
  -- (replaces the previous vim.diagnostic layer, which polluted the
  -- diagnostics list and the quickfix/loclist with non-error noise).
  local hl_missed = vt_hl("DiagnosticVirtualTextError", "Comment")
  local hl_partial = vt_hl("DiagnosticVirtualTextWarn", "Comment")

  local function set_vt(nr, text, hl)
    if nr >= 1 and nr <= line_count then
      pcall(vim.api.nvim_buf_set_extmark, bufnr, coverage_ns, nr - 1, 0, {
        virt_text = { { text, hl } },
        virt_text_pos = "eol",
        hl_mode = "combine",
      })
    end
  end

  for _, nr in ipairs(rec.missed_lines) do
    set_vt(nr, "  ▸ uncovered", hl_missed)
  end
  for _, nr in ipairs(rec.partial_lines) do
    set_vt(nr, "  ▸ partial", hl_partial)
  end

  applied_bufs[bufnr] = true
end

-- Recursively apply the overlay to a list of buffers, yielding to the
-- event loop between each one so the UI stays responsive on large reports.
local function schedule_apply(bufs, idx, on_done, generation)
  -- A newer apply_to_all_buffers() run (or a clear()) superseded this walk;
  -- stop without touching M.is_loading -- the current generation owns it.
  if generation ~= apply_generation then
    return
  end

  if idx > #bufs then
    M.is_loading = false
    if on_done then
      on_done()
    end
    return
  end

  local bufnr = bufs[idx]
  if vim.api.nvim_buf_is_loaded(bufnr) and vim.api.nvim_buf_is_valid(bufnr) then
    M.apply_to_buffer(bufnr)
  end

  vim.schedule(function()
    schedule_apply(bufs, idx + 1, on_done, generation)
  end)
end

--- Apply coverage overlays across all currently loaded valid buffers
---@param on_done? fun() called once every buffer has been processed
function M.apply_to_all_buffers(on_done)
  if not M.is_visible or not M.last_coverage then
    M.is_loading = false
    if on_done then
      on_done()
    end
    return
  end

  ensure_signs_defined()
  applied_bufs = {}
  apply_generation = apply_generation + 1
  M.is_loading = true
  schedule_apply(vim.api.nvim_list_bufs(), 1, on_done, apply_generation)
end

--- Load JaCoCo coverage report from file path (or auto-discover)
---@param xml_path? string
---@param opts? { on_done?: fun() }
---@return boolean success, table|string result_or_err
function M.load(xml_path, opts)
  opts = opts or {}

  if not xml_path or xml_path == "" then
    xml_path = M.find_report_file()
  end

  if not xml_path or vim.fn.filereadable(xml_path) == 0 then
    local msg = "No JaCoCo coverage report found in standard target/build dirs"
    vim.notify(msg, vim.log.levels.WARN, { title = "TetraVim Coverage" })
    return false, msg
  end

  local ok, res, err = pcall(M.parse, xml_path)
  if not ok or not res then
    local err_msg = tostring(res or err or "Parse failed")
    -- Drop any previously loaded report: keeping stale data around after a
    -- failed reload makes toggle/summary silently operate on the old file.
    M.last_coverage = nil
    M.last_report_path = nil
    M.is_visible = false
    M.is_loading = false
    applied_bufs = {}
    vim.notify("Failed to parse JaCoCo XML: " .. err_msg, vim.log.levels.ERROR, { title = "TetraVim Coverage" })
    return false, err_msg
  end

  -- Clear the previous report's overlays before applying the new one so a
  -- reload never leaves orphaned signs/virtual text from lines that are no
  -- longer in the report.
  M.clear(false)

  M.last_coverage = res
  M.last_report_path = xml_path
  M.is_visible = true

  M.apply_to_all_buffers(opts.on_done)

  local s = res.summary
  vim.notify(
    string.format(
      "JaCoCo coverage loaded: %.1f%% (%d covered, %d missed, %d partial)",
      s.coverage_pct,
      s.lines_covered,
      s.lines_missed,
      s.lines_partial
    ),
    vim.log.levels.INFO,
    { title = "TetraVim Coverage" }
  )

  return true, res
end

--- Clear coverage signs, virtual text, and overlays from all buffers
---@param reset_data? boolean If false, retains parsed data for toggle
function M.clear(reset_data)
  vim.fn.sign_unplace(SIGN_GROUP)

  for _, bufnr in ipairs(vim.api.nvim_list_bufs()) do
    if vim.api.nvim_buf_is_valid(bufnr) then
      vim.api.nvim_buf_clear_namespace(bufnr, coverage_ns, 0, -1)
    end
  end

  M.is_visible = false
  M.is_loading = false
  applied_bufs = {}
  -- Supersede any chunked apply walk still in flight so it stops on its next
  -- tick instead of re-placing signs we just unplaced.
  apply_generation = apply_generation + 1

  if reset_data ~= false then
    M.last_coverage = nil
    M.last_report_path = nil
  end
end

--- Toggle coverage overlays on/off
function M.toggle()
  if M.is_visible then
    M.clear(false)
    vim.notify("Coverage overlay hidden", vim.log.levels.INFO, { title = "TetraVim Coverage" })
  else
    if M.last_coverage then
      M.is_visible = true
      M.apply_to_all_buffers()
      vim.notify("Coverage overlay shown", vim.log.levels.INFO, { title = "TetraVim Coverage" })
    else
      M.load()
    end
  end
end

--- Display summary of loaded coverage report
---@return table|nil
function M.summary()
  if not M.last_coverage then
    vim.notify("No coverage report loaded. Use <leader>jcl to load JaCoCo coverage.", vim.log.levels.WARN, {
      title = "TetraVim Coverage",
    })
    return nil
  end

  local s = M.last_coverage.summary
  local msg = string.format(
    "Coverage Summary:\nReport: %s\nCoverage: %.1f%%\nTotal Lines: %d\nCovered: %d\nMissed: %d\nPartial: %d\nFiles: %d",
    M.last_report_path or "unknown",
    s.coverage_pct,
    s.lines_total,
    s.lines_covered,
    s.lines_missed,
    s.lines_partial,
    #M.last_coverage.entries
  )
  vim.notify(msg, vim.log.levels.INFO, { title = "TetraVim Coverage" })
  return s
end

-- Setup buffer autocommands for automatic overlay when a file becomes
-- visible in a window. BufWinEnter (not BufEnter) so we only re-apply when
-- the buffer is actually displayed, and the applied_bufs guard keeps it to
-- one application per buffer per loaded report.
local group = vim.api.nvim_create_augroup("tetravim_coverage_auto", { clear = true })
vim.api.nvim_create_autocmd({ "BufReadPost", "BufWinEnter" }, {
  group = group,
  callback = function(args)
    if M.is_visible and M.last_coverage and not applied_bufs[args.buf] then
      M.apply_to_buffer(args.buf)
    end
  end,
})

-- Drop a buffer's "already applied" marker when it goes away. Without this
-- applied_bufs grows for the life of the session, and -- because Neovim
-- reuses buffer numbers -- a fresh buffer landing on a retired number would
-- be wrongly treated as already overlaid and skipped by the guard above.
vim.api.nvim_create_autocmd({ "BufDelete", "BufWipeout" }, {
  group = group,
  callback = function(args)
    applied_bufs[args.buf] = nil
  end,
})

-- Register user commands
vim.api.nvim_create_user_command("TetraVimCoverageLoad", function(opts)
  local path = opts.args ~= "" and opts.args or nil
  M.load(path)
end, { nargs = "?", complete = "file", desc = "Load JaCoCo code coverage report" })

vim.api.nvim_create_user_command("TetraVimCoverageClear", function()
  M.clear(true)
  vim.notify("JaCoCo coverage cleared", vim.log.levels.INFO, { title = "TetraVim Coverage" })
end, { desc = "Clear JaCoCo code coverage" })

vim.api.nvim_create_user_command("TetraVimCoverageToggle", function()
  M.toggle()
end, { desc = "Toggle JaCoCo code coverage overlay" })

vim.api.nvim_create_user_command("TetraVimCoverageSummary", function()
  M.summary()
end, { desc = "Show JaCoCo code coverage summary" })

return M
