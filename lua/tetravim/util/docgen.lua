-- TetraVim documentation-comment generation (Javadoc / KDoc / docstrings).
--
-- jdtls only stubs a Javadoc block on `/**`+<CR> and kotlin_language_server has
-- no KDoc generation at all, so neither covers "one key -> annotated doc stub"
-- across the JVM + polyglot stack. This is the thin dispatcher the <leader>cg
-- keymaps (registered in plugins/editor-docgen.lua) call into: it drives
-- `danymat/neogen` -- Tree-sitter driven, language-agnostic, emitting
-- `@param` / `@return` placeholders as jumpable LuaSnip snippet fields -- and
-- degrades to a single notify when neogen is not loaded.

local M = {}

local ui = require("tetravim.util.ui")

local function notify_warn(msg)
  ui.notify_warn(msg, "TetraVim Doc")
end

--- Generate a documentation stub for the construct under the cursor.
---@param kind? "func"|"class"|"type"|"file" what to document (default: "func" -- nearest function/method)
function M.generate(kind)
  local ok, neogen = pcall(require, "neogen")
  if not ok then
    notify_warn("neogen is not available -- run :Lazy sync")
    return
  end

  kind = kind or "func"

  -- neogen.generate() returns false (rather than raising) when the current
  -- filetype has no template or the cursor is not on a documentable node.
  local ok_gen, generated = pcall(neogen.generate, { type = kind })
  if not ok_gen then
    notify_warn("Doc generation failed: " .. tostring(generated))
  elseif generated == false then
    notify_warn(string.format("No %s doc template for this position (filetype %q)", kind, vim.bo.filetype))
  end
end

return M
