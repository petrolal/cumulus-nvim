-- TetraVim Spring Datasource Credential Auto-Discovery
--
-- Pure-Lua file/string parsing only. Discovery is stateless: config files
-- are read fresh from disk on every call, nothing is cached or persisted.
--
-- Precedence mirrors Spring Boot's own: if a project has BOTH
-- application.properties and application.yml/application.yaml with a usable
-- spring.datasource.* block, the .properties values win and the YAML
-- file(s) are ignored entirely.
--
-- `${ENV_VAR}` / `${ENV_VAR:default}` placeholders (the standard, extremely
-- common Spring Boot idiom for datasource credentials) are resolved against
-- the current process environment, mirroring Spring's own
-- PropertySourcesPlaceholderConfigurer semantics -- see resolve_placeholders
-- below.

local ui = require("tetravim.util.ui")

local M = {}

-- Directories that are never worth descending into while hunting for Spring
-- config files -- keeps the on-every-init scan from wandering into VCS
-- internals, dependency caches, or build output on large projects. The ~90-name
-- list lives in its own file (db/ignored_dirs.lua) and arrives here already
-- built into a name->true lookup.
local IGNORED_DIRS = require("tetravim.util.clients.db.ignored_dirs")

local MAX_DEPTH = 8

--- Recursively collect every file named `filename` under `root_dir`, using a
--- bounded manual walk (rather than an unfiltered vim.fs.find) so common
--- huge/irrelevant directories never get traversed.
---
--- `truncated` is an in/out `{ hit = boolean }` table (create fresh, or
--- share across multiple calls to detect truncation anywhere across them):
--- set to `true` whenever a directory beyond `MAX_DEPTH` is skipped, so a
--- caller can warn that the scan may have missed a deeply-nested config
--- file instead of silently returning an incomplete/empty result.
---@param root_dir string
---@param filename string
---@param depth? integer
---@param results? string[]
---@param truncated? { hit: boolean }
---@return string[] results
---@return { hit: boolean } truncated
local function find_files(root_dir, filename, depth, results, truncated)
  depth = depth or 0
  results = results or {}
  truncated = truncated or { hit = false }
  if depth > MAX_DEPTH then
    truncated.hit = true
    return results, truncated
  end

  local ok, iter = pcall(vim.fs.dir, root_dir)
  if not ok or not iter then
    return results, truncated
  end

  for name, kind in iter do
    if kind == "file" and name == filename then
      local full = root_dir .. "/" .. name
      -- Test-scoped Spring config (typically an in-memory H2 DB) is not a
      -- real datasource to browse -- keep it out of vim.g.dbs.
      if not (full:find("/src/test/", 1, true) or full:find("/test/resources/", 1, true)) then
        table.insert(results, full)
      end
    elseif kind == "directory" and not IGNORED_DIRS[name] and not name:match("^%.") then
      find_files(root_dir .. "/" .. name, filename, depth + 1, results, truncated)
    end
  end

  return results, truncated
end

--- Warn once that a discovery scan hit `MAX_DEPTH` and may have missed a
--- deeply-nested application.properties/.yml/.yaml file.
---@param root_dir string
local function warn_truncated(root_dir)
  ui.notify_warn(
    string.format(
      "Spring datasource discovery under %s hit the %d-directory depth limit -- some "
        .. "application.properties/.yml/.yaml file(s) nested deeper may have been missed",
      root_dir,
      MAX_DEPTH
    )
  )
end

--- Parse `spring.datasource.{url,username,password}` out of flat dotted
--- `.properties` lines. Java's `.properties` format allows the key/value
--- separator to be `=`, `:`, OR plain whitespace (with no `=`/`:` at all) --
--- e.g. `spring.datasource.password: secret` and `spring.datasource.password
--- secret` are both valid alongside the more common `=` form. `#`/`!`
--- comments are ignored.
---@param lines string[]
---@return { url?: string, username?: string, password?: string }
local function parse_properties_lines(lines)
  local raw = {}
  for _, line in ipairs(lines) do
    local trimmed = line:match("^%s*(.-)%s*$")
    if trimmed ~= "" and not trimmed:match("^[#!]") then
      local key, val = trimmed:match("^([%w%.%-_]+)%s*[:=]?%s*(.-)%s*$")
      if key == "spring.datasource.url" then
        raw.url = val
      elseif key == "spring.datasource.username" then
        raw.username = val
      elseif key == "spring.datasource.password" then
        raw.password = val
      end
    end
  end
  return raw
