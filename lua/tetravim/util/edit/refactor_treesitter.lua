-- TetraVim Refactor: Tree-sitter/text-assisted Spring reference scan (SPEC-2.1)
--
-- JDTLS/Kotlin LS's textDocument/rename only ever touches locations the
-- language server can resolve via normal type/reference analysis. Spring's
-- reflection-based wiring -- XML `<bean class="...">` entries, and
-- @Component/@Service/@Repository/@Controller/@RestController stereotype
-- classes referenced by simple name from @Autowired fields -- lives outside
-- that analysis entirely (XML isn't Java/Kotlin at all; annotation-driven
-- injection is resolved by Spring at runtime, not the compiler/LSP). This
-- module scans the project tree for those locations so refactor.lua can
-- merge them into the same rename preview instead of silently missing them.
--
-- Design:
--   1. Fast, async candidate search via `rg`/`grep` (vim.system, never the
--      main loop) -- mirrors the vim.system + vim.schedule convention in
--      sync_runner.lua. This narrows a whole-project scan down to just the
--      handful of *lines* that mention the symbol at all (deduped per
--      (file, line) -- `rg` reports one hit per occurrence, so a line with
--      the symbol twice would otherwise produce two raw hits).
--   2. Cheap classification of each unique line against Lua patterns for
--      the three reference kinds this spec cares about (xml_bean,
--      stereotype, autowired). A classified line contributes ONE item per
--      whole-word occurrence of the symbol on that line (not just the
--      first) -- a bare textual hit that classifies as none of the three
--      is dropped entirely, never silently rewritten.
--   3. Where a Tree-sitter parser for the candidate's language is
--      available, it is used as a precision filter to discard matches that
--      Lua patterns can't see are inside a comment or string literal (Java/
--      Kotlin via a real grammar, parsed once per file and reused across
--      that file's hits; XML via a lightweight `<!-- -->` state scan, since
--      no XML grammar is guaranteed installed anywhere in this
--      distribution). Missing/broken parsers degrade to pattern-only
--      matching -- never fatal to the overall rename flow.
--   4. Package-scoping: candidates in a different Java/Kotlin package (or,
--      for XML, a different FQN package prefix on the bean `class`
--      attribute) than the symbol being renamed are dropped, so renaming
--      `com.a.FooService` never touches an unrelated `com.b.FooService`.
--      Only applied when both the renamed symbol's package and a given
--      candidate's package are determinable -- otherwise the guard is
--      skipped (undeterminable-but-unfiltered) or the candidate is skipped
--      outright (determinable-old, undeterminable-candidate: conservative).
--
-- Every entry point here is best-effort and non-fatal: a parse failure or
-- missing grammar/tool for one file must never abort the overall rename.

local M = {}

local ui = require("tetravim.util.ui")

M.STEREOTYPE_ANNOTATIONS = {
  "Component",
  "Service",
  "Repository",
  "Controller",
  "RestController",
}

local STEREOTYPE_SET = {}
for _, name in ipairs(M.STEREOTYPE_ANNOTATIONS) do
  STEREOTYPE_SET[name] = true
end

