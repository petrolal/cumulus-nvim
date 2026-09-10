-- TetraVim XML Buffer Conventions (IntelliJ Ultimate Parity; LSP/formatting owned by lsp-devops.lua)
-- Sets buffer-local formatting and comment handling for XML files

-- Indentation: 2-space soft tabs (IntelliJ default)
require("tetravim.util.ftconv").soft_tabs()

-- Comment formatting: Supports <!-- --> single & multi-line comment blocks
vim.bo.commentstring = "<!-- %s -->"
vim.bo.comments = "s:<!--,m:  ,e:-->"
