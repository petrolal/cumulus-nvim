-- TetraVim Lua Buffer Conventions
-- Sets buffer-local formatting and comment handling for Lua files

-- Indentation: 2-space soft tabs
require("tetravim.util.ftconv").soft_tabs()

-- Comment formatting: -- %s
vim.bo.commentstring = "-- %s"
vim.bo.comments = ":---,:--"
