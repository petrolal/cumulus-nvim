-- TetraVim Spring Boot LS symbol bridge
--
-- The VMware Spring Boot Language Server (STS4, driven by `spring-boot.nvim` /
-- `vscode-spring-boot-tools`) publishes a live, compiler-accurate view of the
-- project's Spring model through `workspace/symbol`, using the same magic query
-- prefixes VS Code's "Go to Symbol in Workspace" uses:
--
--   * `@/`  -> request-mapping endpoints (`@GetMapping`, `@RequestMapping`, ...)
--   * `@+`  -> Spring beans (`@Component`, `@Bean`, auto-config, ...)
--
-- When that server is attached this is strictly better than the ripgrep +
-- Tree-sitter heuristics in `tetravim.util.spring` (it sees beans contributed by
-- meta-annotations, `@Import`, Java config and starter auto-config that never
-- carry a stereotype annotation in project source). `tetravim.util.spring`
-- calls in here first and falls back to its own scan when this returns nothing.
--
-- The string parsers are pure and unit-tested (`tests/spring_lsp_spec.lua`);
-- everything that touches a live client degrades to `cb(nil)`.

local M = {}

local CLIENT_NAME = "spring-boot"

--- The attached Spring Boot LS client, if any.
---@return vim.lsp.Client|nil
function M.client()
  local clients = vim.lsp.get_clients({ name = CLIENT_NAME })
  return clients and clients[1] or nil
end

--- Is the Spring Boot LS attached and ready to answer symbol queries?
---@return boolean
function M.available()
  local c = M.client()
  if not c then
    return false
  end
  -- `initialized` is set once the server has replied to `initialize`.
  return c.initialized ~= false
end

--- Parse an STS4 request-mapping `workspace/symbol` name into endpoint fields.
--- Handles the formats STS4 has shipped across versions:
---   `@GetMapping("/greeting")`               (verb baked into the annotation)
---   `@RequestMapping("/api",produces="...")` (RequestMapping, no verb -> ANY)
---   `@/greeting -- GET`                       (older "path -- verbs" form)
---   `@/greeting`                              (path only)
---@param name string
---@return { http_method: string, path: string }|nil
function M.parse_endpoint_symbol(name)
  name = vim.trim(name or "")
  if name == "" then
    return nil
  end

  -- form 1: @<Verb>Mapping("<path>"...)
  local verb, path = name:match('^@(%a+)Mapping%("([^"]*)"')
  if verb then
    local http = verb:upper()
    if http == "REQUEST" then
      http = "ANY"
    end
    return { http_method = http, path = path ~= "" and path or "/" }
  end

  -- form 2: @<path> -- GET,POST
  local p2, verbs = name:match("^@(.-)%s+%-%-%s+(.+)$")
  if p2 then
    local first = verbs:match("(%u+)")
    return { http_method = first or "ANY", path = p2 ~= "" and p2 or "/" }
  end

  -- form 3: @<path>
  local p3 = name:match("^@(.+)$")
  if p3 then
    return { http_method = "ANY", path = vim.trim(p3) }
  end

  return nil
end

--- Parse an STS4 bean `workspace/symbol` name into bean fields.
--- Formats: `@+ 'greetingController' (com.example.GreetingController)`
---          `@+ 'greetingController' com.example.GreetingController`
---          `@+ 'dataSource'`
---@param name string
---@return { bean_name: string, class_name: string }|nil
function M.parse_bean_symbol(name)
  name = vim.trim(name or "")
  local id, rest = name:match("^@%+?%s*'([^']*)'%s*(.*)$")
  if not id or id == "" then
    return nil
  end
  local cls = rest:match("[%w%.%$_]+") or ""
  return { bean_name = id, class_name = cls }
end

local function uri_to_path(uri)
  if not uri or uri == "" then
    return ""
  end
  local ok, p = pcall(vim.uri_to_fname, uri)
  return ok and p or ""
end

local function class_from_path(path)
  return (path:match("([%w_]+)%.%w+$")) or ""
end

--- Run a `workspace/symbol` query against the Spring Boot LS and map the results
--- through `mapper`. Calls `cb(list)` on success, `cb(nil)` when the server is
--- absent or errors. Always resolves on `vim.schedule`.
---@param query string
---@param mapper fun(sym: table): table|nil
---@param cb fun(list: table[]|nil)
local function symbol_query(query, mapper, cb)
  local c = M.client()
  if not c then
    vim.schedule(function()
      cb(nil)
    end)
    return
  end

  local function handle(err, result)
    if err or type(result) ~= "table" then
      vim.schedule(function()
        cb(nil)
      end)
      return
    end
    local out = {}
    for _, sym in ipairs(result) do
      local entry = mapper(sym)
      if entry then
        out[#out + 1] = entry
      end
    end
    vim.schedule(function()
      cb(out)
    end)
  end

  -- `client:request` is the 0.11 form; fall back to the older free function.
  if type(c.request) == "function" then
    c:request("workspace/symbol", { query = query }, handle)
  else
    vim.lsp.buf_request(0, "workspace/symbol", { query = query }, handle)
  end
end

--- Endpoints from the Spring Boot LS, shaped like `spring._endpoints_in_content`.
---@param cb fun(list: table[]|nil)
function M.query_endpoints(cb)
  symbol_query("@/", function(sym)
    local loc = sym.location or {}
    local parsed = M.parse_endpoint_symbol(sym.name)
    if not parsed then
      return nil
    end
    local path = uri_to_path(loc.uri)
    local line = loc.range and loc.range.start and (loc.range.start.line + 1) or 1
    return {
      http_method = parsed.http_method,
      path = parsed.path,
      class_name = sym.containerName and sym.containerName ~= "" and sym.containerName or class_from_path(path),
      handler_name = "",
      file = path,
      line = line,
      source = "lsp",
    }
  end, cb)
end

--- Beans from the Spring Boot LS, shaped like `spring._beans_in_content`.
---@param cb fun(list: table[]|nil)
function M.query_beans(cb)
  symbol_query("@+", function(sym)
    local loc = sym.location or {}
    local parsed = M.parse_bean_symbol(sym.name)
    if not parsed then
      return nil
    end
    local path = uri_to_path(loc.uri)
    local line = loc.range and loc.range.start and (loc.range.start.line + 1) or 1
    return {
      bean_name = parsed.bean_name,
      class_name = parsed.class_name ~= "" and parsed.class_name or class_from_path(path),
      injected_deps = {},
      file = path,
      line = line,
      source = "lsp",
    }
  end, cb)
end

return M
