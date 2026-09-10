-- TetraVim Native Spring Boot Discovery (Story 2.3)
-- Pure-Lua + Tree-sitter Spring Boot discovery, bean extraction, REST endpoint parsing,
-- and DAP configuration generation. Replaces legacy Scala engine Spring features.

local refactor_ts = require("tetravim.util.refactor_treesitter")

local M = {}

M.SCAN_TIMEOUT_MS = 15000

local STEREOTYPES = {
  Component = true,
  Service = true,
  Repository = true,
  RestController = true,
  Controller = true,
}

local SPRING_METHODS = {
  GetMapping = "GET",
  PostMapping = "POST",
  PutMapping = "PUT",
  DeleteMapping = "DELETE",
  PatchMapping = "PATCH",
}

local JAX_RS_METHODS = {
  GET = "GET",
  POST = "POST",
  PUT = "PUT",
  DELETE = "DELETE",
  PATCH = "PATCH",
  HEAD = "HEAD",
  OPTIONS = "OPTIONS",
}

-- Tree-sitter query text held as local string constants, parsed via vim.treesitter.query.parse
local JAVA_CLASS_QUERY = [[
  [
    (class_declaration)
    (interface_declaration)
    (record_declaration)
  ] @class_decl
]]

local KOTLIN_CLASS_QUERY = [[
  [
    (class_declaration)
    (object_declaration)
  ] @class_decl
]]

local JAVA_METHOD_QUERY = [[
  (method_declaration) @method_decl
]]

local KOTLIN_FUNC_QUERY = [[
  (function_declaration) @func_decl
]]

--- Probe if tree-sitter parser for `lang` is available.
---@param lang string
---@return boolean
function M.has_parser(lang)
  local ok, parser = pcall(vim.treesitter.get_string_parser, "", lang)
  return ok and parser ~= nil
end

--- Extract node text from buffer/content string.
---@param node TSNode|nil
---@param content string
---@return string
local function get_text(node, content)
  if not node then
    return ""
  end
  return vim.treesitter.get_node_text(node, content)
end

--- Find first child of `node` matching `type_name`.
---@param node TSNode|nil
---@param type_name string
---@return TSNode|nil
local function find_child_by_type(node, type_name)
  if not node then
    return nil
  end
  for c in node:iter_children() do
    if c:type() == type_name then
      return c
    end
  end
  return nil
end

--- Decapitalize a string preserving leading all-caps run (JavaBeans Introspector convention).
---@param str string|nil
---@return string|nil
function M.decapitalize(str)
  if not str or str == "" then
    return str
  end
  if #str >= 2 and str:sub(1, 1):match("%u") and str:sub(2, 2):match("%u") then
    return str
  end
  return str:sub(1, 1):lower() .. str:sub(2)
end

--- Normalize a path segment: trim quotes, leading/trailing slashes.
---@param s string|nil
---@return string
function M.norm_segment(s)
  if not s then
    return ""
  end
  s = s:match('^"([^"]*)"$') or s:match("^'([^']*)'$") or s
  s = s:gsub("^/+", ""):gsub("/+$", "")
  return s
end

--- Join base and sub path segments, ensuring single leading slash and no duplicate slashes.
---@param base string|nil
---@param sub string|nil
---@return string
function M.join_paths(base, sub)
  local b = M.norm_segment(base)
  local s = M.norm_segment(sub)
  if b == "" and s == "" then
    return "/"
  elseif b == "" then
    return "/" .. s
  elseif s == "" then
    return "/" .. b
  else
    return "/" .. b .. "/" .. s
  end
end

--- Parse a Java annotation node (marker_annotation or annotation).
---@param annot_node TSNode
---@param content string
---@return { name: string|nil, path: string, method: string|nil, line: integer, node: TSNode }
local function parse_java_annotation(annot_node, content)
  local name = nil
  local path = ""
  local method = nil
  local annot_line = annot_node:range() + 1

  local name_node = annot_node:field("name")[1]
  if not name_node then
    for c in annot_node:iter_children() do
      if c:type() == "identifier" or c:type() == "scoped_identifier" then
        name_node = c
        break
      end
    end
  end
  if name_node then
    name = get_text(name_node, content):match("([%w_]+)$")
  end

  local args_node = annot_node:field("arguments")[1] or find_child_by_type(annot_node, "annotation_argument_list")
  if args_node then
    for arg in args_node:iter_children() do
      if arg:type() == "string_literal" then
        path = M.norm_segment(get_text(arg, content))
      elseif arg:type() == "element_value_pair" then
        local key = nil
        local val = nil
        for c in arg:iter_children() do
          if c:type() == "identifier" and not key then
            key = get_text(c, content)
          elseif c:type() ~= "=" and c:type() ~= "identifier" then
            val = c
          end
        end
        if key == "value" or key == "path" then
          if val then
            if val:type() == "string_literal" then
              path = M.norm_segment(get_text(val, content))
            elseif val:type() == "array_initializer" then
              for elem in val:iter_children() do
                if elem:type() == "string_literal" then
                  path = M.norm_segment(get_text(elem, content))
                  break
                end
              end
            end
          end
        elseif key == "method" and val then
          local vtext = get_text(val, content)
          method = vtext:match("RequestMethod%.([%w_]+)") or vtext:match("([%w_]+)$")
        end
      end
    end
  end

  return {
    name = name,
    path = path,
    method = method,
    line = annot_line,
    node = annot_node,
  }
