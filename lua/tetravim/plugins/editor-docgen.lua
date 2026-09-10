-- TetraVim documentation-comment generator (danymat/neogen)
--
-- The language servers don't cover "one key -> annotated doc stub": jdtls only
-- expands `/**`+<CR> into a bare Javadoc skeleton and kotlin_language_server has
-- no KDoc generation at all. neogen fills the gap for the whole polyglot stack
-- (java, kotlin, lua, python, go, rust, ts, ...): it reads the Tree-sitter node
-- under the cursor and writes the language's idiomatic doc block -- `/** */`
-- Javadoc, KDoc, EmmyLua, docstrings -- with `@param` / `@return` placeholders
-- wired as jumpable LuaSnip fields (snippet_engine = "luasnip").
--
-- Keymaps sit in the <leader>c ("code/lsp") which-key group and dispatch through
-- util/docgen so this spec stays a thin shim:
--   <leader>cg  doc stub for the nearest function / method
--   <leader>cG  doc stub for the enclosing class / type
-- (<leader>cj* / <leader>cp* are already claimed buffer-locally by the JVM
--  build-sync and package.json version-lens namespaces respectively.)

return {
  {
    "danymat/neogen",
    dependencies = { "nvim-treesitter/nvim-treesitter" },
    keys = {
      {
        "<leader>cg",
        function()
          require("tetravim.util.edit.docgen").generate("func")
        end,
        mode = { "n" },
        desc = "Generate Doc (function)",
      },
      {
        "<leader>cG",
        function()
          require("tetravim.util.edit.docgen").generate("class")
        end,
        mode = { "n" },
        desc = "Generate Doc (class/type)",
      },
    },
    opts = {
      snippet_engine = "luasnip",
    },
  },
}
