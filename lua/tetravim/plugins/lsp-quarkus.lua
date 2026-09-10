-- TetraVim Quarkus / MicroProfile language intelligence
--
-- Two Red Hat servers, wired through `JavaHello/quarkus.nvim` +
-- `JavaHello/microprofile.nvim`:
--
--   * lsp4mp (`org.eclipse.lsp4mp.ls`) -> `application.properties` /
--     `application.yml` + `microprofile-config.properties` key/value
--     completion, hover and validation. `quarkus.nvim` appends
--     `com.redhat.quarkus.ls.jar` to its classpath so the `quarkus.*`
--     namespace is completed too.
--   * Qute LS (`com.redhat.qute.ls`) -> completion / navigation in `.html`
--     Qute templates and `@Location` references.
--
-- Both also contribute JDT extension jars to jdtls (see `ftplugin/java.lua`)
-- for `@ConfigProperty` / Qute Java-side intelligence.
--
-- Neither bundle is in Mason. `scripts/fetch-jvm-lsp-jars.sh` pulls the
-- `.vsix` files from Open VSX into `$TETRAVIM_JVM_LSP_DIR`; until that runs
-- this spec loads but stays dormant (no server spawned) and
-- `:checkhealth tetravim` explains how to enable it. Each server is a separate
-- ~1 GiB JVM on top of jdtls + the Spring Boot LS, which is why activation is
-- opt-in rather than automatic.

return {
  {
    "JavaHello/quarkus.nvim",
    dependencies = { "JavaHello/microprofile.nvim" },
    ft = { "java", "yaml", "jproperties", "html" },
    init = function()
      local function cmd_handler(cmd_opts)
        local force = cmd_opts.bang or (cmd_opts.args == "--force")
        require("tetravim.util.jvm_frameworks").fetch_jars({ force = force })
      end

      vim.api.nvim_create_user_command("TetraVimFetchJvmLspJars", cmd_handler, {
        bang = true,
        nargs = "?",
        desc = "Download Quarkus and MicroProfile language server jars from Open VSX",
      })

      vim.api.nvim_create_user_command("TetraVimInstallJvmLsp", cmd_handler, {
        bang = true,
        nargs = "?",
        desc = "Download Quarkus and MicroProfile language server jars from Open VSX (alias)",
      })
    end,
    config = function()
      local fw = require("tetravim.util.jvm_frameworks")
      local qp = fw.quarkus_paths()
      local mp = fw.microprofile_paths()
      if not (qp and mp) then
        -- Jars not fetched -- see scripts/fetch-jvm-lsp-jars.sh.
        return
      end

      local java_bin = fw.java_cmd()
      local caps = require("tetravim.util.lsp_capabilities").make()

      -- Order matters: `quarkus.setup` registers `com.redhat.quarkus.ls.jar`
      -- with the microprofile module, so it must run before the lsp4mp launch
      -- builds its classpath.
      require("quarkus").setup({
        java_bin = java_bin,
        ls_path = qp.ls_path,
        jdt_extensions_path = qp.jdt_extensions_path,
        microprofile_ext_path = qp.microprofile_ext_path,
      })
      require("microprofile").setup({
        java_bin = java_bin,
        ls_path = mp.ls_path,
        jdt_extensions_path = mp.jdt_extensions_path,
      })
      require("quarkus.launch").setup({ capabilities = vim.deepcopy(caps) })
      require("microprofile.launch").setup({ capabilities = vim.deepcopy(caps) })
    end,
  },
}
