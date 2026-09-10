-- TetraVim DAP Stacktrace Drill-Down (SPEC-010)
-- Resolves stacktrace symbols and jumps to source files in DAP REPL/console buffers

local M = {}

--- Extract stacktrace line at cursor position
---@return string|nil The stacktrace line or nil if not found
local function get_stacktrace_line_at_cursor()
  local line = vim.api.nvim_get_current_line()
  if not line or line == "" then
    return nil
  end

  -- Check if line contains stacktrace pattern (at ...)
  if line:match("at%s+") then
    return line
  end

  return nil
end

--- Resolve a JVM stacktrace frame to a concrete source file + line.
--- Handles the standard `pkg.Class.method(File.ext:NN)` shape emitted by the
--- JVM for Java, Kotlin and Scala. The fully-qualified class name gives the
--- expected package directory (`com/example`), which is used to pick the right
--- file when several modules ship a same-named source.
---@param frame string
---@param root string Project root to search under
---@return { file_path: string, line: integer }|nil
local function resolve_frame(frame, root)
  local qualified = frame:match("at%s+([%w%.$_]+)%s*%(")
  local file_name, line_no = frame:match("%(([%w%._$-]+):(%d+)%)")
  if not file_name or not line_no then
    return nil
  end
  line_no = tonumber(line_no)

  -- Derive the package path from the qualified name (drop the trailing
  -- Class.method segments; nested classes use `$`).
  local pkg_path
  if qualified then
    local pkg = qualified:gsub("%$.*$", ""):gsub("%.[^.]+%.[^.]+$", "")
    if pkg ~= qualified and pkg ~= "" then
      pkg_path = pkg:gsub("%.", "/")
    end
  end

  local matches = vim.fs.find(file_name, { type = "file", limit = math.huge, path = root })
  if #matches == 0 then
    return nil
  end
  if pkg_path then
    for _, m in ipairs(matches) do
      if m:find(pkg_path .. "/" .. file_name, 1, true) then
        return { file_path = m, line = line_no }
      end
    end
  end
  return { file_path = matches[1], line = line_no }
end

--- Drill down at current cursor position
function M.drill_down_at_line()
  local line = get_stacktrace_line_at_cursor()
  if not line then
    vim.notify("No stacktrace found at cursor", vim.log.levels.WARN)
    return
  end

  local cwd = vim.fn.getcwd()
  local symbol = resolve_frame(line, cwd)

  if not symbol then
    -- No `(File.ext:NN)` in the frame -- fall back to an LSP workspace-symbol
    -- lookup on the method name so bare frames still navigate somewhere useful.
    local method = line:match("at%s+[%w%.$_]+%.([%w_$]+)%s*%(")
    if method and #vim.lsp.get_clients({ bufnr = 0 }) > 0 then
      vim.lsp.buf.workspace_symbol(method)
      return
    end
    vim.notify("Unable to resolve stacktrace symbol", vim.log.levels.WARN)
    return
  end

  vim.cmd("edit " .. vim.fn.fnameescape(symbol.file_path))
  vim.api.nvim_win_set_cursor(0, { symbol.line, 0 })
  vim.cmd("normal! zz") -- Center view on cursor
end

return M
