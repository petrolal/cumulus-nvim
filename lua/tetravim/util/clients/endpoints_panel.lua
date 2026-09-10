-- TetraVim Endpoints panel  (tetravim.util.clients.endpoints_panel)
--
-- NB: the module is `endpoints_panel`, not `endpoints` -- `tetravim.util.endpoints`
-- is a purged legacy name that must stay non-requireable (devops_validation_spec).
--
-- A docked, refreshable list of every HTTP endpoint in the project -- the
-- native answer to IDEA Ultimate's "Endpoints" tool window. Two data sources
-- are merged:
--
--   * Spring MVC / WebFlux mappings  -- tetravim.util.jvm.spring.find_endpoints
--     (the VMware Spring Boot LS `workspace/symbol` model when attached, the
--     ripgrep + Tree-sitter scan otherwise).
--   * JSON OpenAPI / Swagger specs   -- tetravim.util.clients.openapi.discover_specs +
--     list_endpoints.
--
-- Rows are grouped by controller class (Spring) or spec file basename
-- (OpenAPI). The panel itself is tetravim.util.panel; this module only builds
-- the row model and wires the three actions:
--
--   <CR>  jump to the declaring source line (controller method / spec path key)
--   r     refresh
--   g     drop a ".http" request for the row under the cursor into a split

local panel = require("tetravim.util.panel")
local split = require("tetravim.util.split")
local ui = require("tetravim.util.ui")

local M = {}

local NAME_HINT = "tetravim-endpoints"

--- Project root for the scan: the Maven/Gradle root if we can find one,
--- otherwise the cwd (OpenAPI specs alone still make a useful panel).
---@return string root
---@return table|nil detected  the tetravim.util.jvm.spring.detect_root result
local function resolve_root()
  local ok, spring = pcall(require, "tetravim.util.jvm.spring")
  if ok then
    local detected = spring.detect_root(vim.fn.getcwd())
    if detected and detected.root then
      return detected.root, detected
    end
  end
  return vim.fn.getcwd(), nil
end

--- Normalise a Spring endpoint (from tetravim.util.jvm.spring) into the shared row
--- item shape.
local function from_spring(e)
  local group = e.class_name
  if group == nil or group == "" then
    group = "(uncategorised)"
  end
  return {
    http_method = (e.http_method or "ANY"):upper(),
    path = e.path or "/",
    file = e.file,
    line = tonumber(e.line) or 0,
    label = e.handler_name ~= nil and e.handler_name ~= "" and e.handler_name or nil,
    group = group,
    source = "spring",
  }
end

--- Normalise an OpenAPI operation (from tetravim.util.clients.openapi.list_endpoints)
--- into the shared row item shape.
local function from_openapi(e, spec_path)
  return {
    http_method = (e.http_method or "ANY"):upper(),
    path = e.path or "/",
    file = e.file or spec_path,
    line = tonumber(e.line) or 1,
    label = (e.operation_id ~= nil and e.operation_id ~= "" and e.operation_id)
      or (e.summary ~= nil and e.summary ~= "" and e.summary)
      or nil,
    group = "spec: " .. vim.fs.basename(spec_path),
    source = "openapi",
  }
end

