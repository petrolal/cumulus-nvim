-- TetraVim CSS Buffer Conventions
-- Sets buffer-local formatting and comment handling for CSS files

-- Indentation: 2-space soft tabs
require("tetravim.util.ftconv").soft_tabs()

-- Comment formatting: /* ... */
vim.bo.commentstring = "/* %s */"
vim.bo.comments = "s1:/*,mb:*,ex:*/"
