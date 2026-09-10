-- TetraVim JSP / JSTL Buffer Conventions (IntelliJ IDEA Ultimate "JSP" parity)
--
-- Neovim ships a bundled `jsp` syntax (HTML + embedded Java); there is no OSS
-- JSP language server. This adds the editor ergonomics IDEA gives .jsp/.jspf
-- files: 2-space indent, `<%-- --%>` comment strings, matchit tag pairs, and
-- emmet (declared in lsp-web-tooling.lua).

vim.bo.shiftwidth = 2
vim.bo.tabstop = 2
vim.bo.softtabstop = 2
vim.bo.expandtab = true

-- JSP comments (`<%-- --%>`) are stripped before the response, unlike HTML
-- `<!-- -->` comments -- prefer them for the `gc` operator.
vim.bo.commentstring = "<%-- %s --%>"
vim.bo.comments = "s:<%--,m:  ,e:--%>"

vim.bo.suffixesadd = ".jsp,.jspf,.tag"

-- matchit: pair JSP scriptlet / declaration / expression / directive delimiters
-- and the common JSTL block tags via `%`.
vim.b.match_words = table.concat({
  [[<%--:--%>]],
  [[<%[!=@]\?:%>]],
  [[<c:if\>:</c:if>]],
  [[<c:forEach\>:</c:forEach>]],
  [[<c:choose>:<c:when\>:<c:otherwise>:</c:choose>]],
}, ",")
