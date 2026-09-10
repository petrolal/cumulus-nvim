-- lua/tetravim/util/jvm_test.lua
--
-- In-repo test runner for the JVM languages this distribution has no neotest
-- adapter for. neotest-java covers `.java`, neotest-scala covers `.scala`;
-- Kotlin and Groovy route here instead of pulling in a third-party Gradle
-- adapter.
--
-- Flow: locate the nearest test class / test function around the cursor (via
-- Tree-sitter, with a line-scan fallback when the parser is missing), turn it
-- into a fully-qualified `--tests 'pkg.Class.method'` filter, run
-- `./gradlew test` (or `./mvnw test -Dtest=pkg.Class#method`) in the shared
-- TetraVim split, then best-effort parse the JUnit XML the build drops under
-- `build/test-results/` (Gradle) / `target/surefire-reports/` (Maven) into a
-- pass/fail summary and a quickfix list of the failures.
--
-- Every external touch-point degrades to a single notify per CLAUDE.md.

local build = require("tetravim.util.build")
local term = require("tetravim.util.term")
local notify = require("tetravim.util.notify")

local M = {}

local TITLE = "TetraVim Test"

-- --------------------------------------------------------------------------
-- Buffer inspection
-- --------------------------------------------------------------------------

--- Pull the `package` declaration out of a buffer's head.
---@param bufnr integer
---@return string|nil
local function read_package(bufnr)
  local lines = vim.api.nvim_buf_get_lines(bufnr, 0, 80, false)
  for _, line in ipairs(lines) do
    local pkg = line:match("^%s*package%s+([%w_.]+)")
    if pkg then
      return pkg
    end
  end
  return nil
end

local TS_LANG_BY_FT = {
  kotlin = "kotlin",
  java = "java",
  groovy = "groovy",
  scala = "scala",
}

local CLASS_NODES = {
  class_declaration = true,
  object_declaration = true, -- kotlin
  object_definition = true, -- scala
  class_definition = true, -- scala
}

local FUNC_NODES = {
  function_declaration = true, -- kotlin
  method_declaration = true, -- java
  function_definition = true, -- scala / groovy
}

local IDENT_NODES = {
  type_identifier = true,
  simple_identifier = true,
  identifier = true,
}

local function node_name(node, bufnr)
  local ok, field = pcall(function()
    return node:field("name")[1]
  end)
  if ok and field then
    return vim.treesitter.get_node_text(field, bufnr)
  end
  for child in node:iter_children() do
    if IDENT_NODES[child:type()] then
      return vim.treesitter.get_node_text(child, bufnr)
    end
  end
  return nil
end

--- Nearest enclosing class + function names via Tree-sitter.
---@return string|nil class_name, string|nil func_name
local function nearest_via_treesitter(bufnr, ft)
  local lang = TS_LANG_BY_FT[ft]
  if not lang then
    return nil, nil
  end
  local ok, parser = pcall(vim.treesitter.get_parser, bufnr, lang)
  if not ok or not parser then
    return nil, nil
  end
  local ok_tree, trees = pcall(function()
    return parser:parse()
  end)
  if not ok_tree or not trees or not trees[1] then
    return nil, nil
  end
  local cursor = vim.api.nvim_win_get_cursor(0)
  local row, col = cursor[1] - 1, cursor[2]
  local node = trees[1]:root():named_descendant_for_range(row, col, row, col)
  local class_name, func_name
  while node do
    local ntype = node:type()
    if not func_name and FUNC_NODES[ntype] then
      func_name = node_name(node, bufnr)
    elseif not class_name and CLASS_NODES[ntype] then
      class_name = node_name(node, bufnr)
    end
    node = node:parent()
  end
  return class_name, func_name
end

--- Nearest class + function names by scanning buffer lines upward from the
--- cursor. Deliberately loose -- it only has to feed a `--tests` filter.
---@param bufnr integer
---@return string|nil class_name, string|nil func_name
function M._nearest_via_linescan(bufnr)
  local cursor = vim.api.nvim_win_get_cursor(0)
  local lines = vim.api.nvim_buf_get_lines(bufnr, 0, cursor[1], false)
  local class_name, func_name
  for i = #lines, 1, -1 do
    local line = lines[i]
    if not func_name then
      func_name = line:match("%f[%w]fun%s+`([^`]+)`") -- kotlin backticked test name
        or line:match("%f[%w]fun%s+([%w_]+)%s*%(")
        or line:match("%f[%w]def%s+([%w_]+)") -- groovy / spock
        or line:match("%f[%w]void%s+([%w_]+)%s*%(") -- plain java-ish
    end
    if not class_name then
      class_name = line:match("%f[%w]class%s+([%w_]+)") or line:match("%f[%w]object%s+([%w_]+)")
      if class_name then
        break
      end
    end
  end
  return class_name, func_name
end

-- --------------------------------------------------------------------------
-- Target resolution
-- --------------------------------------------------------------------------

---@class TetravimTestTarget
---@field scope "method"|"class"
---@field package string|nil
---@field class string
---@field method string|nil
---@field filter string   -- fully-qualified gradle `--tests` selector

