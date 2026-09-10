-- TetraVim Native Spring Boot Discovery (Story 2.3)
-- Pure-Lua + Tree-sitter Spring Boot discovery, bean extraction, REST endpoint parsing,
-- and DAP configuration generation. Replaces legacy Scala engine Spring features.
--
-- This module is the scan / orchestration layer: project-root detection, the
-- async ripgrep/grep candidate-file sweep, the LSP-preferred endpoint/bean
-- queries and DAP config assembly. The pure content->data parser lives in
-- `spring/parse.lua` and the shared Tree-sitter primitives in `spring/ast.lua`;
-- both are re-exported below so existing call sites and specs keep using
-- `spring._endpoints_in_content`, `spring.decapitalize`, `spring.has_parser`, &c.

local refactor_ts = require("tetravim.util.refactor_treesitter")
local ast = require("tetravim.util.spring.ast")
local parse = require("tetravim.util.spring.parse")

local M = {}

M.SCAN_TIMEOUT_MS = 15000

-- Tree-sitter primitives still needed by `M.find_main_class` below.
local get_text = ast.get_text
local find_child_by_type = ast.find_child_by_type
local JAVA_CLASS_QUERY = ast.JAVA_CLASS_QUERY
local KOTLIN_CLASS_QUERY = ast.KOTLIN_CLASS_QUERY
local parse_java_annotation = parse.java_annotation
local parse_kotlin_annotation = parse.kotlin_annotation

--- Re-exported from `spring/ast.lua` / `spring/parse.lua`. Call sites and specs
--- read these off the parent module unchanged.
M.has_parser = ast.has_parser
M.decapitalize = parse.decapitalize
M.norm_segment = parse.norm_segment
M.join_paths = parse.join_paths
M.endpoint_from_method = parse.endpoint_from_method
M._endpoints_in_content = parse.endpoints_in_content
M._beans_in_content = parse.beans_in_content

--- Find candidate files under `root` asynchronously using `rg` or `grep`.
---@param root string
---@param regex_pattern string
---@param cb fun(files: string[]|nil)
function M._candidate_files_async(root, regex_pattern, cb)
  local has_rg = vim.fn.executable("rg") == 1
  local has_grep = vim.fn.executable("grep") == 1

  if not has_rg and not has_grep then
    vim.notify("ripgrep or grep required for Spring discovery", vim.log.levels.WARN)
    vim.schedule(function()
      cb(nil)
    end)
    return
  end

  local function finish(files)
    vim.schedule(function()
      cb(files)
    end)
  end

  local function parse_files(stdout)
    local files = {}
    local seen = {}
    for _, line in ipairs(vim.split(stdout or "", "\n", { trimempty = true })) do
      local trimmed = vim.trim(line)
      if trimmed ~= "" and not seen[trimmed] then
        seen[trimmed] = true
        table.insert(files, trimmed)
      end
    end
    return files
  end

  local function run_grep_fallback()
    vim.schedule(function()
      local grep_cmd = {
        "grep",
        "-rl",
        "-E",
        "--include=*.[jJ][aA][vV][aA]",
        "--include=*.[kK][tT]",
        "--include=*.[kK][tT][sS]",
        "--exclude-dir=.git",
        "--exclude-dir=target",
        "--exclude-dir=build",
        "--exclude-dir=node_modules",
        "--exclude-dir=.gradle",
        "--exclude-dir=out",
        "-e",
        regex_pattern,
        "--",
        root,
      }
      local ok, handle = pcall(vim.system, grep_cmd, { text = true, timeout = M.SCAN_TIMEOUT_MS }, function(result)
        if result.code == 0 then
          finish(parse_files(result.stdout))
        elseif result.code == 1 then
          finish({})
        else
          vim.notify("Spring discovery scan failed or timed out", vim.log.levels.WARN)
          finish(nil)
        end
      end)
      if not ok or not handle then
        vim.notify("Spring discovery scan failed to start grep", vim.log.levels.WARN)
        finish(nil)
      end
    end)
  end

  if has_rg then
    local rg_cmd = {
      "rg",
      "-l",
      "-e",
      regex_pattern,
      "--iglob",
      "*.java",
      "--iglob",
      "*.kt",
      "--iglob",
      "*.kts",
      "--",
      root,
    }
    local ok, handle = pcall(vim.system, rg_cmd, { text = true, timeout = M.SCAN_TIMEOUT_MS }, function(result)
      if result.code == 0 then
        finish(parse_files(result.stdout))
      elseif result.code == 1 then
        finish({})
      else
        run_grep_fallback()
      end
    end)
    if not ok or not handle then
      run_grep_fallback()
    end
  else
    run_grep_fallback()
  end