end

--- Parse a Kotlin annotation node.
---@param annot_node TSNode
---@param content string
---@return { name: string|nil, path: string, method: string|nil, line: integer, node: TSNode }
local function parse_kotlin_annotation(annot_node, content)
  local name = nil
  local path = ""
  local method = nil
  local annot_line = annot_node:range() + 1

  for c in annot_node:iter_children() do
    if c:type() == "user_type" then
      for id in c:iter_children() do
        if id:type() == "type_identifier" then
          name = get_text(id, content)
        end
      end
    elseif c:type() == "constructor_invocation" then
      for sub in c:iter_children() do
        if sub:type() == "user_type" then
          for id in sub:iter_children() do
            if id:type() == "type_identifier" then
              name = get_text(id, content)
            end
          end
        elseif sub:type() == "value_arguments" then
          for varg in sub:iter_children() do
            if varg:type() == "value_argument" then
              local key = nil
              for elem in varg:iter_children() do
                if elem:type() == "simple_identifier" and not key then
                  key = get_text(elem, content)
                elseif elem:type() == "string_literal" then
                  path = M.norm_segment(get_text(elem, content))
                elseif elem:type() == "collection_literal" then
                  for lit in elem:iter_children() do
                    if lit:type() == "string_literal" then
                      path = M.norm_segment(get_text(lit, content))
                      break
                    end
                  end
                end
              end
              if key == "method" then
                local vtext = get_text(varg, content)
                method = vtext:match("RequestMethod%.([%w_]+)") or vtext:match("([%w_]+)$")
              end
            end
          end
        end
      end
    end
  end

  return {
    name = name,
    path = path,
    method = method,
    line = annot_line,
    node = annot_node,
  }
end

--- Extract endpoint definition from a method/function TSNode.
---@param method_node TSNode
---@param content string
---@param lang string
---@param class_base_path string
---@param class_name string
---@param file? string
---@return { file: string, line: integer, http_method: string, path: string, class_name: string, handler_name: string }|nil
function M.endpoint_from_method(method_node, content, lang, class_base_path, class_name, file)
  local handler_name = ""
  local http_method = nil
  local method_path = ""
  local mapping_line = nil

  local mods = find_child_by_type(method_node, "modifiers")
  if not mods then
    return nil
  end

  if lang == "java" then
    handler_name = get_text(method_node:field("name")[1] or find_child_by_type(method_node, "identifier"), content)
    for annot in mods:iter_children() do
      if annot:type():find("annotation") then
        local a = parse_java_annotation(annot, content)
        if SPRING_METHODS[a.name] then
          http_method = SPRING_METHODS[a.name]
          method_path = a.path
          mapping_line = a.line
        elseif a.name == "RequestMapping" then
          http_method = a.method or "GET"
          method_path = a.path
          mapping_line = a.line
        elseif JAX_RS_METHODS[a.name] then
          http_method = JAX_RS_METHODS[a.name]
          mapping_line = a.line
        elseif a.name == "Path" then
          method_path = a.path
          if not mapping_line then
            mapping_line = a.line
          end
        end
      end
    end
  elseif lang == "kotlin" then
    handler_name = get_text(find_child_by_type(method_node, "simple_identifier"), content)
    for annot in mods:iter_children() do
      if annot:type() == "annotation" then
        local a = parse_kotlin_annotation(annot, content)
        if SPRING_METHODS[a.name] then
          http_method = SPRING_METHODS[a.name]
          method_path = a.path
          mapping_line = a.line
        elseif a.name == "RequestMapping" then
          http_method = a.method or "GET"
          method_path = a.path
          mapping_line = a.line
        elseif JAX_RS_METHODS[a.name] then
          http_method = JAX_RS_METHODS[a.name]
          mapping_line = a.line
        elseif a.name == "Path" then
          method_path = a.path
          if not mapping_line then
            mapping_line = a.line
          end
        end
      end
    end
  end

  if not http_method then
    return nil
  end

  return {
    file = file or "",
    line = mapping_line or (method_node:range() + 1),
    http_method = http_method,
    path = M.join_paths(class_base_path, method_path),
    class_name = class_name,
    handler_name = handler_name,
  }
