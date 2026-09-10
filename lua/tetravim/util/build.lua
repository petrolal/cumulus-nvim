-- TetraVim JVM build-tool detection
--
-- Walks up from a starting path looking for the marker file that identifies a
-- Maven or Gradle project root. Pure Neovim (vim.fs); no external process.

local M = {}

local GRADLE_MARKERS = { "build.gradle", "build.gradle.kts", "settings.gradle", "settings.gradle.kts" }
local MAVEN_MARKERS = { "pom.xml" }

--- Helper to inspect a directory for Gradle or Maven markers upward.
---@param path? string
---@return "maven"|"gradle"|nil tool
---@return string|nil root
local function find_upward(path)
  if not path or path == "" then
    return nil, nil
  end

  -- Strip oil:// or file:// protocol prefixes
  path = path:gsub("^oil://", ""):gsub("^file://", "")

  -- If it's a file, start from its containing directory
  if vim.fn.filereadable(path) == 1 then
    path = vim.fs.dirname(path)
  end

  if vim.fn.isdirectory(path) ~= 1 then
    return nil, nil
  end

  local gradle = vim.fs.find(GRADLE_MARKERS, { upward = true, path = path, type = "file" })[1]
  local maven = vim.fs.find(MAVEN_MARKERS, { upward = true, path = path, type = "file" })[1]

  -- Prefer the marker closest to `path`; on a tie Gradle wins (wrapper-driven repos).
  if gradle and maven then
    if #vim.fs.dirname(gradle) >= #vim.fs.dirname(maven) then
      return "gradle", vim.fs.dirname(gradle)
    end
    return "maven", vim.fs.dirname(maven)
  elseif gradle then
    return "gradle", vim.fs.dirname(gradle)
  elseif maven then
    return "maven", vim.fs.dirname(maven)
  end

  return nil, nil
end

--- Find all JVM projects located in immediate subdirectories of a given directory.
---@param base_dir? string
---@return { tool: "maven"|"gradle", root: string, name: string }[]
function M.find_subprojects(base_dir)
  base_dir = base_dir or vim.fn.getcwd()
  if vim.fn.isdirectory(base_dir) ~= 1 then
    return {}
  end

  local candidates = {}
  local subdirs = vim.fn.glob(base_dir .. "/*", false, true)
  for _, sub in ipairs(subdirs) do
    if vim.fn.isdirectory(sub) == 1 then
      local name = vim.fs.basename(sub)
      local is_gradle = false
      for _, marker in ipairs(GRADLE_MARKERS) do
        if vim.fn.filereadable(sub .. "/" .. marker) == 1 then
          is_gradle = true
          break
        end
      end
      if is_gradle then
        table.insert(candidates, { tool = "gradle", root = sub, name = name })
      else
        local is_maven = false
        for _, marker in ipairs(MAVEN_MARKERS) do
          if vim.fn.filereadable(sub .. "/" .. marker) == 1 then
            is_maven = true
            break
          end
        end
        if is_maven then
          table.insert(candidates, { tool = "maven", root = sub, name = name })
        end
      end
    end
  end
  return candidates
end

--- Detect the JVM build tool governing `path` or the current buffer/workspace context.
---@param path? string Starting directory or file (default: buffer -> cwd)
---@return "maven"|"gradle"|nil tool
---@return string|nil root Absolute project root directory when a tool is found
function M.detect(path)
  -- 1. If explicit path provided, check upward from it
  if path and path ~= "" then
    local tool, root = find_upward(path)
    if tool then
      return tool, root
    end
  end

  -- 2. Check upward from current buffer
  local ok_buf, buf_name = pcall(vim.api.nvim_buf_get_name, 0)
  if ok_buf and buf_name and buf_name ~= "" then
    local tool, root = find_upward(buf_name)
    if tool then
      return tool, root
    end
  end

  -- 3. Check attached LSP clients
  local get_clients = vim.lsp.get_clients or vim.lsp.buf_get_clients
  if get_clients then
    local ok_clients, clients = pcall(get_clients, { bufnr = 0 })
    if ok_clients and clients then
      for _, c in ipairs(clients) do
        if c.config and c.config.root_dir then
          local tool, root = find_upward(c.config.root_dir)
          if tool then
            return tool, root
          end
        end
      end
    end
  end

  -- 4. Check upward from getcwd()
  local cwd = vim.fn.getcwd()
  local tool, root = find_upward(cwd)
  if tool then
    return tool, root
  end

  -- 5. Downward shallow search: if cwd contains exactly 1 JVM project
  local subprojects = M.find_subprojects(cwd)
  if #subprojects == 1 then
    return subprojects[1].tool, subprojects[1].root
  end

  return nil, nil
end

local WRAPPERS = { maven = "mvnw", gradle = "gradlew" }
local SYSTEM_CMD = { maven = "mvn", gradle = "gradle" }

--- Resolve the build command for a JVM project, preferring the checked-in
--- wrapper (`mvnw` / `gradlew`) over the system tool. If the wrapper exists but
--- is not executable, its executable bit is set once via a non-blocking
--- `vim.uv.fs_chmod` (never shells out to `chmod`). Shared by
--- `util.jvm`, `util.build-sync-state` and `util.project-wizard` so wrapper
--- resolution lives in exactly one place.
---@param tool "maven"|"gradle"
---@param root? string project root (defaults to cwd)
---@return string cmd `"./mvnw"` | `"./gradlew"` | an absolute wrapper path | `"mvn"` | `"gradle"`
function M.wrapper_cmd(tool, root)
  local wrapper_name = WRAPPERS[tool]
  local system_cmd = SYSTEM_CMD[tool]
  if not wrapper_name then
    return system_cmd or ""
  end
  local cwd = root or vim.fn.getcwd()

  local function ensure_exec(path)
    if vim.fn.executable(path) == 0 then
      -- rwxr-xr-x -- the correct mode for a build wrapper script. Non-blocking;
      -- never shells out to `chmod`.
      pcall(vim.uv.fs_chmod, path, tonumber("755", 8))
    end
  end

  local local_wrapper = cwd .. "/" .. wrapper_name
  if vim.fn.filereadable(local_wrapper) == 1 then
    ensure_exec(local_wrapper)
    return "./" .. wrapper_name
  end

  local upward = vim.fs.find({ wrapper_name }, { upward = true, path = cwd, type = "file" })[1]
  if upward and vim.fn.filereadable(upward) == 1 then
    ensure_exec(upward)
    return upward
  end

  return system_cmd
end

return M
