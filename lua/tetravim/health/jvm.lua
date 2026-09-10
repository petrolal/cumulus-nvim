-- TetraVim Healthcheck -- Project-wide safe rename, Spring Boot discovery, JVM framework config LSP
-- Carved out of the former monolithic lua/tetravim/health.lua
-- (Story 27.2 / Story 35.1 / Story 6.1). Orchestrated by health/init.lua;
-- sections run in the original order so :checkhealth output is unchanged.

local M = {}

function M.check()
  vim.health.start("TetraVim Project-Wide Safe Rename")

  if vim.fn.executable("rg") == 1 then
    vim.health.ok("rg (ripgrep): installed and executable (Spring XML/@Autowired/stereotype reference scan)")
  elseif vim.fn.executable("grep") == 1 then
    vim.health.info(
      "rg (ripgrep): NOT found on $PATH -- falling back to grep (slower). Suggestion: install ripgrep for a faster Spring-reference scan"
    )
  else
    vim.health.warn(
      "Neither 'rg' nor 'grep' found on $PATH -- the Spring XML/@Autowired/stereotype reference scan is "
        .. "unavailable; project-wide rename will only cover LSP-visible locations. Suggestion: install ripgrep or grep"
    )
  end

  vim.health.start("TetraVim Spring Boot Discovery")
  local spring = require("tetravim.util.spring")

  if spring.has_parser("java") then
    vim.health.ok("Tree-sitter java parser: installed")
  else
    vim.health.warn("Tree-sitter java parser: NOT installed (required for Spring Boot discovery)")
  end

  if vim.fn.executable("rg") == 1 then
    vim.health.ok("rg (ripgrep): installed and executable (Spring candidate scan)")
  elseif vim.fn.executable("grep") == 1 then
    vim.health.ok("grep: installed and executable (fallback for Spring candidate scan)")
  else
    vim.health.warn("Neither 'rg' nor 'grep' found on $PATH (required for Spring discovery)")
  end

  local root_info = spring.detect_root()
  if root_info then
    vim.health.ok(
      string.format(
        "Spring Boot / JVM project root: %s (%s, %s)",
        root_info.root,
        root_info.build_tool,
        root_info.project_name
      )
    )
  else
    vim.health.info("Spring Boot / JVM project root: not detected in current directory")
  end

  local ok_sl, spring_lsp = pcall(require, "tetravim.util.spring_lsp")
  if ok_sl and spring_lsp.available() then
    vim.health.ok(
      "Spring Boot LS symbol model: attached -- endpoint/bean discovery uses `workspace/symbol` (compiler-accurate)"
    )
  elseif ok_sl then
    vim.health.info(
      "Spring Boot LS symbol model: not attached -- endpoint/bean discovery falls back to the Tree-sitter + ripgrep "
        .. "scan (open a Java buffer in a Spring project to attach the server)"
    )
  else
    vim.health.warn("tetravim.util.spring_lsp: failed to load")
  end

  vim.health.start("TetraVim JVM Framework Config LSP (Spring Boot / Quarkus / MicroProfile)")

  local frameworks = require("tetravim.util.jvm_frameworks")

  -- Spring Boot LS (Mason: vscode-spring-boot-tools) --------------------------
  if pcall(require, "spring_boot") then
    vim.health.ok("spring-boot.nvim: resolvable")
  else
    vim.health.warn("spring-boot.nvim: not resolvable -- run :Lazy sync")
  end

  local sb_jar = frameworks.spring_boot_ls_jar()
  if sb_jar then
    vim.health.ok("Spring Boot Language Server jar: " .. sb_jar)
  else
    vim.health.warn(
      "Spring Boot Language Server jar: NOT found. Suggestion: :MasonInstall vscode-spring-boot-tools "
        .. "(application.properties / application.yml completion is unavailable until then)"
    )
  end

  -- Quarkus + MicroProfile (Open VSX .vsix, fetched via :TetraVimFetchJvmLspJars)
  for _, mod in ipairs({ "quarkus", "microprofile" }) do
    if pcall(require, mod) then
      vim.health.ok(mod .. ".nvim: resolvable")
    else
      vim.health.warn(mod .. ".nvim: not resolvable -- run :Lazy sync")
    end
  end

  if frameworks.quarkus_ready() then
    vim.health.ok(
      "Quarkus / lsp4mp jars: installed under "
        .. frameworks.dir()
        .. " (application.properties / .yml + quarkus.* + Qute completion active)"
    )
  else
    vim.health.info(
      "Quarkus / lsp4mp jars: NOT installed (optional). Suggestion: run "
        .. "':TetraVimFetchJvmLspJars' to download the Red Hat vscode-quarkus / "
        .. "vscode-microprofile bundles from Open VSX into "
        .. frameworks.dir()
        .. ". Each adds a ~1 GiB JVM language server."
    )
  end

  if frameworks.java_cmd() then
    vim.health.ok("JVM framework servers will launch with: " .. frameworks.java_cmd())
  else
    vim.health.info("JVM framework servers will launch with 'java' on $PATH ($JAVA_HOME not resolved to a JDK 21)")
  end

  local ok_tog, toggle = pcall(require, "tetravim.util.jvm_lsp_toggle")
  if ok_tog then
    local ram = toggle.available_ram_mb()
    if toggle.is_enabled() then
      local blocked = toggle.reason_blocked()
      if blocked then
        vim.health.warn("Quarkus / MicroProfile LSP: opted in but blocked -- " .. blocked)
      else
        vim.health.ok("Quarkus / MicroProfile LSP: opted in (<leader>jsq to disable)")
      end
    else
      vim.health.info(
        "Quarkus / MicroProfile LSP: not opted in -- <leader>jsq (or create "
          .. vim.fn.stdpath("state")
          .. "/tetravim/jvm-lsp-active) to enable the ~1 GiB servers"
      )
    end
    if ram then
      local how = ram < toggle.LOW_RAM_MB and vim.health.warn or vim.health.ok
      how(string.format("Free RAM (MemAvailable): %d MiB (auto-activate guard: %d MiB)", ram, toggle.LOW_RAM_MB))
    end
    local report = toggle.rss_report()
    if #report > 0 then
      local total = 0
      for _, e in ipairs(report) do
        local mb = e.rss_mb or 0
        total = total + mb
        vim.health.info(string.format("  %s (pid %d): %d MiB RSS", e.label, e.pid, mb))
      end
      vim.health.info(string.format("  -> %d JVM language server(s), %d MiB resident total", #report, total))
    else
      vim.health.info("  No JVM language servers currently running")
    end
  end
end

return M
