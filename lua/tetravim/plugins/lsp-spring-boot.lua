-- TetraVim Spring Boot language intelligence
--
-- `JavaHello/spring-boot.nvim` drives the VMware Spring Boot Language Server
-- (Mason package `vscode-spring-boot-tools`). It gives:
--
--   * `application.properties` / `application.yml` key + value completion,
--     hover and diagnostics (backed by `spring-configuration-metadata.json`
--     harvested from the project + its dependency jars -- SchemaStore has no
--     equivalent), including keys contributed by `@ConfigurationProperties`
--     types in the current project;
--   * Spring symbol navigation (`@RequestMapping` routes, beans, events) in
--     Java buffers, layered on top of jdtls via the STS4 JDT extension jars
--     (wired into the jdtls `bundles` list in `ftplugin/java.lua`).
--
-- The server attaches to `application.{properties,yml}` and to Java buffers in
-- a Spring project; nvim-cmp picks it up through the shared `nvim_lsp` source
-- because it starts with `util/lsp_capabilities` like every other server.

return {
  {
    "nvim-treesitter/nvim-treesitter",
    opts = function(_, opts)
      if type(opts.ensure_installed) == "table" then
        -- `jproperties` buffers (application.properties) -> `properties` parser.
        vim.list_extend(opts.ensure_installed, { "properties" })
      end
    end,
  },

  {
    "JavaHello/spring-boot.nvim",
    ft = { "java", "yaml", "jproperties" },
    config = function()
      local ok, spring_boot = pcall(require, "spring_boot")
      if not ok then
        return
      end
      local caps = require("tetravim.util.lsp.capabilities").make({
        -- `spring_boot.launch.update_ls_config` deep-merges `opts.server` with
        -- "keep" precedence -- our table wins -- so the STS4 executeCommand
        -- capability it relies on must be carried explicitly here.
        workspace = { executeCommand = { value = true } },
      })
      spring_boot.setup({
        java_cmd = require("tetravim.util.jvm.frameworks").java_cmd(),
        server = {
          capabilities = caps,
        },
      })
    end,
  },
}