--- Work out what to run from a buffer + cursor position.
---@param bufnr? integer
---@param opts? { whole_file?: boolean }
---@return TetravimTestTarget|nil target, string|nil err
function M.derive_target(bufnr, opts)
  opts = opts or {}
  bufnr = bufnr or vim.api.nvim_get_current_buf()
  local name = vim.api.nvim_buf_get_name(bufnr)
  if name == "" or vim.bo[bufnr].buftype ~= "" then
    return nil, "current buffer is not a file"
  end
  local ft = vim.bo[bufnr].filetype
  local pkg = read_package(bufnr)

  local ts_class, ts_func = nearest_via_treesitter(bufnr, ft)
  local ls_class, ls_func
  if not ts_class or (not opts.whole_file and not ts_func) then
    ls_class, ls_func = M._nearest_via_linescan(bufnr)
  end

  local class_name = ts_class or ls_class or vim.fn.fnamemodify(name, ":t:r")
  local func_name
  if not opts.whole_file then
    func_name = ts_func or ls_func
    if func_name then
      func_name = func_name:gsub("^`(.*)`$", "%1")
    end
  end

  local fqcn = pkg and (pkg .. "." .. class_name) or class_name
  local target = { package = pkg, class = class_name }
  if func_name and func_name ~= "" then
    target.scope = "method"
    target.method = func_name
    target.filter = fqcn .. "." .. func_name
  else
    target.scope = "class"
    target.filter = fqcn
  end
  return target
end

-- --------------------------------------------------------------------------
-- Command construction
-- --------------------------------------------------------------------------

--- Build the shell command for a test run.
---@param tool "gradle"|"maven"
---@param base_cmd string   `./gradlew` | `gradle` | `./mvnw` | `mvn`
---@param target TetravimTestTarget|nil  nil = run the whole module
---@return string
function M.build_command(tool, base_cmd, target)
  if not target then
    return base_cmd .. " test"
  end
  if tool == "maven" then
    local sel = (target.package and (target.package .. ".") or "") .. target.class
    if target.scope == "method" then
      sel = sel .. "#" .. target.method
    end
    return base_cmd .. " test -Dtest='" .. sel .. "'"
  end
  return base_cmd .. " test --tests '" .. target.filter .. "'"
end

-- --------------------------------------------------------------------------
-- JUnit XML result parsing
-- --------------------------------------------------------------------------

local function xml_unescape(s)
  if not s then
    return s
  end
  return (s:gsub("&lt;", "<"):gsub("&gt;", ">"):gsub("&quot;", '"'):gsub("&apos;", "'"):gsub("&amp;", "&"))
end

--- Fold one JUnit `<testsuite>` XML document into `agg`.
---@param body string
---@param agg? table
---@return table agg  { total, failures, errors, skipped, cases = { {classname,name,status,message} } }
function M.parse_junit_string(body, agg)
  agg = agg or { total = 0, failures = 0, errors = 0, skipped = 0, cases = {} }
  body = body or ""

  local suite = body:match("<testsuite%s[^>]*>") or body:match("<testsuite%s[^>]*/>") or ""
  agg.total = agg.total + tonumber(suite:match('tests="(%d+)"') or 0)
  agg.failures = agg.failures + tonumber(suite:match('failures="(%d+)"') or 0)
  agg.errors = agg.errors + tonumber(suite:match('errors="(%d+)"') or 0)
  agg.skipped = agg.skipped + tonumber(suite:match('skipped="(%d+)"') or 0)

  -- Strip + record the self-closing (passed) testcases first so the paired
  -- pattern below cannot span across one of them.
  body = body:gsub("<testcase[^>]-/>", function(tc)
    agg.cases[#agg.cases + 1] = {
      classname = tc:match('classname="([^"]*)"'),
      name = tc:match('name="([^"]*)"'),
      status = "passed",
    }
    return ""
  end)

  for tc in body:gmatch("<testcase.-</testcase>") do
    local status = "passed"
    if tc:find("<failure", 1, true) then
      status = "failure"
    elseif tc:find("<error", 1, true) then
      status = "error"
    elseif tc:find("<skipped", 1, true) then
      status = "skipped"
    end
    agg.cases[#agg.cases + 1] = {
      classname = tc:match('classname="([^"]*)"'),
      name = tc:match('name="([^"]*)"'),
      status = status,
      message = xml_unescape(
        tc:match('<failure%s[^>]-message="([^"]*)"') or tc:match('<error%s[^>]-message="([^"]*)"')
      ),
    }
  end
  return agg
end

--- Parse every JUnit XML file in `files`.
---@param files string[]
---@return table agg
function M.parse_junit_files(files)
  local agg = { total = 0, failures = 0, errors = 0, skipped = 0, cases = {} }
  for _, path in ipairs(files or {}) do
    local fh = io.open(path, "r")
    if fh then
      local ok, body = pcall(function()
        return fh:read("*a")
      end)
      fh:close()
      if ok and body then
        M.parse_junit_string(body, agg)
      end
    end
  end
  return agg