--- Find every whole-word occurrence of `symbol` on `line`.
---@param line string
---@param symbol string
---@return { col: integer, end_col: integer }[] 1-based, end exclusive
function M._find_all_occurrences(line, symbol)
  local occurrences = {}
  local pattern = "%f[%w_]" .. vim.pesc(symbol) .. "%f[^%w_]"
  local init = 1
  while true do
    local s, e = line:find(pattern, init)
    if not s then
      break
    end
    occurrences[#occurrences + 1] = { col = s, end_col = e + 1 }
    init = e + 1
  end
  return occurrences
end

--- Extract a leading `package foo.bar;` (Java) or `package foo.bar`
--- (Kotlin) declaration from a file's lines, if present near the top.
---@param lines string[]
---@return string|nil
function M.file_package(lines)
  for i = 1, #lines do
    local line = lines[i]
    if line then
      local pkg = line:match("^%s*package%s+([%w_.]+)%s*;?%s*$")
      if pkg then
        return pkg
      end
    end
  end
  return nil
end

--- Whether `lines` (a candidate file's own content) imports `symbol` from
--- `package` -- either the exact FQN (`import pkg.Symbol;` / Kotlin's
--- semicolon-less form) or a wildcard import of the package (`import
--- pkg.*;`). A same-package-only check misses the entire point of
--- @Autowired-by-simple-name: a DIFFERENT package's class routinely
--- @Autowired-injects a bean by simple name after importing it, and that
--- reference must still be included in the rename preview. Only used to
--- ADMIT a cross-package candidate that the same-package check would
--- otherwise reject -- it never excludes anything on its own.
---@param lines string[]
---@param package string
---@param symbol string
---@return boolean
function M.file_imports_symbol(lines, package, symbol)
  local exact_pattern = "^%s*import%s+" .. vim.pesc(package) .. "%." .. vim.pesc(symbol) .. "%s*;?%s*$"
  local wildcard_pattern = "^%s*import%s+" .. vim.pesc(package) .. "%.%*%s*;?%s*$"
  for i = 1, #lines do
    local line = lines[i]
    if line and (line:match(exact_pattern) or line:match(wildcard_pattern)) then
      return true
    end
  end
  return false
end

--- Classify a single XML line already known to contain `symbol` as a whole
--- word. Returns one entry per whole-word occurrence of `symbol` that
--- falls inside a `<bean ... class="...">` attribute's value, each tagged
--- with the FQN package prefix immediately preceding it when the attribute
--- value is fully-qualified (nil when it's a bare simple name).
---@param line string
---@param symbol string
---@return { col: integer, end_col: integer, package: string|nil }[]|nil
function M.classify_xml_line(line, symbol)
  if not line:find("<bean%f[%A]") then
    return nil
  end
  local attr_start = line:find("class%s*=%s*[\"']")
  if not attr_start then
    return nil
  end
  local quote_start = line:find("[\"']", attr_start)
  if not quote_start then
    return nil
  end
  local quote_char = line:sub(quote_start, quote_start)
  local quote_end = line:find(quote_char, quote_start + 1, true)
  if not quote_end then
    return nil
  end

  local occurrences = {}
  local pattern = "%f[%w]" .. vim.pesc(symbol) .. "%f[%W]"
  local init = quote_start + 1
  while init < quote_end do
    local s, e = line:find(pattern, init)
    if not s or s >= quote_end then
      break
    end

    local package = nil
    if s > 1 and line:sub(s - 1, s - 1) == "." then
      local prefix_start = s - 1
      while prefix_start > 1 and line:sub(prefix_start - 1, prefix_start - 1):match("[%w_.]") do
        prefix_start = prefix_start - 1
      end
      local prefix = line:sub(prefix_start, s - 2)
      if prefix ~= "" then
        package = prefix
      end
    end

    occurrences[#occurrences + 1] = { col = s, end_col = e + 1, package = package }
    init = e + 1
  end

  if #occurrences == 0 then
    return nil
  end
  return occurrences
end

--- Classify a Java/Kotlin candidate line (already known to contain `symbol`
--- as a whole word) using the line itself plus up to 2 preceding lines of
--- context (annotations sit directly above the declaration they modify).
--- Returns every whole-word occurrence of `symbol` on the line once the
--- line as a whole is classified -- e.g. `private FooService fooService =
--- FooService.createDefault();` under an `@Autowired` yields two items,
--- not just the first.
---@param lines string[] full file content, 1 line per array entry
---@param idx integer 1-based index of the matched line within `lines`
---@param symbol string
---@return "stereotype"|"autowired"|nil kind
---@return { col: integer, end_col: integer }[]|nil occurrences
function M.classify_jvm_line(lines, idx, symbol)
  local line = lines[idx]
  if not line then
    return nil
  end
  local occurrences = M._find_all_occurrences(line, symbol)
  if #occurrences == 0 then
    return nil
  end

  local context = {}
  for i = math.max(1, idx - 2), idx do
    context[#context + 1] = lines[i]
  end
  local context_text = table.concat(context, "\n")

  -- `@Autowired` field/property whose declared type is `symbol`, e.g.
  -- `private FooService fooService;` (Java) or `val fooService: FooService`
  -- (Kotlin) -- both put the symbol on the matched line itself, with
  -- `@Autowired` on the same or a preceding line.
  if context_text:find("@Autowired%f[%A]") then
    local is_type_position = line:find("%f[%w]" .. vim.pesc(symbol) .. "%f[%W]%s+%a[%w_]*%s*[;=,)]")
      or line:find(":%s*" .. vim.pesc(symbol) .. "%f[%W]")
    if is_type_position then
      return "autowired", occurrences
    end
  end

  -- Stereotype-annotated class declaration: `@Component`/`@Service`/etc.
  -- immediately above (or on the same line as, for single-line styles)
  -- `class Symbol`.
  local has_stereotype = false
  for name in pairs(STEREOTYPE_SET) do
    if context_text:find("@" .. name .. "%f[%A]") then
      has_stereotype = true
      break
    end
  end
  if has_stereotype and line:find("class%s+" .. vim.pesc(symbol) .. "%f[%W]") then
    return "stereotype", occurrences
  end

  return nil
end

--- Best-effort, comment-state-tracking check for whether (lnum, col) --
--- 1-based line, 1-based column -- falls inside an XML `<!-- ... -->`
--- comment. Walks from the start of the file tracking open/close state
--- since XML comments can span multiple lines; a plain text scan avoids
--- depending on an XML Tree-sitter grammar that isn't guaranteed to be
--- installed anywhere in this distribution.
---@param lines string[]
---@param lnum integer
---@param col integer
---@return boolean
function M.is_inside_xml_comment(lines, lnum, col)
  local in_comment = false
  for i = 1, lnum do
    local line = lines[i] or ""
    local search_from = 1
    local line_len = #line
    while search_from <= line_len + 1 do
      if in_comment then
        local close_s, close_e = line:find("%-%->", search_from)
        if not close_s then
          if i == lnum and col >= search_from then
            return true
          end
          break
        end
        if i == lnum and col >= search_from and col <= close_e then
          return true
        end
        in_comment = false
        search_from = close_e + 1
      else
        local open_s = line:find("<!%-%-", search_from)
        if not open_s then
          break
        end
        if i == lnum and col >= search_from and col < open_s then
          return false
        end
        in_comment = true
        search_from = open_s + 4
      end
    end
  end
  return false
end

--- Parse `content` as `lang` and return its root TSNode, or nil if no
--- parser is installed / parsing errors. Intended to be called ONCE per
--- file and the result reused across every occurrence in that file --
--- callers must not re-parse per hit.
---@param content string
---@param lang string
---@return TSNode|nil
function M._ts_root_for(content, lang)
  local ok, root = pcall(function()
    local parser = vim.treesitter.get_string_parser(content, lang)
    local trees = parser:parse()
    return trees[1]:root()
  end)
  if not ok then
    return nil
  end
  return root
end

--- Given an already-parsed root (or nil, meaning "no parser available"),
--- returns true only if (row, col) -- 0-based -- falls inside a comment or
--- string-literal node.
---@param root TSNode|nil
---@param row integer
---@param col integer
---@return boolean
function M._is_comment_or_string_node(root, row, col)
  if not root then
    return false
  end
  local ok, result = pcall(function()
    local node = root:named_descendant_for_range(row, col, row, col)
    while node do
      local ntype = node:type()
      if ntype:find("comment", 1, true) or ntype:find("string", 1, true) then
        return true
      end
      node = node:parent()
    end
    return false
  end)
  if not ok then
    return false
  end
  return result
end

--- Best-effort Tree-sitter precision filter: returns true only when a
--- parser is available AND it confirms `row` (0-based) falls inside a
--- comment or string-literal node -- i.e. this candidate should be
--- discarded even though the Lua-pattern pass matched it. Returns false
--- (never discard) whenever a parser isn't installed or parsing errors,
--- since pattern-matching already did the real classification work.
---
--- Convenience wrapper over `_ts_root_for` + `_is_comment_or_string_node`
--- for callers that only need a single (row, col) check; `scan_root_async`
--- itself calls those two directly so it can parse each file once and
--- reuse the root across every hit in that file.
---@param content string
---@param lang string
---@param row integer 0-based line
---@param col integer 0-based byte column
---@return boolean
function M.is_inside_comment_or_string(content, lang, row, col)
  return M._is_comment_or_string_node(M._ts_root_for(content, lang), row, col)
end

local LANG_BY_EXT = {
  java = "java",
  kt = "kotlin",
  kts = "kotlin",
}

-- Upper bound on the `rg`/`grep` candidate search. refactor.lua's
-- RENAME_TIMEOUT_MS only guards the textDocument/rename request; without
-- this a stuck scanner would hold the shared action_lock with no preview
-- and no feedback until Neovim restarts. A non-0/1 exit (which a timeout
-- kill produces) already routes to the grep fallback / warn_scan_unavailable.
local SCAN_TIMEOUT_MS = 15000

-- Stable vim.notify id so the "scanning..." toast collapses in place rather
-- than stacking, mirroring sync_runner.lua's heartbeat-notify convention.
local SCAN_NOTIFY_ID = "tetravim_refactor_spring_scan"

local SCAN_UNAVAILABLE_MSG =
  "Spring-reference scan unavailable (neither 'rg' nor 'grep' could be run) -- XML/@Autowired/stereotype coverage may be incomplete for this rename"

local function warn_scan_unavailable()
  ui.notify_warn(SCAN_UNAVAILABLE_MSG, "TetraVim Refactor")
end

--- Find candidate files under `root` that mention `symbol` as a whole word,
--- restricted to .java/.kt/.xml, via `rg` (preferred) or `grep` (fallback).
--- Fully async -- never blocks the editor. Calls `callback({ {file=, lnum=,
--- col=, end_col=}, ... })` (raw hits, not yet classified) via vim.schedule.
--- Calls `callback({})` if neither tool is available or the scan errors
--- (and, in that specific case, surfaces one `vim.notify` WARN so the user
--- knows Spring-reference coverage may be incomplete).
---@param root string
---@param symbol string
---@param callback fun(hits: table[])
function M.raw_hits_async(root, symbol, callback)
  local function finish(hits)
    vim.schedule(function()
      callback(hits)
    end)
  end

  local function parse_rg(output)
    local hits = {}
    for _, line in ipairs(vim.split(output, "\n", { trimempty = true })) do
      -- rg --vimgrep: file:lnum:col:text
      local file, lnum, col, text = line:match("^(.-):(%d+):(%d+):(.*)$")
      if file then
        local s, e = M._word_span(text, symbol, tonumber(col))
        if s then
          hits[#hits + 1] = { file = file, lnum = tonumber(lnum), col = s, end_col = e, line = text }
        end
      end
    end
    return hits
  end

  local function parse_grep(output)
    local hits = {}
    for _, line in ipairs(vim.split(output, "\n", { trimempty = true })) do
      local file, lnum, text = line:match("^(.-):(%d+):(.*)$")
      if file then
        local s, e = M._word_span(text, symbol, 1)
        if s then
          hits[#hits + 1] = { file = file, lnum = tonumber(lnum), col = s, end_col = e, line = text }
        end
      end
    end
    return hits
  end

  local rg_cmd = {
    "rg",
    "--vimgrep",
    "--fixed-strings",
    "--word-regexp",
    "--iglob",
    "*.java",
    "--iglob",
    "*.kt",
    "--iglob",
    "*.xml",
    symbol,
    root,
  }
  local rg_ok, rg_handle_or_err = pcall(vim.system, rg_cmd, { text = true, timeout = SCAN_TIMEOUT_MS }, function(result)
    if result.code == 0 or result.code == 1 then
      -- exit 1 == "no matches", not an error -- still a valid empty scan.
      finish(parse_rg(result.stdout or ""))
      return
    end
    -- Non-zero/non-1 exit (e.g. rg present but errored on this root):
    -- fall back to grep rather than silently dropping Spring coverage.
    M._grep_fallback(root, symbol, parse_grep, finish)
  end)
  if not rg_ok then
    M._grep_fallback(root, symbol, parse_grep, finish)
    return
  end
  if not rg_handle_or_err then
    M._grep_fallback(root, symbol, parse_grep, finish)
  end
end

function M._grep_fallback(root, symbol, parse_grep, finish)
  -- May be entered either from a safe (main-loop) context or from inside
  -- rg's own fast-context exit callback -- vim.schedule wrapping the spawn
  -- itself keeps every path safe rather than assuming vim.system() is
  -- callable from a fast callback.
  vim.schedule(function()
    local grep_cmd = {
      "grep",
      "-rn",
      "-F",
      "-w",
      "--include=*.[jJ][aA][vV][aA]",
      "--include=*.[kK][tT]",
      "--include=*.[xX][mM][lL]",
      -- Unlike rg (which honors .gitignore by default), grep has no
      -- built-in exclusions -- keep it out of the usual non-source dirs.
      "--exclude-dir=.git",
      "--exclude-dir=target",
      "--exclude-dir=build",
      "--exclude-dir=node_modules",
      "--exclude-dir=.gradle",
      "--exclude-dir=out",
      "--",
      symbol,
      root,
    }
    local ok, handle_or_err = pcall(vim.system, grep_cmd, { text = true, timeout = SCAN_TIMEOUT_MS }, function(result)
      if result.code == 0 or result.code == 1 then
        finish(parse_grep(result.stdout or ""))
      else
        warn_scan_unavailable()
        finish({})
      end
    end)
    if not ok or not handle_or_err then
      warn_scan_unavailable()
      finish({})
    end
  end)
end

--- Locate the whole-word span of `symbol` in `text`, preferring the
--- occurrence at/after `hint_col` (1-based) when the tool already reported
--- a column, falling back to the first whole-word occurrence otherwise.
---@return integer|nil col
---@return integer|nil end_col
function M._word_span(text, symbol, hint_col)
  local pattern = "%f[%w]" .. vim.pesc(symbol) .. "%f[%W]"
  local init = hint_col or 1
  local s, e = text:find(pattern, math.max(1, init - 1))
  if not s then
    s, e = text:find(pattern, 1)
  end
  if not s then
    return nil
  end
  return s, e + 1
end

--- Scan `root` for Spring references to `symbol` (a simple class name),
--- classify each candidate, and hand the classified list to `callback`.
--- Fully async (delegates to raw_hits_async); never blocks the editor.
---
--- When `old_package` is given (the renamed symbol's own declared
--- package), any Java/Kotlin candidate file whose own `package` differs
--- (or is undeterminable) is skipped entirely, and any XML `<bean
--- class="...">` occurrence whose FQN package prefix differs (or is
--- undeterminable, e.g. a bare simple-name class attribute) is skipped --
--- this is what keeps renaming `com.a.FooService` from touching an
--- unrelated `com.b.FooService`. Pass nil to skip this guard entirely
--- (e.g. when the renamed symbol's own package couldn't be determined).
---@param root string
---@param symbol string
---@param old_package string|nil
---@param callback fun(items: table[]) -- { file, lnum, col, end_col, kind, text }
function M.scan_root_async(root, symbol, old_package, callback)
  M.raw_hits_async(root, symbol, function(hits)
    -- Dedupe to one hit per (file, line): rg reports one match per
    -- *occurrence*, so a line with the symbol twice produces two raw hits
    -- here. Classifying per-hit using only the first occurrence's column
    -- (an earlier version of this code did exactly that) corrupts the
    -- buffer when a line has the symbol more than once, since every raw
    -- hit for that line would classify to the SAME span. Classify once per
    -- unique line instead and let classify_* enumerate every occurrence.
    local by_file = {}
    local unique_files = {}
    for _, hit in ipairs(hits) do
      if not by_file[hit.file] then
        by_file[hit.file] = {}
        unique_files[#unique_files + 1] = hit.file
      end
      by_file[hit.file][hit.lnum] = by_file[hit.file][hit.lnum] or hit
    end

    local items = {}
    local failed_files = {}

    -- Heartbeat toast for a scan large enough to be perceptible: the
    -- per-chunk readfile + Tree-sitter parse is synchronous work between
    -- vim.schedule ticks, so on a big monorepo this can take a beat.
    -- Collapses in place via SCAN_NOTIFY_ID (sync_runner.lua's convention).
    local HEARTBEAT_THRESHOLD = 40
    local show_heartbeat = #unique_files >= HEARTBEAT_THRESHOLD
    if show_heartbeat then
      ui.notify_info(
        string.format("Scanning %d file(s) for Spring references to '%s'...", #unique_files, symbol),
        "TetraVim Refactor",
        { id = SCAN_NOTIFY_ID }
      )
    end

    local file_idx = 1
    local function process_chunk()
      local chunk_end = math.min(file_idx + 10, #unique_files)
      for i = file_idx, chunk_end do
        local file = unique_files[i]
        local lnum_hits = by_file[file]
        local ext = (file:match("%.([%w]+)$") or ""):lower()
        local ok, lines = pcall(vim.fn.readfile, file)
        if not ok or not lines then
          failed_files[#failed_files + 1] = file
        elseif ext == "xml" then
          for lnum, hit in pairs(lnum_hits) do
            local line = lines[lnum] or hit.line
            local occurrences = line and M.classify_xml_line(line, symbol)
            if occurrences then
              for _, occ in ipairs(occurrences) do
                local package_ok = true
                if old_package then
                  package_ok = occ.package ~= nil and occ.package == old_package
                end
                if package_ok and not M.is_inside_xml_comment(lines, lnum, occ.col) then
                  items[#items + 1] = {
                    file = file,
                    lnum = lnum,
                    col = occ.col,
                    end_col = occ.end_col,
                    kind = "xml_bean",
                    text = line,
                  }
                end
              end
            end
          end
        elseif LANG_BY_EXT[ext] then
          local lang = LANG_BY_EXT[ext]
          local file_package = M.file_package(lines)
          local package_ok = true
          if old_package then
            -- Same-package files ALWAYS qualify; a different (or
            -- undeterminable) package still qualifies if the file explicitly
            -- imports the renamed symbol from old_package -- e.g. a
            -- different-package @Autowired consumer. Without this, renaming
            -- com.a.FooService would silently miss a com.b.Consumer that
            -- imports and @Autowired-injects it.
            package_ok = (file_package ~= nil and file_package == old_package)
              or M.file_imports_symbol(lines, old_package, symbol)
          end
          if package_ok then
            -- Parse this file's Tree-sitter tree ONCE and reuse the root
            -- across every hit/occurrence in it, rather than re-parsing the
            -- whole file per hit.
            local content = table.concat(lines, "\n")
            local ts_root = M._ts_root_for(content, lang)
            for lnum in pairs(lnum_hits) do
              local kind, occurrences = M.classify_jvm_line(lines, lnum, symbol)
              if kind and occurrences then
                for _, occ in ipairs(occurrences) do
                  local discard = M._is_comment_or_string_node(ts_root, lnum - 1, occ.col - 1)
                  if not discard then
                    items[#items + 1] = {
                      file = file,
                      lnum = lnum,
                      col = occ.col,
                      end_col = occ.end_col,
                      kind = kind,
                      text = lines[lnum],
                    }
                  end
                end
              end
            end
          end
        end
      end

      file_idx = chunk_end + 1
      if file_idx <= #unique_files then
        if show_heartbeat then
          ui.notify_info(
            string.format(
              "Scanning for Spring references to '%s'... (%d/%d files)",
              symbol,
              math.min(file_idx - 1, #unique_files),
              #unique_files
            ),
            "TetraVim Refactor",
            { id = SCAN_NOTIFY_ID }
          )
        end
        vim.schedule(process_chunk)
      else
        if show_heartbeat then
          ui.notify_info(
            string.format("Spring-reference scan complete (%d file(s), %d match(es))", #unique_files, #items),
            "TetraVim Refactor",
            { id = SCAN_NOTIFY_ID }
          )
        end
        if #failed_files > 0 then
          ui.notify_warn(
            "Spring-reference scan could not read "
              .. #failed_files
              .. " candidate file(s), coverage may be incomplete: "
              .. table.concat(failed_files, ", "),
            "TetraVim Refactor"
          )
        end
        callback(items)
      end
    end

    process_chunk()
  end)
end

return M
