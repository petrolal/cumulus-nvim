-- TetraVim Healthcheck -- Neovim core & platform, system dependencies, Tree-sitter, Gradle build lock
-- Carved out of the former monolithic lua/tetravim/health.lua
-- (Story 27.2 / Story 35.1 / Story 6.1). Orchestrated by health/init.lua;
-- sections run in the original order so :checkhealth output is unchanged.

local M = {}

function M.check()
  vim.health.start("TetraVim Neovim Core & Platform")

  -- Hard floor mirrors init.lua: vim.lsp.config/vim.lsp.enable, vim.diagnostic.jump
  -- and winborder are all 0.11 APIs, and init.lua bails before this file can load
  -- on anything older -- so a sub-0.11 Neovim here means something bypassed
  -- init.lua and belongs in the error bucket, not a soft warning.
  if vim.fn.has("nvim-0.11") == 1 then
    vim.health.ok(string.format("Neovim version: %s (>= 0.11 required)", vim.version()))
  else
    vim.health.error(string.format("Neovim version: %s -- TetraVim requires Neovim >= 0.11", vim.version()))
  end

  if vim.opt.confirm:get() == true then
    vim.health.ok("Global exit confirmation (vim.opt.confirm = true) is active")
  else
    vim.health.warn("Global exit confirmation is disabled")
  end

  vim.health.start("TetraVim System Dependencies")

  local binaries = {
    { name = "rg", required = true, label = "ripgrep (fast project-wide search)" },
    { name = "git", required = true, label = "git (VCS integration)" },
    { name = "fd", required = false, label = "fd (file finder)" },
    { name = "make", required = false, label = "make (native build steps)" },
    { name = "node", required = false, label = "node (LSP servers, formatters)" },
  }
  for _, bin in ipairs(binaries) do
    if vim.fn.executable(bin.name) == 1 then
      vim.health.ok(string.format("%s: found on $PATH (%s)", bin.name, bin.label))
    elseif bin.required then
      vim.health.warn(string.format("%s: NOT found on $PATH -- %s", bin.name, bin.label))
    else
      vim.health.info(string.format("%s: NOT found on $PATH (optional -- %s)", bin.name, bin.label))
    end
  end

  vim.health.start("TetraVim Tree-sitter Engine")

  -- nvim-treesitter is pinned to the "main" branch (lazy-lock.json), which
  -- compiles every parser by shelling out to the `tree-sitter` CLI
  -- (`tree-sitter build`). A missing CLI fails parser install for *every*
  -- language with `ENOENT ... 'tree-sitter'`.
  if vim.fn.executable("tree-sitter") == 1 then
    vim.health.ok("tree-sitter CLI: found on $PATH (parser compilation available)")
  else
    vim.health.warn(
      "tree-sitter CLI: NOT found on $PATH -- parser install will fail. "
        .. "Install with `npm install -g tree-sitter-cli` or `:MasonInstall tree-sitter-cli`"
    )
  end

  for _, lang in ipairs({ "lua", "vim", "markdown", "query" }) do
    if pcall(vim.treesitter.get_string_parser, "", lang) then
      vim.health.ok(string.format("%s Tree-sitter parser: installed", lang))
    else
      vim.health.warn(string.format("%s Tree-sitter parser: NOT installed. Suggestion: :TSInstall %s", lang, lang))
    end
  end

  vim.health.start("Gradle Wrapper & Build Lock")

  local uv = vim.uv
  local cwd = vim.fn.getcwd()
  local is_gradle = uv.fs_stat(cwd .. "/build.gradle") ~= nil
    or uv.fs_stat(cwd .. "/build.gradle.kts") ~= nil
    or uv.fs_stat(cwd .. "/settings.gradle") ~= nil
    or uv.fs_stat(cwd .. "/settings.gradle.kts") ~= nil

  if not is_gradle then
    vim.health.info("Gradle project not detected in current directory")
  else
    if uv.fs_stat(cwd .. "/gradlew") then
      vim.health.ok("Gradle wrapper script (gradlew): present")
    else
      vim.health.warn("Gradle wrapper script (gradlew): missing -- run 'gradle wrapper' to add it")
    end

    if uv.fs_stat(cwd .. "/gradle/wrapper/gradle-wrapper.jar") then
      vim.health.ok("gradle-wrapper.jar: present")
    else
      vim.health.warn("gradle-wrapper.jar: missing under gradle/wrapper/")
    end

    local props = cwd .. "/gradle/wrapper/gradle-wrapper.properties"
    if uv.fs_stat(props) then
      local ok_read, lines = pcall(vim.fn.readfile, props)
      local content = ok_read and table.concat(lines, "\n") or ""
      local dist = content:match("distributionUrl=.-gradle%-([%d%.]+)%-")
      if dist then
        vim.health.ok(string.format("Gradle distribution pinned: %s", dist))
      else
        vim.health.info("gradle-wrapper.properties: present (distribution version not parsed)")
      end
      if content:match("distributionSha256Sum=") then
        vim.health.ok("SHA-256 checksum: configured (distributionSha256Sum)")
      else
        vim.health.warn("SHA-256 checksum: NOT configured -- add distributionSha256Sum for supply-chain safety")
      end
    else
      vim.health.warn("gradle-wrapper.properties: missing under gradle/wrapper/")
    end

    local locks = vim.fn.glob(cwd .. "/.gradle/*.lock", false, true)
    if locks and #locks > 0 then
      vim.health.warn(string.format("Stale Gradle build lock(s) present: %s", table.concat(locks, ", ")))
    else
      vim.health.ok("No stale Gradle build locks under .gradle/")
    end
  end
end

return M
