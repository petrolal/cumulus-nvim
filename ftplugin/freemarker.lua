-- TetraVim FreeMarker Buffer Conventions (IntelliJ IDEA Ultimate "FreeMarker" parity)
--
-- No OSS FreeMarker language server or Tree-sitter grammar exists, so this is
-- the honest native floor: 2-space indent, directive-aware comment strings and
-- matchit block pairs, on top of the HTML-embedded highlighting in
-- syntax/freemarker.vim and emmet (declared in lsp-web-tooling.lua).

require("tetravim.util.ftconv").soft_tabs()

-- FreeMarker comments are <#-- ... -->
vim.bo.commentstring = "<#-- %s -->"
vim.bo.comments = "s:<#--,m: ,e:-->"

vim.bo.suffixesadd = ".ftl,.ftlh,.ftlx"

-- matchit: jump between the halves of FreeMarker block directives with `%`
-- (Neovim loads the matchit plugin by default). `\s` handles `<#if x>` vs
-- `<#if>`; the closing tags carry no attributes.
vim.b.match_words = table.concat({
  [[<#if\>:<#elseif\>:<#else\>:</#if>]],
  [[<#list\>:<#else\>:</#list>]],
  [[<#assign\>:</#assign>]],
  [[<#macro\>:</#macro>]],
  [[<#function\>:</#function>]],
  [[<#switch\>:<#case\>:<#default\>:</#switch>]],
  [[<#attempt>:<#recover>:</#attempt>]],
  [[<@\w\+:</@\w\+>]],
}, ",")
