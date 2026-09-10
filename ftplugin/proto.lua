-- TetraVim .proto Buffer Conventions (SPEC-3.4: gRPC & Protobufs Integration)
-- Sets buffer-local formatting and comment handling for Protocol Buffer
-- files, mirroring ftplugin/http.lua / ftplugin/sql.lua.

-- Indentation: 2-space soft tabs (buf / protobuf style guide default)
require("tetravim.util.ftconv").soft_tabs()

-- Comment formatting: proto3 uses "//" line comments and "/* */" block
-- comments (C-style). List the block-comment parts first so a "/*" run is
-- recognized distinctly from a plain "//" comment, matching
-- ftplugin/sql.lua's shape.
vim.bo.commentstring = "// %s"
vim.bo.comments = "s1:/*,mb:*,ex:*/,://"
