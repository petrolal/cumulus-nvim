-- TetraVim HTML Buffer Conventions (IntelliJ Ultimate Parity)
-- Sets buffer-local formatting and comment handling for HTML files

-- Indentation: 2-space soft tabs (IntelliJ default)
require("tetravim.util.ftconv").soft_tabs()

-- Comment formatting: Supports <!-- --> single & multi-line comment blocks
vim.bo.commentstring = "<!-- %s -->"
vim.bo.comments = "s:<!--,m:  ,e:-->"
