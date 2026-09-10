-- TetraVim OpenAPI-to-.http Template Generation (SPEC-3.2)
--
-- JSON OpenAPI specs only, parsed via vim.json.decode -- never a YAML
-- parser (out of v1 scope; see "Never" boundary in the spec). Pure
-- read-and-transform: no network calls, no writes to disk -- the caller
-- decides what to do with the returned .http text (e.g. drop it into a new
-- buffer).

local ui = require("tetravim.util.ui")

local M = {}

-- Keys of `paths.<path>` that represent HTTP operations, per the OpenAPI
-- spec (everything else -- "parameters", "$ref", "summary", etc. at the
-- path-item level -- is not an operation and must be skipped).
local HTTP_METHODS = {
  get = true,
  put = true,
  post = true,
  delete = true,
  options = true,
  head = true,
  patch = true,
  trace = true,
}

local BODY_METHODS = {
  post = true,
  put = true,
  patch = true,
}

--- Build one ".http" request block (name comment, request line, headers)
--- for a single OpenAPI operation.
---@param method string lowercase HTTP method (e.g. "get")
---@param path string OpenAPI path template (e.g. "/users/{id}")
---@param base_url string
---@param operation table|nil the operation object (may be nil/non-table for a malformed spec)
---@return string
local function build_request_block(method, path, base_url, operation)
  local method_upper = method:upper()
  local name = method_upper .. " " .. path
  if type(operation) == "table" then
    if type(operation.operationId) == "string" then
      name = operation.operationId
    elseif type(operation.summary) == "string" then
      name = operation.summary
    end
  end

  -- A CR/LF inside operationId/summary would break the single-line
  -- "### <name>" header and inject stray lines into the block -- collapse
  -- every run of newline characters to a single space so the header stays
  -- on one line (a bare "\r\n" must not leave two spaces behind).
  name = name:gsub("[\r\n]+", " ")

  local lines = { "### " .. name }

  -- An OpenAPI path template's `{param}` segments (e.g. "/users/{id}") are
  -- carried through literally into the request line -- flag each one with
  -- a TODO comment so the generated template doesn't silently send a
  -- literal "{id}" path segment without the reader noticing it needs a
  -- real value substituted in. Deduped -- a path re-using the same
  -- parameter name twice (e.g. "/a/{id}/b/{id}") must only get ONE TODO
  -- comment for it, not one per occurrence.
  local seen_params = {}
  for param in path:gmatch("{([^{}]+)}") do
    if not seen_params[param] then
      seen_params[param] = true
      table.insert(lines, "# TODO: replace {" .. param .. "} with a real value")
    end
  end

  -- Flag every required query/header parameter so the generated block does
  -- not silently omit an input the endpoint demands. Deduped on (in, name)
  -- so a spec repeating a parameter only produces one TODO line.
  if type(operation) == "table" and type(operation.parameters) == "table" then
    local seen_required = {}
    for _, param in ipairs(operation.parameters) do
      if
        type(param) == "table"
        and param.required == true
        and type(param.name) == "string"
        and (param["in"] == "query" or param["in"] == "header")
      then
        -- Collapse any CR/LF in the parameter name for the same reason as the
        -- operationId/summary header above -- a newline here would inject a
        -- stray line into the block.
        local pname = param.name:gsub("[\r\n]+", " ")
        local key = param["in"] .. "\0" .. pname
        if not seen_required[key] then
          seen_required[key] = true
          table.insert(lines, "# TODO: set required " .. param["in"] .. " parameter '" .. pname .. "'")
        end
      end
    end
  end

  table.insert(lines, method_upper .. " " .. base_url .. path .. " HTTP/1.1")
  table.insert(lines, "Accept: application/json")
  if BODY_METHODS[method] then
    table.insert(lines, "Content-Type: application/json")
    -- kulala.nvim (like the .http format generally) expects a blank line
    -- separating headers from the body -- without a body placeholder here,
    -- a POST/PUT/PATCH block would have a Content-Type header promising a
    -- JSON body that never actually follows.
    table.insert(lines, "")
    table.insert(lines, "{}")
  end

  return table.concat(lines, "\n")
end