end

--- Detect Maven/Gradle project root synchronously.
---@param start_path? string
---@return { root: string, build_tool: string, project_name: string }|nil
function M.detect_root(start_path)
  local search_path = start_path or vim.fn.getcwd()
  local markers = vim.fs.find({
    "pom.xml",
    "build.gradle",
    "build.gradle.kts",
    "settings.gradle",
    "settings.gradle.kts",
  }, { upward = true, path = search_path })

  if not markers or #markers == 0 then
    return nil
  end

  local marker = markers[1]
  local root = vim.fs.dirname(marker)
  local marker_name = vim.fs.basename(marker)
  local build_tool = (marker_name == "pom.xml") and "maven" or "gradle"
  local project_name = nil

  if build_tool == "maven" then
    local f = io.open(root .. "/pom.xml", "r")
    if f then
      local pom = f:read("*a")
      f:close()
      local clean_pom = pom:gsub("<parent>.-</parent>", "")
      project_name = clean_pom:match("<artifactId>([^<]+)</artifactId>")
    end
  else
    for _, fname in ipairs({ "settings.gradle.kts", "settings.gradle" }) do
      local f = io.open(root .. "/" .. fname, "r")
      if f then
        local content = f:read("*a")
        f:close()
        project_name = content:match("rootProject%.name%s*=%s*[\"']([^\"']+)[\"']")
        if project_name then
          break
        end
      end
    end
  end

  if not project_name or project_name == "" then
    project_name = vim.fs.basename(root)
  end

  return {
    root = root,
    build_tool = build_tool,
    project_name = project_name,
  }
end

--- Find main class annotated with `@SpringBootApplication` asynchronously.
---@param root string
---@param cb fun(main_class: string|nil)
function M.find_main_class(root, cb)
  if not M.has_parser("java") then
    vim.notify("Tree-sitter java parser not available", vim.log.levels.WARN)
    vim.schedule(function()
      cb(nil)
    end)
    return
  end

  M._candidate_files_async(root, "\\bSpringBootApplication\\b", function(files)
    if not files or #files == 0 then
      cb(nil)
      return
    end

    local has_kotlin = false
    for _, f in ipairs(files) do
      if f:match("%.kts?$") then
        has_kotlin = true
        break
      end
    end
    if has_kotlin and not M.has_parser("kotlin") then
      vim.notify("Tree-sitter kotlin parser not available", vim.log.levels.WARN)
      cb(nil)
      return
    end

    for _, file in ipairs(files) do
      local ok_read, lines = pcall(vim.fn.readfile, file)
      if ok_read and lines and #lines > 0 then
        local content = table.concat(lines, "\n")
        local ext = file:match("%.([%w_]+)$")
        local lang = (ext == "kt" or ext == "kts") and "kotlin" or "java"
        local root_node = refactor_ts._ts_root_for(content, lang)
        if root_node then
          local q_str = (lang == "java") and JAVA_CLASS_QUERY or KOTLIN_CLASS_QUERY
          local ok_q, q = pcall(vim.treesitter.query.parse, lang, q_str)
          if ok_q and q then
            for _, class_node in q:iter_captures(root_node, content) do
              local is_boot_app = false
              local mods = find_child_by_type(class_node, "modifiers")
              if mods then
                for annot in mods:iter_children() do
                  local aname = nil
                  if lang == "java" and annot:type():find("annotation") then
                    aname = parse_java_annotation(annot, content).name
                  elseif lang == "kotlin" and annot:type() == "annotation" then
                    aname = parse_kotlin_annotation(annot, content).name
                  end
                  if aname == "SpringBootApplication" then
                    local row, col = annot:range()
                    if not refactor_ts._is_comment_or_string_node(root_node, row, col) then
                      is_boot_app = true
                      break
                    end
                  end
                end
              end

              if is_boot_app then
                local class_name = ""
                if lang == "java" then
                  class_name =
                    get_text(class_node:field("name")[1] or find_child_by_type(class_node, "identifier"), content)
                elseif lang == "kotlin" then
                  class_name = get_text(
                    find_child_by_type(class_node, "type_identifier")
                      or find_child_by_type(class_node, "simple_identifier"),
                    content
                  )
                end

                local pkg = refactor_ts.file_package(lines) or content:match("package%s+([%w_.]+)")
                local fqn = (pkg and pkg ~= "") and (pkg .. "." .. class_name) or class_name
                cb(fqn)
                return
              end
            end
          end
        end
      end
    end

    cb(nil)
  end)
