-- TetraVim Native Spring Boot Discovery -- shared Tree-sitter primitives.
--
-- Carved out of lua/tetravim/util/jvm/spring.lua: the low-level helpers and query
-- text that BOTH the content parser (spring/parse.lua) AND the async
-- main-class scan (still in the parent module) need. Kept dependency-free
-- (only `vim`) so either side can require it without a cycle.

local M = {}

-- Tree-sitter query text held as string constants, parsed via
-- vim.treesitter.query.parse at call sites.
M.JAVA_CLASS_QUERY = [[
  [
    (class_declaration)
    (interface_declaration)
    (record_declaration)
  ] @class_decl
]]

M.KOTLIN_CLASS_QUERY = [[
  [
    (class_declaration)
    (object_declaration)
  ] @class_decl
]]

M.JAVA_METHOD_QUERY = [[
  (method_declaration) @method_decl
]]

M.KOTLIN_FUNC_QUERY = [[
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
function M.get_text(node, content)
  if not node then
    return ""
  end
  return vim.treesitter.get_node_text(node, content)
end

--- Find first child of `node` matching `type_name`.
---@param node TSNode|nil
---@param type_name string
---@return TSNode|nil
function M.find_child_by_type(node, type_name)
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

return M
