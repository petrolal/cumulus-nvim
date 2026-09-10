-- TetraVim TypeScript Buffer Conventions
-- Sets buffer-local formatting and comment handling for TypeScript files

-- Indentation: 2-space soft tabs
require("tetravim.util.ftconv").soft_tabs()

-- Comment formatting: // ... and /* ... */
vim.bo.commentstring = "// %s"
vim.bo.comments = "sO:* -,mO:* ,ex:*/,s1:/*,mb:*,ex:*/,:///"