end

--- Parse AST to extract REST endpoints in `content`.
---@param content string
---@param lang string "java" or "kotlin"
---@param file? string
---@return table[] Array of { file, line, http_method, path, class_name, handler_name }
function M._endpoints_in_content(content, lang, file)
  local root = refactor_ts._ts_root_for(content, lang)
  if not root then
    return {}
  end

  local endpoints = {}
  local class_query_str = (lang == "java") and JAVA_CLASS_QUERY or KOTLIN_CLASS_QUERY
  local ok_q, class_query = pcall(vim.treesitter.query.parse, lang, class_query_str)
  if not ok_q or not class_query then
    return {}
  end

  for _, class_node in class_query:iter_captures(root, content) do
    local class_name = ""
    local class_base_path = ""
    local mods = find_child_by_type(class_node, "modifiers")

    if lang == "java" then
      class_name = get_text(class_node:field("name")[1] or find_child_by_type(class_node, "identifier"), content)
      if mods then
        for annot in mods:iter_children() do
          if annot:type():find("annotation") then
            local a = parse_java_annotation(annot, content)
            if a.name == "RequestMapping" or a.name == "Path" then
              class_base_path = a.path
            end
          end
        end
      end
    elseif lang == "kotlin" then
      class_name = get_text(
        find_child_by_type(class_node, "type_identifier") or find_child_by_type(class_node, "simple_identifier"),
        content
      )
      if mods then
        for annot in mods:iter_children() do
          if annot:type() == "annotation" then
            local a = parse_kotlin_annotation(annot, content)
            if a.name == "RequestMapping" or a.name == "Path" then
              class_base_path = a.path
            end
          end
        end
      end
    end

    local body = find_child_by_type(class_node, "class_body") or find_child_by_type(class_node, "interface_body")
    if body then
      local method_query_str = (lang == "java") and JAVA_METHOD_QUERY or KOTLIN_FUNC_QUERY
      local ok_mq, method_query = pcall(vim.treesitter.query.parse, lang, method_query_str)
      if ok_mq and method_query then
        for _, method_node in method_query:iter_captures(body, content) do
          local ep = M.endpoint_from_method(method_node, content, lang, class_base_path, class_name, file)
          if ep then
            table.insert(endpoints, ep)
          end
        end
      end
    end
  end

  return endpoints
end

