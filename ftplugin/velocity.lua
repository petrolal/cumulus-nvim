-- TetraVim Apache Velocity Buffer Conventions (IntelliJ IDEA Ultimate "Velocity" parity)
--
-- No OSS Velocity language server or Tree-sitter grammar exists, so this is the
-- honest native floor: 2-space indent, `##` / `#* *#` comment strings and
-- matchit block pairs, on top of the HTML-embedded highlighting in
-- syntax/velocity.vim and emmet (declared in lsp-web-tooling.lua).

require("tetravim.util.ftconv").soft_tabs()

-- Velocity: `## line comment`, `#* block comment *#`. commentstring drives the
-- `gc` operator; `comments` keeps `o`/formatoptions sane inside `#* *#`.
vim.bo.commentstring = "## %s"
vim.bo.comments = "s:#*,m: *,e:*#,b:##"

vim.bo.suffixesadd = ".vm,.vhtml"

-- matchit: pair #if / #foreach / #macro / #define with their #end via `%`.
vim.b.match_words = table.concat({
  [[#\%(if\|foreach\|macro\|define\)\>:#\%(else\|elseif\)\>:#end\>]],
}, ",")