end

--- Strip surrounding quotes from a YAML scalar value, if present.
---@param val string
---@return string
local function unquote(val)
  local unwrapped = val:match('^"(.*)"$') or val:match("^'(.*)'$")
  return unwrapped or val
end

--- Parse `spring: \n  datasource: \n    url: ...` out of indentation-nested
--- `.yml` lines. This is intentionally NOT a general-purpose YAML parser --
--- it only tracks an indentation stack of `key:` lines well enough to find
--- the exact `spring.datasource.{url,username,password}` path.
---@param lines string[]
---@return { url?: string, username?: string, password?: string }
local function parse_yaml_lines(lines)
  local raw = {}
  -- Stack of { indent = <n>, key = <string> } describing the current
  -- nesting path down to (but not including) the line being processed.
  local stack = {}

  for _, line in ipairs(lines) do
    if line:match("%S") and not line:match("^%s*#") then
      local indent_str, key, val = line:match("^(%s*)([%w_%-]+):%s*(.-)%s*$")
      if key then
        -- Strip a YAML trailing inline comment (whitespace + '#') from an
        -- unquoted scalar BEFORE deciding whether a value is present, so
        -- `password: secret # note` yields `secret`, not `secret # note`,
        -- and `password:   # todo` reads as null (nested/absent), not "".
        if val ~= "" and not (val:match('^"') or val:match("^'")) then
          val = (val:gsub("%s+#.*$", ""))
          val = val:match("^%s*(.-)%s*$")
        end
        local indent = #indent_str
        while #stack > 0 and stack[#stack].indent >= indent do
          table.remove(stack)
        end
        table.insert(stack, { indent = indent, key = key })

        -- A bare `key:` with nothing after it (val == "") is YAML null --
        -- the value is either absent or continues as a nested mapping on
        -- following lines, so it must NOT be recorded here. An explicit
        -- empty-string scalar (`key: ""` / `key: ''`) is different: `val`
        -- is the 2-character quoted literal at this point (unquoting
        -- happens below), so it is correctly NOT equal to "" and DOES fall
        -- through to be recorded (as an empty string, once unquoted) --
        -- e.g. `spring.datasource.password: ""` must resolve to an empty
        -- password, not be treated as a missing one.
        if val ~= "" then
          local path = {}
          for _, entry in ipairs(stack) do
            table.insert(path, entry.key)
          end
          local full_path = table.concat(path, ".")
          local value = unquote(val)
          if full_path == "spring.datasource.url" then
            raw.url = value
          elseif full_path == "spring.datasource.username" then
            raw.username = value
          elseif full_path == "spring.datasource.password" then
            raw.password = value
          end
        end
      end
    end
  end

  return raw
end

--- Percent-encode a credential component per RFC 3986 (keep only unreserved
--- characters -- ALPHA / DIGIT / "-" / "." / "_" / "~" -- literal). Without
--- this, a credential containing "@", ":", "/", or "%" would be spliced
--- straight into the URL's authority component and misparsed (e.g. an "@"
--- in a password would be read as the userinfo/host separator).
---@param str string
---@return string
local function url_encode(str)
  return (str:gsub("[^%w%-%.%_%~]", function(c)
    return string.format("%%%02X", string.byte(c))
  end))
end

--- Parse a plain `.env` file (`KEY=VALUE` lines, `#` comments, an optional
--- leading `export `, optional surrounding quotes on the value) into a
--- lookup table. Not a full dotenv implementation -- no variable
--- interpolation, no multi-line values -- just enough to resolve the
--- `${VAR}` placeholders discover_datasources() needs.
---@param lines string[]
---@return table<string, string>
local function parse_dotenv_lines(lines)
  local values = {}
  for _, line in ipairs(lines) do
    local trimmed = line:match("^%s*(.-)%s*$")
    if trimmed ~= "" and not trimmed:match("^#") then
      trimmed = trimmed:gsub("^export%s+", "")
      local key, val = trimmed:match("^([%w_]+)%s*=%s*(.-)%s*$")
      if key then
        values[key] = unquote(val)
      end
    end
  end
  return values
end