--- Parse AST to extract Spring beans in `content`.
---@param content string
---@param lang string "java" or "kotlin"
---@param file? string
---@return table[] Array of { file, line, bean_name, class_name, injected_deps }
function M._beans_in_content(content, lang, file)
  local root = refactor_ts._ts_root_for(content, lang)
  if not root then
    return {}
  end

  local beans = {}
  local class_query_str = (lang == "java") and JAVA_CLASS_QUERY or KOTLIN_CLASS_QUERY
  local ok_q, class_query = pcall(vim.treesitter.query.parse, lang, class_query_str)
  if not ok_q or not class_query then
    return {}
  end

  for _, class_node in class_query:iter_captures(root, content) do
    local is_stereotype = false
    local mods = find_child_by_type(class_node, "modifiers")
    if mods then
      for annot in mods:iter_children() do
        local aname = nil
        if lang == "java" and annot:type():find("annotation") then
          aname = parse_java_annotation(annot, content).name
        elseif lang == "kotlin" and annot:type() == "annotation" then
          aname = parse_kotlin_annotation(annot, content).name
        end
        if aname and STEREOTYPES[aname] then
          is_stereotype = true
          break
        end
      end
    end

    if is_stereotype then
      local class_name = ""
      if lang == "java" then
        class_name = get_text(class_node:field("name")[1] or find_child_by_type(class_node, "identifier"), content)
      elseif lang == "kotlin" then
        class_name = get_text(
          find_child_by_type(class_node, "type_identifier") or find_child_by_type(class_node, "simple_identifier"),
          content
        )
      end

      local bean_name = M.decapitalize(class_name)
      local line = class_node:range() + 1
      local injected_deps = {}

      if class_node:type() ~= "interface_declaration" then
        local body = find_child_by_type(class_node, "class_body")

        if lang == "java" and body then
          local ctors = {}
          for m in body:iter_children() do
            if m:type() == "constructor_declaration" then
              local has_autowired = false
              local cmods = find_child_by_type(m, "modifiers")
              if cmods then
                for a in cmods:iter_children() do
                  if a:type():find("annotation") and parse_java_annotation(a, content).name == "Autowired" then
                    has_autowired = true
                    break
                  end
                end
              end
              table.insert(ctors, { node = m, autowired = has_autowired })
            end
          end

          local target_ctors = {}
          if #ctors == 1 then
            table.insert(target_ctors, ctors[1].node)
          elseif #ctors > 1 then
            for _, c in ipairs(ctors) do
              if c.autowired then
                table.insert(target_ctors, c.node)
              end
            end
          end

          for _, ctor in ipairs(target_ctors) do
            local params = find_child_by_type(ctor, "formal_parameters")
            if params then
              for p_node in params:iter_children() do
                if p_node:type() == "formal_parameter" then
                  local t_node = p_node:field("type")[1]
                  if not t_node then
                    for c in p_node:iter_children() do
                      if c:type():find("type") then
                        t_node = c
                        break
                      end
                    end
                  end
                  if t_node then
                    local t_text = get_text(t_node, content):match("([%w_]+)$")
                    if t_text then
                      table.insert(injected_deps, M.decapitalize(t_text))
                    end
                  end
                end
              end
            end
          end

          for m in body:iter_children() do
            if m:type() == "field_declaration" then
              local fmods = find_child_by_type(m, "modifiers")
              local has_autowired = false
              if fmods then
                for a in fmods:iter_children() do
                  if a:type():find("annotation") and parse_java_annotation(a, content).name == "Autowired" then
                    has_autowired = true
                    break
                  end
                end
              end
              if has_autowired then
                local t_node = m:field("type")[1] or find_child_by_type(m, "type_identifier")
                if t_node then
                  local t_text = get_text(t_node, content):match("([%w_]+)$")
                  if t_text then
                    table.insert(injected_deps, M.decapitalize(t_text))
                  end
                end
              end
            elseif m:type() == "method_declaration" then
              local mmods = find_child_by_type(m, "modifiers")
              local has_autowired = false
              if mmods then
                for a in mmods:iter_children() do
                  if a:type():find("annotation") and parse_java_annotation(a, content).name == "Autowired" then
                    has_autowired = true
                    break
                  end
                end
              end
              if has_autowired then
                local params = find_child_by_type(m, "formal_parameters")
                if params then
                  for p_node in params:iter_children() do
                    if p_node:type() == "formal_parameter" then
                      local t_node = p_node:field("type")[1] or find_child_by_type(p_node, "type_identifier")
                      if t_node then
                        local t_text = get_text(t_node, content):match("([%w_]+)$")
                        if t_text then
                          table.insert(injected_deps, M.decapitalize(t_text))
                        end
                      end
                      break
                    end
                  end
                end
              end
            end
          end
        elseif lang == "kotlin" then
          local pctor = find_child_by_type(class_node, "primary_constructor")
          if pctor then
            for param in pctor:iter_children() do
              if param:type() == "class_parameter" then
                local utype = find_child_by_type(param, "user_type")
                if utype then
                  local tid = find_child_by_type(utype, "type_identifier")
                  if tid then
                    local t_text = get_text(tid, content)
                    table.insert(injected_deps, M.decapitalize(t_text))
                  end
                end
              end
            end
          end

          if body then
            for prop in body:iter_children() do
              if prop:type() == "property_declaration" then
                local pmods = find_child_by_type(prop, "modifiers")
                local has_autowired = false
                if pmods then
                  for a in pmods:iter_children() do
                    if a:type() == "annotation" and parse_kotlin_annotation(a, content).name == "Autowired" then
                      has_autowired = true
                      break
                    end
                  end
                end
                if has_autowired then
                  local var_decl = find_child_by_type(prop, "variable_declaration")
                  local utype = var_decl and find_child_by_type(var_decl, "user_type")
                  if utype then
                    local tid = find_child_by_type(utype, "type_identifier")
                    if tid then
                      local t_text = get_text(tid, content)
                      table.insert(injected_deps, M.decapitalize(t_text))
                    end
                  end
                end
              end
            end
          end
        end
      end

      -- De-duplicate dependencies preserving order
      local deduped = {}
      local seen = {}
      for _, dep in ipairs(injected_deps) do
        if not seen[dep] then
          seen[dep] = true
          table.insert(deduped, dep)
        end
      end

      table.insert(beans, {
        file = file or "",
        line = line,
        bean_name = bean_name,
        class_name = class_name,
        injected_deps = deduped,
      })
    end
  end

  return beans
end

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
