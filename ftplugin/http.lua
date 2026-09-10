-- TetraVim .http Buffer Conventions (SPEC-3.2: HTTP Client & REST API Explorer)
-- Sets buffer-local formatting and comment handling for .http files
-- (IntelliJ HTTP Client / kulala.nvim syntax)

-- Indentation: 2-space soft tabs
require("tetravim.util.ftconv").soft_tabs()

-- Comment formatting: .http files use "#" line comments; "###" additionally
-- delimits request blocks (IntelliJ HTTP Client / kulala.nvim convention).
-- List the longer "###" leader first so it's recognized distinctly from a
-- plain "#" comment, matching ftplugin/html.lua/ftplugin/sql.lua's shape.
vim.bo.commentstring = "# %s"
vim.bo.comments = ":###,:#"