--- Load `root_dir/.env`, if present, as a fallback `${VAR}` resolution
--- source. Very common in local Spring Boot dev (IntelliJ's EnvFile plugin,
--- `direnv`, manually-sourced `.env` files, etc. all populate exactly this
--- shape) for projects that document "create a .env file" rather than
--- exporting SPRING_DATASOURCE_* in the shell tetravim.nvim itself inherits.
---@param root_dir string
---@return table<string, string>
local function load_dotenv(root_dir)
  if type(root_dir) ~= "string" or root_dir == "" then
    return {}
  end
  local path = root_dir .. "/.env"
  if vim.fn.filereadable(path) ~= 1 then
    return {}
  end
  local ok, lines = pcall(vim.fn.readfile, path)
  if not ok then
    return {}
  end
  return parse_dotenv_lines(lines)
end

--- Resolve Spring `${ENV_VAR}` / `${ENV_VAR:default}` placeholders in a
--- config value, mirroring Spring Boot's own
--- PropertySourcesPlaceholderConfigurer semantics: a SET process environment
--- variable always wins -- including one explicitly set to the empty string
--- (`FOO=`), which is a deliberate "use no password" idiom and must resolve
--- to "", not be treated as though FOO were unset entirely; otherwise a
--- matching key in the project's `root_dir/.env` file (if any) is used,
--- under the same set-including-empty rule, since that's how these
--- variables actually reach the app in the common local-dev setup;
--- otherwise the literal text after the first `:` (which may itself contain
--- `:` or `/`, e.g. a full JDBC URL default) is used; a placeholder with no
--- default and no match anywhere is left as `${VAR_NAME}` and reported as
--- unresolved. Values with no `${...}` at all pass through unchanged.
---
--- A NESTED placeholder in the default position (e.g. `${A:${B}}`) is
--- deliberately NOT resolved -- see this module's header comment / the
--- spec's boundary -- doing so naively via a single-level regex would find
--- the WRONG closing `}` (the inner placeholder's), truncate the default,
--- and leave a stray `}` in the output, silently corrupting the value. Such
--- a placeholder is left verbatim and its outer variable name is reported
--- as unresolved instead.
---
--- Two further malformed shapes are also reported as unresolved (never
--- thrown, never silently dropped): an UNTERMINATED placeholder (`${VAR`
--- with no matching `}`) reports the raw truncated text; a NAMELESS
--- placeholder (`${}`, `${:default}`) reports its (empty) body rather than
--- indexing the environment/dotenv with a nil/empty key, which would
--- otherwise throw and abort the entire calling scan.
---@param value string
---@param dotenv table<string, string> from load_dotenv()
---@return string resolved
---@return string[] unresolved names of `${VAR}`/`${VAR:default}` placeholders that could not be resolved
local function resolve_placeholders(value, dotenv)
  local unresolved = {}
  local out = {}
  local i = 1
  local len = #value

  while i <= len do
    local s = value:find("${", i, true)
    if not s then
      table.insert(out, value:sub(i))
      break
    end
    table.insert(out, value:sub(i, s - 1))

    -- Scan forward from just after '${', tracking brace depth so a nested
    -- '${...}' is detected (depth > 1) rather than stopping at ITS closing
    -- '}' as though it were the outer placeholder's.
    local j = s + 2
    local depth = 1
    local nested = false
    while j <= len and depth > 0 do
      if value:sub(j, j + 1) == "${" then
        depth = depth + 1
        nested = true
        j = j + 2
      elseif value:sub(j, j) == "}" then
        depth = depth - 1
        j = j + 1
      else
        j = j + 1
      end
    end

    if depth > 0 then
      -- Unterminated placeholder (no matching '}') -- nothing sane to do
      -- but leave the rest of the string verbatim; still report it as
      -- unresolved (every other failure path here does) so a truncated
      -- `${VAR` doesn't silently produce an un-warned value.
      local remainder = value:sub(s)
      table.insert(unresolved, remainder)
      table.insert(out, remainder)
      i = len + 1
    elseif nested then
      local inner = value:sub(s + 2, j - 2)
      local var_name = inner:match("^([^:]+)") or inner
      table.insert(unresolved, var_name)
      table.insert(out, value:sub(s, j - 1))
      i = j
    else
      local inner = value:sub(s + 2, j - 2)
      local var_name, default = inner:match("^([^:]+):?(.*)$")
      -- `${VAR}` and `${VAR:}` both parse to default == "" -- only the
      -- presence of a ':' distinguishes "no default" from "empty default".
      -- Spring resolves `${VAR:}` to an empty string.
      local has_default = inner:find(":", 1, true) ~= nil
      if var_name == nil or var_name == "" then
        -- A malformed placeholder with no name at all (`${}`, `${:default}`)
        -- -- indexing vim.uv.os_getenv()/dotenv with a nil/empty key would
        -- throw and abort the ENTIRE discover_datasources() scan for a
        -- single bad placeholder. Treat it the same as a genuinely-missing
        -- variable: unresolved, left verbatim.
        table.insert(unresolved, inner)
        table.insert(out, "${" .. inner .. "}")
      else
        -- vim.env[name] collapses an explicitly-empty environment variable
        -- (`FOO=`) to Lua `nil`, indistinguishable from FOO being unset at
        -- all -- vim.uv.os_getenv() (a thin libuv wrapper) preserves the
        -- real distinction (returns "" vs nil respectively), which is
        -- exactly what "empty-string-vs-unset" here depends on.
        local env_val = vim.uv.os_getenv(var_name)
        local dotenv_val = dotenv[var_name]
        if env_val ~= nil then
          table.insert(out, env_val)
        elseif dotenv_val ~= nil then
          table.insert(out, dotenv_val)
        elseif has_default then
          table.insert(out, default)
        else
          table.insert(unresolved, var_name)
          table.insert(out, "${" .. var_name .. "}")
        end
      end
      i = j
    end
  end

  return table.concat(out), unresolved
end

--- Convert a JDBC-style URL (`jdbc:postgresql://host:port/db`) plus
--- credentials into dadbod's own connection URL convention
--- (`driver://user:password@host:port/db`) by stripping the `jdbc:` prefix
--- and splicing the (percent-encoded) credentials into the authority
--- component.
---@param jdbc_url string
---@param username string
---@param password string
---@return string? dadbod_url nil if `jdbc_url` doesn't look like a JDBC URL, or its authority already carries credentials
local function jdbc_to_dadbod_url(jdbc_url, username, password)
  local stripped = jdbc_url:gsub("^jdbc:", "")
  local scheme, rest = stripped:match("^([%w%+]+)://(.*)$")
  if not scheme then
    return nil
  end
  -- An authority that already carries userinfo (`user:pass@host...`, valid
  -- JDBC syntax for some drivers) must not get ANOTHER username:password@
  -- spliced in front of it -- that would silently produce a corrupted URL
  -- (`scheme://new:new@old:old@host...`) rather than cleanly failing. Only
  -- the authority (before the first '/' that starts the path) is checked,
  -- so an '@' legitimately appearing later in a path/query segment doesn't
  -- false-positive.
  local authority = rest:match("^([^/]*)") or rest
  if authority:find("@", 1, true) then
    return nil
  end
  return scheme .. "://" .. url_encode(username) .. ":" .. url_encode(password) .. "@" .. rest
end

--- Build a human-readable, disambiguated connection name for a discovered
--- config file. A single match just uses the project directory name; when
--- multiple modules each have their own config file, the entry's relative
--- path is appended so `vim.g.dbs` entries don't collide.
---@param root_dir string
---@param file_path string
---@param total integer total number of files found for this filename
---@return string
local function entry_name(root_dir, file_path, total)
  local project = vim.fs.basename(root_dir)
  if total <= 1 then
    return project
  end
  local rel = file_path:sub(#root_dir + 2)
  return project .. " (" .. rel .. ")"
end

--- Turn a raw `{url, username, password}` table (possibly partial or empty)
--- into a `vim.g.dbs` entry, warning and returning nil for a malformed
--- (partially-populated) block, and silently returning nil when no
--- spring.datasource.* keys were found at all (not an error).
---@param name string
---@param raw { url?: string, username?: string, password?: string }
---@param source_path string
---@param dotenv table<string, string> from load_dotenv()
---@return { name: string, url: string }?
local function build_entry(name, raw, source_path, dotenv)
  local has_url = raw.url ~= nil
  local has_username = raw.username ~= nil
  local has_password = raw.password ~= nil

  if not (has_url or has_username or has_password) then
    return nil
  end

  if not (has_url and has_username and has_password) then
    local missing = {}
    if not has_url then
      table.insert(missing, "url")
    end
    if not has_username then
      table.insert(missing, "username")
    end
    if not has_password then
      table.insert(missing, "password")
    end
    ui.notify_warn(
      string.format(
        "Incomplete spring.datasource config in %s (missing %s) -- skipping this connection",
        source_path,
        table.concat(missing, ", ")
      )
    )
    return nil
  end

  local unresolved_vars = {}
  local resolved_url, unresolved_url = resolve_placeholders(raw.url, dotenv)
  local resolved_username, unresolved_username = resolve_placeholders(raw.username, dotenv)
  local resolved_password, unresolved_password = resolve_placeholders(raw.password, dotenv)
  vim.list_extend(unresolved_vars, unresolved_url)
  vim.list_extend(unresolved_vars, unresolved_username)
  vim.list_extend(unresolved_vars, unresolved_password)

  if #unresolved_vars > 0 then
    ui.notify_warn(
      string.format(
        "Spring datasource in %s references environment variable(s) not set in this session or in a "
          .. "project-root .env file, with no default (%s) -- skipping this connection. Set them in your "
          .. "shell, add a .env file at the project root, or add `:default` fallbacks in the config.",
        source_path,
        table.concat(unresolved_vars, ", ")
      )
    )
    return nil
  end

  local url = jdbc_to_dadbod_url(resolved_url, resolved_username, resolved_password)
  if not url then
    ui.notify_warn("Could not parse spring.datasource.url in " .. source_path .. " -- skipping this connection")
    return nil
  end

  return { name = name, url = url }
end

--- Discover Spring Boot datasource credentials under `root_dir` and return
--- them as an array of `{ name, url }` entries suitable for direct
--- assignment to `vim.g.dbs`. Returns an empty table when nothing is found.
--- `application.properties` matches take precedence over `application.yml`
--- / `application.yaml` (matching Spring Boot's own precedence, which
--- treats the `.yml` and `.yaml` extensions as equivalent); the YAML tier is
--- only consulted when no valid entry was found in any `.properties` file.
---@param root_dir string
---@return { name: string, url: string }[]
function M.discover_datasources(root_dir)
  local dbs = {}
  if type(root_dir) ~= "string" or root_dir == "" then
    return dbs
  end

  -- Avoid scanning the entire home directory or system root. This prevents hitting
  -- the depth limit immediately and discovering nested projects' datasources incorrectly.
  local home = vim.fn.expand("~")
  if root_dir == home or root_dir == "/" then
    return dbs
  end

  local dotenv = load_dotenv(root_dir)
  -- Shared across every find_files() call below so exactly one truncation
  -- warning is emitted per discover_datasources() call, however many of the
  -- individual scans (properties, yml, yaml) actually hit the depth cap.
  local truncated = { hit = false }

  local prop_files = find_files(root_dir, "application.properties", nil, nil, truncated)
  for _, path in ipairs(prop_files) do
    -- Guard each read individually (permissions, delete-after-find race,
    -- binary/NUL content) so one unreadable file skips itself rather than
    -- throwing E484/E485 and aborting the whole scan.
    local rok, lines = pcall(vim.fn.readfile, path)
    if rok and type(lines) == "table" then
      local raw = parse_properties_lines(lines)
      local entry = build_entry(entry_name(root_dir, path, #prop_files), raw, path, dotenv)
      if entry then
        table.insert(dbs, entry)
      end
    end
  end

  if #dbs > 0 then
    if truncated.hit then
      warn_truncated(root_dir)
    end
    return dbs
  end

  -- Spring Boot recognizes both `application.yml` and `application.yaml` as
  -- the same config tier -- collect both before falling back from the
  -- .properties tier.
  local yml_files = find_files(root_dir, "application.yml", nil, nil, truncated)
  -- find_files now returns (results, truncated) -- parenthesize to keep
  -- only the first return value, or vim.list_extend would receive the
  -- `truncated` table as its `start` index argument.
  vim.list_extend(yml_files, (find_files(root_dir, "application.yaml", nil, nil, truncated)))
  for _, path in ipairs(yml_files) do
    local rok, lines = pcall(vim.fn.readfile, path)
    if rok and type(lines) == "table" then
      local raw = parse_yaml_lines(lines)
      local entry = build_entry(entry_name(root_dir, path, #yml_files), raw, path, dotenv)
      if entry then
        table.insert(dbs, entry)
      end
    end
  end

  if truncated.hit then
    warn_truncated(root_dir)
  end

  return dbs
end

return M
