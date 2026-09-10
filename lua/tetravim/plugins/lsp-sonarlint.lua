-- TetraVim SonarQube / SonarLint Integration (Epic 6, Story 6.1)
--
-- In-editor SonarQube-rule diagnostics and rule descriptions for Java,
-- Kotlin and Scala via the SonarLint language server (Mason package
-- `sonarlint-language-server`, driven by the community `sonarlint.nvim`
-- bridge). All analysis, rule metadata and quality-profile handling come
-- from the SonarLint LS itself -- nothing is reimplemented here. The server
-- command, bundled analyzer jars and `sonar-project.properties`
-- quality-profile binding are resolved by tetravim.util.quality.sonar.
--
-- Everything is pcall-guarded: a missing plugin or a missing
-- `sonarlint-language-server` binary degrades to a single notification,
-- never a startup error -- the same resilience discipline as lsp-proto.lua.

return {
  {
    "https://gitlab.com/schrieveslaach/sonarlint.nvim",
    ft = { "java", "kotlin", "scala" },
    dependencies = { "williamboman/mason.nvim" },
    config = function()
      local sonar = require("tetravim.util.quality.sonar")
      local ui = require("tetravim.util.ui")

      local ok, sonarlint = pcall(require, "sonarlint")
      if not ok then
        ui.notify_warn("sonarlint.nvim is not installed -- run :Lazy sync to enable SonarQube diagnostics")
        return
      end

      local cmd = sonar.language_server_cmd()
      if not cmd then
        ui.notify_warn(
          "sonarlint-language-server not found -- run :MasonInstall sonarlint-language-server for SonarQube diagnostics"
        )
        return
      end

      local server = { cmd = cmd }

      -- Bind the project-specific quality profile / connected-mode settings
      -- declared in a sonar-project.properties at the project root, if any.
      local project_settings = sonar.find_project_settings()
      if project_settings and next(project_settings) then
        server.settings = { sonarlint = project_settings }
      end

      local setup_ok, setup_err = pcall(sonarlint.setup, {
        server = server,
        filetypes = sonar.FILETYPES,
      })
      if not setup_ok then
        ui.notify_err("SonarLint setup failed: " .. tostring(setup_err))
      end
    end,
  },
}
