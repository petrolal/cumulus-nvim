-- TetraVim SQL Buffer Conventions (DataGrip Parity follow-up)
-- Sets buffer-local formatting and comment handling for SQL files

-- Indentation: 2-space soft tabs (DataGrip default)
require("tetravim.util.ftconv").soft_tabs()

-- Comment formatting: Supports -- line comments and /* */ block comments
vim.bo.commentstring = "-- %s"
vim.bo.comments = "s1:/*,mb:*,ex:*/,://,b:--"