--- Read a JSON OpenAPI spec at `spec_path` and generate ".http"-formatted
--- text: one request block (method, url, headers) per operation found under
--- `paths`. Returns nil (after warning) for:
---   - a `.yaml`/`.yml` spec (JSON only, v1 scope)
---   - a missing/unreadable file
---   - a file that fails to parse as JSON
---   - a spec with no usable `paths`/operations
---@param spec_path string
---@return string|nil
function M.generate_http_from_spec(spec_path)
  if type(spec_path) ~= "string" or spec_path == "" then
    ui.notify_warn("OpenAPI spec path is required")
    return nil
  end

  -- Expand "~/openapi.json"-style paths the user is naturally inclined to
  -- type into the vim.ui.input prompt -- vim.fn.filereadable() below does
  -- NOT expand "~" itself, so an otherwise-valid path would fail unresolved.
  -- Use vim.fs.normalize rather than vim.fn.expand: expand() treats "%" and
  -- "#" as the current/alternate-file wildcards and mangles any spec path
  -- that legitimately contains those characters.
  spec_path = vim.fs.normalize(spec_path)

  if spec_path:lower():match("%.ya?ml$") then
    ui.notify_warn("OpenAPI spec is YAML (" .. spec_path .. "): JSON only is supported (v1 scope)")
    return nil
  end

  if vim.fn.filereadable(spec_path) ~= 1 then
    ui.notify_warn("OpenAPI spec not found or unreadable: " .. spec_path)
    return nil
  end

  local ok_read, lines_or_err = pcall(vim.fn.readfile, spec_path)
  if not ok_read then
    ui.notify_warn("Failed to read OpenAPI spec " .. spec_path .. ": " .. tostring(lines_or_err))
    return nil
  end

  -- Strip a leading UTF-8 BOM (\239\187\191) if present -- vim.json.decode
  -- treats it as an unexpected character and fails an otherwise-valid spec
  -- that was saved BOM-first by some Windows editors.
  local raw = table.concat(lines_or_err, "\n")
  raw = raw:gsub("^\239\187\191", "")

  local ok_decode, spec = pcall(vim.json.decode, raw)
  if not ok_decode or type(spec) ~= "table" then
    ui.notify_warn("Failed to parse OpenAPI spec as JSON: " .. spec_path)
    return nil
  end

  if type(spec.paths) ~= "table" then
    ui.notify_warn("OpenAPI spec has no `paths` object: " .. spec_path)
    return nil
  end

  local base_url = "{{baseUrl}}"
  if
    type(spec.servers) == "table"
    and type(spec.servers[1]) == "table"
    and type(spec.servers[1].url) == "string"
    and spec.servers[1].url ~= ""
  then
    -- Strip trailing slash(es) so joining with a leading-slash `path` below
    -- never produces a double slash (and an empty-string url already fell
    -- through to the "{{baseUrl}}" placeholder above instead of producing a
    -- hostless request line).
    base_url = spec.servers[1].url:gsub("/+$", "")

    if base_url == "" then
      -- A bare "/" (or "///") server URL strips to "" -- fall back to the
      -- placeholder rather than emitting a hostless "GET /users" request line.
      base_url = "{{baseUrl}}"
      ui.notify_warn(
        "OpenAPI server URL is '/' (no host); using the {{baseUrl}} placeholder -- generated requests need a host prefix"
      )
    elseif base_url ~= "{{baseUrl}}" and not base_url:match("^%a[%w+.-]*://") then
      ui.notify_warn("OpenAPI server URL is relative (" .. base_url .. "); generated requests need a host prefix")
    end

    -- OpenAPI permits multiple `servers` entries; only the first is used for
    -- generation -- name it so the reader knows which one was picked.
    if #spec.servers > 1 then
      ui.notify_info("OpenAPI spec lists " .. #spec.servers .. " servers; using the first: " .. base_url)
    end
  end

  -- OpenAPI server URLs may contain `{variable}` templates (per the
  -- `servers[].variables` object) -- substituting those is out of v1 scope,
  -- so warn rather than silently emitting request lines with a literal,
  -- unresolved "{...}" in the host/path, which would otherwise look like a
  -- generation bug rather than a known scope limit. The "{{baseUrl}}"
  -- placeholder is our own deliberate fallback (no/relative/bare-slash
  -- server URL), not an unresolved OpenAPI server variable -- exclude it.
  if base_url ~= "{{baseUrl}}" and base_url:match("{[^{}]+}") then
    ui.notify_warn(
      "OpenAPI server URL contains unresolved template variable(s) ("
        .. base_url
        .. ") -- generated request URLs will include the literal placeholder(s); server variable substitution is out of scope"
    )
  end

  -- Sort path keys (and, within each path, method keys) for deterministic,
  -- reviewable output rather than whatever order vim.json.decode's table
  -- happens to iterate in.
  local path_keys = {}
  local non_slash_path_keys = {}
  for path_key, path_item in pairs(spec.paths) do
    if type(path_item) == "table" then
      -- A valid OpenAPI path key is a template starting with "/". A key
      -- without a leading slash (e.g. "users") would generate a hostless,
      -- malformed request line -- skip it and warn, but let its siblings
      -- generate normally. `x-*` keys are spec-permitted extensions on the
      -- Paths Object, not malformed paths -- skip them silently.
      if type(path_key) == "string" and path_key:match("^/") then
        table.insert(path_keys, path_key)
      elseif not (type(path_key) == "string" and path_key:match("^x%-")) then
        table.insert(non_slash_path_keys, tostring(path_key))
      end
    end
  end
  table.sort(path_keys)

  if #non_slash_path_keys > 0 then
    table.sort(non_slash_path_keys)
    ui.notify_warn("Skipped OpenAPI path key(s) without a leading '/': " .. table.concat(non_slash_path_keys, ", "))
  end

  local blocks = {}
  local ref_skipped_paths = {}
  local ref_skipped_operations = {}
  for _, path_key in ipairs(path_keys) do
    local path_item = spec.paths[path_key]

    if type(path_item["$ref"]) == "string" then
      -- A `$ref`-only path item (external/internal path-item reference)
      -- carries no inline operations to walk -- that's out of scope for
      -- this story (see openapi.lua's module doc). Collect it instead of
      -- silently producing zero blocks for this path.
      table.insert(ref_skipped_paths, path_key)
    else
      -- Keep both the original-case key (to look the operation object up
      -- on path_item, which is case-sensitive) and its lowercased form (for
      -- the HTTP_METHODS membership check and build_request_block's method
      -- argument) -- a spec using non-lowercase method keys (nonstandard
      -- but not impossible) would otherwise silently look up a nil
      -- operation and lose its operationId/summary.
      local method_entries = {}
      for method_key in pairs(path_item) do
        if type(method_key) == "string" then
          local lower = method_key:lower()
          if HTTP_METHODS[lower] then
            local op_value = path_item[method_key]
            if type(op_value) == "table" and type(op_value["$ref"]) == "string" then
              -- An operation expressed as `{"$ref": ...}` carries no inline
              -- operation object (no operationId/summary/requestBody) to
              -- build a real block from -- rendering it anyway would
              -- produce a garbage block indistinguishable from a real one.
              -- Skip it and warn, same treatment as a whole-path-item $ref.
              table.insert(ref_skipped_operations, method_key:upper() .. " " .. path_key)
            else
              table.insert(method_entries, { lower = lower, original = method_key })
            end
          end
        end
      end
      table.sort(method_entries, function(a, b)
        return a.lower < b.lower
      end)

      for _, entry in ipairs(method_entries) do
        table.insert(blocks, build_request_block(entry.lower, path_key, base_url, path_item[entry.original]))
      end
    end
  end

  if #ref_skipped_paths > 0 then
    table.sort(ref_skipped_paths)
    ui.notify_warn(
      "Skipped $ref path item(s) (external/internal path-item references are out of scope for this story): "
        .. table.concat(ref_skipped_paths, ", ")
    )
  end

  if #ref_skipped_operations > 0 then
    table.sort(ref_skipped_operations)
    ui.notify_warn(
      "Skipped operation(s) expressed as a bare $ref (no inline operation object to generate from): "
        .. table.concat(ref_skipped_operations, ", ")
    )
  end

  if #blocks == 0 then
    ui.notify_warn("No operations found under `paths` in OpenAPI spec: " .. spec_path)
    return nil
  end

  return table.concat(blocks, "\n\n") .. "\n"
end

--- Discover JSON OpenAPI / Swagger spec files under `root` (bounded depth).
--- Matches the conventional filenames plus `*.openapi.json` / `*.swagger.json`;
--- YAML specs are skipped (JSON only, per this module's scope). Vendored trees
--- (`node_modules`, `target`, `build`, `.git`, `.gradle`, `dist`, `out`) are
--- pruned so a monorepo scan stays cheap.
---@param root string
---@return string[]
function M.discover_specs(root)
  if type(root) ~= "string" or root == "" then
    return {}
  end
  root = vim.fs.normalize(root)

  local exact = {
    ["openapi.json"] = true,
    ["swagger.json"] = true,
    ["api-docs.json"] = true,
  }
  -- Any path segment matching one of these prunes the file. vim.fs.find has no
  -- dir-prune hook, so this is a post-filter on the containing directory path.
  local pruned = {
    ["node_modules"] = true,
    ["target"] = true,
    ["build"] = true,
    ["dist"] = true,
    ["out"] = true,
    [".git"] = true,
    [".gradle"] = true,
    [".idea"] = true,
  }

  local found = vim.fs.find(function(name, path)
    if not (exact[name] or name:match("%.openapi%.json$") or name:match("%.swagger%.json$")) then
      return false
    end
    local rel = path:sub(#root + 1)
    local depth = 0
    for seg in rel:gmatch("[^/]+") do
      if pruned[seg] then
        return false
      end
      depth = depth + 1
    end
    return depth <= 6
  end, { path = root, type = "file", limit = 25 })

  return found or {}
end

--- Parse a JSON OpenAPI spec at `spec_path` into a flat endpoint list.
--- Non-throwing: returns an empty list (never nil) for a missing / YAML /
--- non-JSON / pathless spec, so a caller merging several specs never has to
--- nil-check. `line` is a best-effort source line (the first raw line quoting
--- the path key) for jump-to-source into the spec file.
---@param spec_path string
---@return { http_method: string, path: string, operation_id: string, summary: string, file: string, line: integer, source: string }[]
function M.list_endpoints(spec_path)
  if type(spec_path) ~= "string" or spec_path == "" then
    return {}
  end
  spec_path = vim.fs.normalize(spec_path)
  if spec_path:lower():match("%.ya?ml$") or vim.fn.filereadable(spec_path) ~= 1 then
    return {}
  end

  local ok_read, raw_lines = pcall(vim.fn.readfile, spec_path)
  if not ok_read or type(raw_lines) ~= "table" then
    return {}
  end
  local raw = table.concat(raw_lines, "\n"):gsub("^\239\187\191", "")
  local ok_decode, spec = pcall(vim.json.decode, raw)
  if not ok_decode or type(spec) ~= "table" or type(spec.paths) ~= "table" then
    return {}
  end

  local function line_of(path_key)
    local needle = '"' .. path_key .. '"'
    for i, l in ipairs(raw_lines) do
      if l:find(needle, 1, true) then
        return i
      end
    end
    return 1
  end

  local out = {}
  for path_key, path_item in pairs(spec.paths) do
    if type(path_key) == "string" and path_key:match("^/") and type(path_item) == "table" then
      local ln = line_of(path_key)
      for method_key, op in pairs(path_item) do
        if type(method_key) == "string" and HTTP_METHODS[method_key:lower()] then
          local operation_id, summary = "", ""
          if type(op) == "table" then
            if type(op.operationId) == "string" then
              operation_id = op.operationId:gsub("[\r\n]+", " ")
            end
            if type(op.summary) == "string" then
              summary = op.summary:gsub("[\r\n]+", " ")
            end
          end
          out[#out + 1] = {
            http_method = method_key:upper(),
            path = path_key,
            operation_id = operation_id,
            summary = summary,
            file = spec_path,
            line = ln,
            source = "openapi",
          }
        end
      end
    end
  end

  table.sort(out, function(a, b)
    if a.path == b.path then
      return a.http_method < b.http_method
    end
    return a.path < b.path
  end)
  return out
end

return M