end

--- Detect Spring Boot app info asynchronously.
---@param start_path? string
---@param cb fun(app_info: { root: string, build_tool: string, project_name: string, main_class: string }|nil)
function M.detect_app(start_path, cb)
  local root_info = M.detect_root(start_path)
  if not root_info then
    vim.schedule(function()
      cb(nil)
    end)
    return
  end

  M.find_main_class(root_info.root, function(main_class)
    if not main_class then
      cb(nil)
      return
    end

    cb({
      root = root_info.root,
      build_tool = root_info.build_tool,
      project_name = root_info.project_name,
      main_class = main_class,
    })
  end)
end

--- Build DAP launch and attach configurations asynchronously.
---@param root? string
---@param cb fun(dap_config: { launch: table, attach: table }|nil)
function M.build_dap_config(root, cb)
  local root_info = M.detect_root(root)
  if not root_info then
    vim.schedule(function()
      cb(nil)
    end)
    return
  end

  M.find_main_class(root_info.root, function(main_class)
    if not main_class then
      cb(nil)
      return
    end

    local launch = {
      type = "java",
      request = "launch",
      name = "Spring Boot: " .. root_info.project_name,
      mainClass = main_class,
      projectName = root_info.project_name,
      console = "integratedTerminal",
    }
    local attach = {
      type = "java",
      request = "attach",
      name = "Spring Boot: " .. root_info.project_name .. " (attach)",
      hostName = "127.0.0.1",
      port = 5005,
    }
    cb({ launch = launch, attach = attach })
  end)
end

--- Find all REST endpoints via the Tree-sitter + ripgrep source scan.
---@param root string
---@param cb fun(endpoints: table[]|nil)
function M._find_endpoints_scan(root, cb)
  if not M.has_parser("java") then
    vim.notify("Tree-sitter java parser not available", vim.log.levels.WARN)
    vim.schedule(function()
      cb(nil)
    end)
    return
  end

  local pattern =
    "\\b(GetMapping|PostMapping|PutMapping|DeleteMapping|PatchMapping|RequestMapping|Path|GET|POST|PUT|DELETE)\\b"
  M._candidate_files_async(root, pattern, function(files)
    if files == nil then
      cb(nil)
      return
    end
    if #files == 0 then
      cb({})
      return
    end

    local has_kotlin = false
    for _, f in ipairs(files) do
      -- Exclude Gradle DSL build scripts: they are not Kotlin source files
      -- and should not trigger the Kotlin parser requirement check.
      if f:match("%.kts?$") and not f:match("build%.gradle%.kts$") then
        has_kotlin = true
        break
      end
    end
    if has_kotlin and not M.has_parser("kotlin") then
      vim.notify("Tree-sitter kotlin parser not available", vim.log.levels.WARN)
      cb(nil)
      return
    end

    local all_endpoints = {}
    for _, file in ipairs(files) do
      local ok_read, lines = pcall(vim.fn.readfile, file)
      if ok_read and lines and #lines > 0 then
        local content = table.concat(lines, "\n")
        local ext = file:match("%.([%w_]+)$")
        local lang = (ext == "kt" or ext == "kts") and "kotlin" or "java"
        local eps = M._endpoints_in_content(content, lang, file)
        for _, ep in ipairs(eps) do
          table.insert(all_endpoints, ep)
        end
      end
    end

    cb(all_endpoints)
  end)
