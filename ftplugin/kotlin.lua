-- Kotlin Ftplugin (SPEC-2.1: Project-Wide Safe Rename)
--
-- Mirrors the unconditional <leader>cr override installed for Java in
-- ftplugin/java.lua. Installed for every Kotlin buffer regardless of LSP
-- attach so that pressing <leader>cr with no Kotlin LS client still yields
-- project_rename's visible "no project-wide rename available" notify (I/O
-- matrix "No JVM LSP attached" row) rather than silently falling through to
-- the global vim.lsp.buf.rename(). The global mapping for non-JVM
-- filetypes is untouched.
vim.keymap.set("n", "<leader>cr", function()
  require("tetravim.util.refactor").project_rename()
end, { buffer = 0, desc = "Project-Wide Rename (Kotlin)" })

-- Visual test running for Kotlin. This distribution ships no neotest adapter
-- for Kotlin (neotest-java is `.java`-only, neotest-scala is `.scala`-only), so
-- route through the in-repo Gradle/Maven runner: Tree-sitter finds the nearest
-- test class / function, output lands in the shared TetraVim split, and the
-- JUnit XML is parsed into a pass/fail summary + quickfix. Buffer-local so they
-- shadow the neotest-backed global <leader>tr / <leader>jt* maps only inside
-- Kotlin buffers.
do
  local function nearest()
    require("tetravim.util.jvm_test").run_nearest()
  end
  local function file()
    require("tetravim.util.jvm_test").run_file()
  end
  vim.keymap.set("n", "<leader>tr", nearest, { buffer = 0, desc = "Run Nearest Test (Kotlin/Gradle)" })
  vim.keymap.set("n", "<leader>tf", file, { buffer = 0, desc = "Run Test File (Kotlin/Gradle)" })
  vim.keymap.set("n", "<leader>jtt", nearest, { buffer = 0, desc = "Run Nearest Test Method (Kotlin/Gradle)" })
  vim.keymap.set("n", "<leader>jtc", file, { buffer = 0, desc = "Run Current Test Class / File (Kotlin/Gradle)" })
end