end

--- Result XML files the last `test` run produced under `root`.
---@param tool "gradle"|"maven"
---@param root string
---@return string[]
function M.result_files(tool, root)
  if not root or root == "" then
    return {}
  end
  local direct, recursive
  if tool == "maven" then
    direct = "/target/surefire-reports/*.xml"
    recursive = "/**/target/surefire-reports/*.xml"
  else
    direct = "/build/test-results/test/*.xml"
    recursive = "/**/build/test-results/test/*.xml"
  end
  local files = vim.fn.glob(root .. direct, false, true)
  vim.list_extend(files, vim.fn.glob(root .. recursive, false, true))
  local seen, out = {}, {}
  for _, f in ipairs(files) do
    if not seen[f] then
      seen[f] = true
      out[#out + 1] = f
    end
  end
  return out
end

--- Best-effort locate the source file for a JUnit `classname`.
---@param root string
---@param classname string|nil
---@return string|nil
function M.guess_source(root, classname)
  if not root or not classname then
    return nil
  end
  local simple = classname:match("([^.]+)$") or classname
  simple = simple:match("^([^$]+)") or simple -- drop nested $Inner
  for _, ext in ipairs({ "kt", "java", "scala", "groovy" }) do
    local hits = vim.fn.glob(root .. "/**/" .. simple .. "." .. ext, false, true)
    if #hits > 0 then
      return hits[1]
    end
  end
  return nil
end

-- --------------------------------------------------------------------------
-- Run + report
-- --------------------------------------------------------------------------

--- Summarise a finished run: notify + populate quickfix on failure.
---@param tool "gradle"|"maven"
---@param root string
---@param code integer  process exit code
function M.report(tool, root, code)
  local files = M.result_files(tool, root)
  if #files == 0 then
    if code == 0 then
      notify.notify_info("Tests passed (no JUnit XML found to summarise)", TITLE)
    else
      notify.notify_warn("Test run exited " .. tostring(code) .. " (no JUnit XML found)", TITLE)
    end
    return
  end

  local agg = M.parse_junit_files(files)
  local failed = agg.failures + agg.errors
  local passed = math.max(agg.total - failed - agg.skipped, 0)
  local summary =
    string.format("%d run · %d passed · %d failed · %d skipped", agg.total, passed, failed, agg.skipped)

  if failed == 0 and code == 0 then
    notify.notify_info(summary, TITLE)
    return
  end

  local qf = {}
  for _, c in ipairs(agg.cases) do
    if c.status == "failure" or c.status == "error" then
      qf[#qf + 1] = {
        filename = M.guess_source(root, c.classname),
        lnum = 1,
        text = string.format("%s.%s  --  %s", c.classname or "?", c.name or "?", c.message or c.status),
      }
    end
  end
  if #qf > 0 then
    vim.fn.setqflist({}, "r", { title = "JVM test failures", items = qf })
    pcall(vim.cmd, "copen")
  end
  notify.notify_warn(summary, TITLE)
end

--- Detect the governing build tool for a buffer.
---@param bufnr integer
---@return "maven"|"gradle"|nil tool, string|nil root
local function jvm_root(bufnr)
  local name = vim.api.nvim_buf_get_name(bufnr)
  return build.detect(name ~= "" and name or nil)
end

---@param target TetravimTestTarget|nil
---@param opts? { bufnr?: integer }
local function run(target, opts)
  opts = opts or {}
  local bufnr = opts.bufnr or vim.api.nvim_get_current_buf()
  local tool, root = jvm_root(bufnr)
  if not tool then
    notify.notify_warn("No Maven/Gradle project found for this buffer", TITLE)
    return
  end
  local base_cmd = build.wrapper_cmd(tool, root)
  local cmd = M.build_command(tool, base_cmd, target)
  term.run_term(cmd, {
    title = TITLE .. " (" .. tool .. ")",
    cwd = root,
    on_exit = function(code)
      vim.schedule(function()
        M.report(tool, root, code)
      end)
    end,
  })
end

--- Run the test method/class under the cursor.
---@param bufnr? integer
function M.run_nearest(bufnr)
  bufnr = bufnr or vim.api.nvim_get_current_buf()
  local target, err = M.derive_target(bufnr)
  if not target then
    notify.notify_warn(err or "could not locate a test around the cursor", TITLE)
    return
  end
  run(target, { bufnr = bufnr })
end

--- Run every test in the current file's class.
---@param bufnr? integer
function M.run_file(bufnr)
  bufnr = bufnr or vim.api.nvim_get_current_buf()
  local target, err = M.derive_target(bufnr, { whole_file = true })
  if not target then
    notify.notify_warn(err or "current buffer is not a test file", TITLE)
    return
  end
  run(target, { bufnr = bufnr })
end

--- Run the whole module's `test` task.
---@param bufnr? integer
function M.run_all(bufnr)
  run(nil, { bufnr = bufnr or vim.api.nvim_get_current_buf() })
end

return M
