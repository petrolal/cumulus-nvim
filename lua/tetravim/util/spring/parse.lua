-- TetraVim Native Spring Boot Discovery -- content parser.
--
-- Carved out of lua/tetravim/util/spring.lua: everything that turns a Java /
-- Kotlin source string into structured data (annotation parsing, REST endpoint
-- extraction, Spring bean + injected-dependency extraction) plus the small path
-- string helpers those routines lean on. No filesystem, no async, no LSP -- the
-- parent module owns the scan/orchestration layer and re-exports this surface
-- as `spring._endpoints_in_content` / `spring._beans_in_content` &c.

local ast = require("tetravim.util.spring.ast")
local refactor_ts = require("tetravim.util.refactor_treesitter")

local get_text = ast.get_text
local find_child_by_type = ast.find_child_by_type
local JAVA_CLASS_QUERY = ast.JAVA_CLASS_QUERY
local KOTLIN_CLASS_QUERY = ast.KOTLIN_CLASS_QUERY
local JAVA_METHOD_QUERY = ast.JAVA_METHOD_QUERY
local KOTLIN_FUNC_QUERY = ast.KOTLIN_FUNC_QUERY

local M = {}

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
function M.java_annotation(annot_node, content)
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
function M.kotlin_annotation(annot_node, content)
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
        local a = M.java_annotation(annot, content)
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
        local a = M.kotlin_annotation(annot, content)
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
function M.endpoints_in_content(content, lang, file)
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
            local a = M.java_annotation(annot, content)
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
            local a = M.kotlin_annotation(annot, content)
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
function M.beans_in_content(content, lang, file)
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
          aname = M.java_annotation(annot, content).name
        elseif lang == "kotlin" and annot:type() == "annotation" then
          aname = M.kotlin_annotation(annot, content).name
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
                  if a:type():find("annotation") and M.java_annotation(a, content).name == "Autowired" then
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
                  if a:type():find("annotation") and M.java_annotation(a, content).name == "Autowired" then
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
                  if a:type():find("annotation") and M.java_annotation(a, content).name == "Autowired" then
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
                    if a:type() == "annotation" and M.kotlin_annotation(a, content).name == "Autowired" then
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

return M