end

--- Find all Spring beans via the Tree-sitter + ripgrep source scan.
---@param root string
---@param cb fun(beans: table[]|nil)
function M._find_beans_scan(root, cb)
  if not M.has_parser("java") then
    vim.notify("Tree-sitter java parser not available", vim.log.levels.WARN)
    vim.schedule(function()
      cb(nil)
    end)
    return
  end

  local pattern = "\\b(Service|Component|Repository|RestController|Controller)\\b"
  M._candidate_files_async(root, pattern, function(files)
    if files == nil then
      cb(nil)
      return
    end
    if #files == 0 then
      cb({})
      return
    end

    local has_kotlin = false
    for _, f in ipairs(files) do
      if f:match("%.kts?$") then
        has_kotlin = true
        break
      end
    end
    if has_kotlin and not M.has_parser("kotlin") then
      vim.notify("Tree-sitter kotlin parser not available", vim.log.levels.WARN)
      cb(nil)
      return
    end

    local all_beans = {}
    for _, file in ipairs(files) do
      local ok_read, lines = pcall(vim.fn.readfile, file)
      if ok_read and lines and #lines > 0 then
        local content = table.concat(lines, "\n")
        local ext = file:match("%.([%w_]+)$")
        local lang = (ext == "kt" or ext == "kts") and "kotlin" or "java"
        local bs = M._beans_in_content(content, lang, file)
        for _, b in ipairs(bs) do
          table.insert(all_beans, b)
        end
      end
    end

    cb(all_beans)
  end)
end

--- Find all REST endpoints asynchronously.
---
--- Prefers the VMware Spring Boot Language Server's `workspace/symbol` model
--- (`tetravim.util.spring_lsp`) when it is attached -- it is compiler-accurate
--- and sees mappings the source scan cannot. Falls back to the Tree-sitter +
--- ripgrep scan (`M._find_endpoints_scan`) when the server is absent or returns
--- nothing.
---@param root string
---@param cb fun(endpoints: table[]|nil)
function M.find_endpoints(root, cb)
  local ok, sl = pcall(require, "tetravim.util.spring_lsp")
  if ok and sl.available() then
    sl.query_endpoints(function(list)
      if list and #list > 0 then
        cb(list)
      else
        M._find_endpoints_scan(root, cb)
      end
    end)
    return
  end
  return M._find_endpoints_scan(root, cb)
end

--- Find all Spring beans asynchronously. Prefers the Spring Boot LS symbol model
--- (`tetravim.util.spring_lsp`), falls back to `M._find_beans_scan`.
---@param root string
---@param cb fun(beans: table[]|nil)
function M.find_beans(root, cb)
  local ok, sl = pcall(require, "tetravim.util.spring_lsp")
  if ok and sl.available() then
    sl.query_beans(function(list)
      if list and #list > 0 then
        cb(list)
      else
        M._find_beans_scan(root, cb)
      end
    end)
    return
  end
  return M._find_beans_scan(root, cb)
end

return M