--- Merge, de-duplicate and sort the raw item list.
--- De-dup key is METHOD + path + group so the same mapping surfaced by both the
--- LS and an OpenAPI spec still shows once per source view.
local function normalise(items)
  local seen = {}
  local out = {}
  for _, it in ipairs(items) do
    local key = it.group .. "\0" .. it.http_method .. "\0" .. it.path
    if not seen[key] then
      seen[key] = true
      out[#out + 1] = it
    end
  end
  table.sort(out, function(a, b)
    if a.group ~= b.group then
      return a.group < b.group
    end
    if a.path ~= b.path then
      return a.path < b.path
    end
    return a.http_method < b.http_method
  end)
  return out
end

--- Build the { text, item } row list (group headers interleaved) for panel.render.
local function build_rows(items)
  local rows = {}
  local current_group = nil
  for _, it in ipairs(items) do
    if it.group ~= current_group then
      current_group = it.group
      if #rows > 0 then
        rows[#rows + 1] = { text = "" }
      end
      rows[#rows + 1] = { text = "▸ " .. current_group }
    end
    local method = string.format("%-7s", it.http_method)
    local text = "    " .. method .. " " .. it.path
    if it.label then
      text = text .. "  · " .. it.label
    end
    rows[#rows + 1] = { text = text, item = it }
  end
  return rows
end

--- Jump from the panel to the declaring source line in the previous (editor)
--- window.
local function jump(item)
  if not item or not item.file or item.file == "" then
    ui.notify_warn("No source location for this row")
    return
  end
  if vim.fn.filereadable(item.file) ~= 1 then
    ui.notify_warn("File not found: " .. item.file)
    return
  end
  pcall(vim.cmd, "wincmd p")
  pcall(vim.cmd, "edit " .. vim.fn.fnameescape(item.file))
  local line = item.line and item.line > 0 and item.line or 1
  pcall(vim.api.nvim_win_set_cursor, 0, { line, 0 })
  vim.cmd("normal! zz")
end

--- `g` -- emit a one-request ".http" buffer for the row under the cursor.
local function to_http(item)
  if not item then
    return
  end
  local method = item.http_method
  if method == "ANY" then
    method = "GET"
  end
  local url_path = item.path:gsub("{([^}]+)}", ":%1")
  local lines = {
    "### " .. (item.label or (item.http_method .. " " .. item.path)),
    "@base = http://localhost:8080",
    "",
    method .. " {{base}}" .. url_path,
    "Accept: application/json",
    "",
  }
  split.open(table.concat(lines, "\n"), { filetype = "http", name_hint = "tetravim-http" })
end

--- Collect endpoints from both sources, then render.
--- Async: tetravim.util.jvm.spring.find_endpoints resolves on vim.schedule.
function M.open()
  local root, detected = resolve_root()

  local items = {}
  local spec_count = 0

  -- OpenAPI specs are synchronous -- gather them first so they show even if the
  -- Spring scan finds nothing / times out.
  local ok_oa, openapi = pcall(require, "tetravim.util.clients.openapi")
  if ok_oa then
    local specs = openapi.discover_specs(root) or {}
    spec_count = #specs
    for _, spec_path in ipairs(specs) do
      for _, e in ipairs(openapi.list_endpoints(spec_path) or {}) do
        items[#items + 1] = from_openapi(e, spec_path)
      end
    end
  end

  local function render(spring_count)
    local merged = normalise(items)
    local header = {
      "TetraVim Endpoints  ·  "
        .. #merged
        .. " endpoint(s)"
        .. (detected and ("  ·  " .. (detected.project_name or vim.fs.basename(root))) or ""),
      "root: " .. root,
      "spring: " .. spring_count .. "   openapi specs: " .. spec_count,
      "<CR> jump   r refresh   g → .http   q close",
      "",
    }
    if #merged == 0 then
      header[#header + 1] = "No endpoints found (no Spring mappings, no JSON OpenAPI spec)."
    end
    panel.render({
      name_hint = NAME_HINT,
      filetype = "tetravim-endpoints",
      header = header,
      rows = build_rows(merged),
      on_select = function(item)
        jump(item)
      end,
      refresh = function()
        M.open()
      end,
      keymaps = {
        g = function(item)
          to_http(item)
        end,
      },
    })
  end

  local ok_sp, spring = pcall(require, "tetravim.util.jvm.spring")
  if not ok_sp then
    render(0)
    return
  end

  spring.find_endpoints(root, function(list)
    local n = 0
    for _, e in ipairs(list or {}) do
      items[#items + 1] = from_spring(e)
      n = n + 1
    end
    render(n)
  end)
end

return M
