-- TetraVim Template-Language Stack
-- IntelliJ IDEA Ultimate bundles a dozen template engines; the Neovim
-- ecosystem has real tooling for only some. Honest coverage map:
--
--   Handlebars / Mustache  -> built-in `hbs`/`mustache` ft + Tree-sitter + emmet
--   Pug / Jade             -> built-in `pug` ft + Tree-sitter `pug` + emmet
--   EJS / ERB              -> `.ejs` mapped to `eruby` ft + Tree-sitter
--                             `embedded_template` + emmet
--   Jinja2 / Django        -> `htmldjango` ft + djlint (format + lint, see
--                             tools-formatting.lua / tools-linting.lua) + emmet
--   Thymeleaf              -> plain `.html`: html LSP + emmet already apply
--   FreeMarker / Velocity  -> no OSS server/parser; TetraVim ships an
--                             HTML-embedded `syntax/{freemarker,velocity}.vim`
--                             (directive + interpolation highlighting) plus
--                             `ftplugin/{freemarker,velocity}.lua` conventions
--                             (2-space indent, directive-aware commentstring,
--                             matchit block pairs) + emmet
--   JSP / JSTL             -> built-in `jsp` ft (html+java) + `ftplugin/jsp.lua`
--                             (`<%-- --%>` comments, matchit tag pairs) + emmet
--
-- emmet attachment for these filetypes is declared in lsp-web-tooling.lua.

vim.filetype.add({
  extension = {
    ftl = "freemarker",
    ftlh = "freemarker",
    ftlx = "freemarker",
    vm = "velocity",
    j2 = "htmldjango",
    jinja = "htmldjango",
    jinja2 = "htmldjango",
    ejs = "eruby",
    jspf = "jsp",
  },
})

return {
  {
    "nvim-treesitter/nvim-treesitter",
    opts = function(_, opts)
      if type(opts.ensure_installed) == "table" then
        vim.list_extend(opts.ensure_installed, { "embedded_template", "pug" })
      end
    end,
  },
}
