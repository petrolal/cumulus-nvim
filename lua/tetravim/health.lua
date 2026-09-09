-- TetraVim Healthcheck Module (Story 27.2, Story 35.1 & Story 6.1)

local M = {}

function M.check()
  vim.health.start("TetraVim Neovim Core & Platform")

  if vim.fn.has("nvim-0.10.0") == 1 then
    vim.health.ok(string.format("Neovim version: %s (>= 0.10.0 required)", vim.version()))
  else
    vim.health.warn(string.format("Neovim version: %s (v0.10.0+ recommended)", vim.version()))
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

  vim.health.start("Gradle Wrapper & Build Lock")

  local uv = vim.uv or vim.loop
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

  vim.health.start("TetraVim Project-Wide Safe Rename (SPEC-2.1)")

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

  vim.health.start("TetraVim Spring Boot Discovery (Story 2.3)")
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

  -- Quarkus + MicroProfile (Open VSX .vsix, fetched by scripts/fetch-jvm-lsp-jars.sh)
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
        .. "'bash scripts/fetch-jvm-lsp-jars.sh' to download the Red Hat vscode-quarkus / "
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

  vim.health.start("AWS CloudFormation & SAM DevOps Tooling (Story 8.2)")

  local cfn_tools = {
    {
      name = "aws",
      desc = "AWS CLI (required for 'aws cloudformation validate-template')",
      install = "Install via https://aws.amazon.com/cli/",
    },
    {
      name = "sam",
      desc = "AWS SAM CLI (required for 'sam build', 'sam local invoke', 'sam validate')",
      install = "Install via https://docs.aws.amazon.com/serverless-application-model/latest/developerguide/install-sam-cli.html",
    },
    {
      name = "cfn-lint",
      desc = "CloudFormation Linter (cfn-lint)",
      install = ":MasonInstall cfn-lint or pip install cfn-lint",
    },
    {
      name = "cfn-guard",
      desc = "CloudFormation Guard Policy Evaluator (cfn-guard)",
      install = "Install via brew install cloudformation-guard or cargo install cfn-guard",
    },
  }

  for _, tool in ipairs(cfn_tools) do
    if vim.fn.executable(tool.name) == 1 then
      vim.health.ok(string.format("%s: installed and executable", tool.name))
    else
      vim.health.info(string.format("%s: NOT found on $PATH (%s. Suggestion: %s)", tool.name, tool.desc, tool.install))
    end
  end

  vim.health.start("Ansible Automation Tooling (Story 8.3)")

  local ansible_tools = {
    {
      name = "ansible-playbook",
      desc = "Ansible Playbook CLI (required for '--syntax-check', '--check', execution)",
      install = "Install via pip install ansible or brew install ansible",
    },
    {
      name = "ansible-lint",
      desc = "Ansible Playbook Linter",
      install = ":MasonInstall ansible-lint or pip install ansible-lint",
    },
    {
      name = "ansible-inventory",
      desc = "Ansible Inventory CLI (required for '--graph')",
      install = "Included with ansible package (pip install ansible)",
    },
    {
      name = "ansible-vault",
      desc = "Ansible Vault CLI (encrypt/decrypt/view secrets)",
      install = "Included with ansible package (pip install ansible)",
    },
    {
      name = "ansible-doc",
      desc = "Ansible Module Documentation Browser",
      install = "Included with ansible package (pip install ansible)",
    },
  }

  for _, tool in ipairs(ansible_tools) do
    if vim.fn.executable(tool.name) == 1 then
      vim.health.ok(string.format("%s: installed and executable", tool.name))
    else
      vim.health.info(string.format("%s: NOT found on $PATH (%s. Suggestion: %s)", tool.name, tool.desc, tool.install))
    end
  end

  vim.health.start("TetraVim CI/CD YAML -- GitHub Actions & GitLab CI (Epic 39)")

  if pcall(require, "schemastore") then
    vim.health.ok("SchemaStore.nvim: resolvable (JSON Schema Store catalog feeds yamlls/jsonls)")
  else
    vim.health.warn(
      "SchemaStore.nvim: NOT resolvable -- run :Lazy sync (GitHub Workflow / GitLab CI schema validation unavailable)"
    )
  end

  local ci_tools = {
    {
      name = "yaml-language-server",
      desc = "YAML LSP -- schema validation, completion and hover for workflow & pipeline files",
      install = ":MasonInstall yaml-language-server",
    },
    {
      name = "gh-actions-language-server",
      desc = "GitHub Actions LSP -- 'uses:' resolution, expression and input checks",
      install = ":MasonInstall gh-actions-language-server",
    },
    {
      name = "actionlint",
      desc = "GitHub Actions workflow linter (shellcheck-backed 'run:' analysis)",
      install = ":MasonInstall actionlint",
    },
    {
      name = "yamllint",
      desc = "Generic YAML linter -- style checks for .gitlab-ci.yml",
      install = ":MasonInstall yamllint",
    },
  }

  for _, tool in ipairs(ci_tools) do
    if vim.fn.executable(tool.name) == 1 then
      vim.health.ok(string.format("%s: installed and executable", tool.name))
    else
      vim.health.info(string.format("%s: NOT found on $PATH (%s. Suggestion: %s)", tool.name, tool.desc, tool.install))
    end
  end

  if vim.fn.executable("glab") == 1 then
    vim.health.ok("glab: installed (optional -- 'glab ci lint' server-side pipeline validation)")
  else
    vim.health.info("glab: NOT found on $PATH (optional -- enables server-side 'glab ci lint' validation)")
  end

  vim.health.start("TetraVim Autocompletion / IntelliSense (nvim-cmp + LuaSnip)")

  local cmp_ok = pcall(require, "cmp")
  if cmp_ok then
    vim.health.ok("nvim-cmp: resolvable (open a buffer / enter insert mode to load it)")
  else
    vim.health.warn("nvim-cmp: not resolvable -- enter insert mode once to lazy-load it, or run :Lazy sync")
  end

  local cmp_lsp_ok = pcall(require, "cmp_nvim_lsp")
  if cmp_lsp_ok then
    vim.health.ok("cmp-nvim-lsp: resolvable -- extended completion capabilities advertised to every LSP server")
  else
    vim.health.warn("cmp-nvim-lsp: not resolvable -- LSP completion falls back to plain capabilities. Run :Lazy sync")
  end

  local luasnip_ok = pcall(require, "luasnip")
  if luasnip_ok then
    local ok_ls, ls = pcall(require, "luasnip")
    local ft_count = 0
    if ok_ls and type(ls.get_snippets) == "function" then
      local all = ls.get_snippets() or {}
      for _ in pairs(all) do
        ft_count = ft_count + 1
      end
    end
    if ft_count > 0 then
      vim.health.ok(string.format("LuaSnip: resolvable -- snippets loaded for %d filetype(s)", ft_count))
    else
      vim.health.ok("LuaSnip: resolvable (friendly-snippets load lazily per filetype)")
    end
  else
    vim.health.warn("LuaSnip: not resolvable -- snippet expansion unavailable. Run :Lazy sync")
  end

  for _, dep in ipairs({ "cmp_luasnip", "cmp_buffer", "cmp_path" }) do
    if not pcall(require, dep) then
      vim.health.info(dep:gsub("_", "-") .. ": not yet loaded (loads with nvim-cmp on InsertEnter)")
    end
  end

  vim.health.start("TetraVim Embedded Database Explorer (SPEC-3.1)")

  local dadbod_completion_ok = pcall(require, "vim_dadbod_completion")
  if dadbod_completion_ok then
    vim.health.ok("vim-dadbod-completion: resolvable (SQL buffer completion source available)")
  else
    vim.health.warn(
      "vim-dadbod-completion: not resolvable -- open a sql/mysql/plsql buffer to lazy-load it, or run :Lazy sync"
    )
  end

  -- vim.treesitter.language.add() does not throw when the parser is absent
  -- (it returns nil, nil), so pcall always reports success. Use get_string_parser
  -- which raises an error when the parser is not installed.
  local sql_parser_ok = pcall(vim.treesitter.get_string_parser, "", "sql")
  if sql_parser_ok then
    vim.health.ok("sql Tree-sitter parser: installed (SQL buffer syntax highlighting available)")
  else
    vim.health.info("sql Tree-sitter parser: NOT installed. Suggestion: :TSInstall sql")
  end

  vim.health.start("TetraVim HTTP Client & REST API Explorer (Story 3.2)")

  local http_tools = {
    {
      name = "jq",
      desc = "jq JSON processor (required for the <leader>ahj response-filtering keymap)",
      install = "Install via apt install jq / brew install jq / pacman -S jq",
    },
    {
      name = "curl",
      desc = "curl (kulala.nvim's request backend -- required for <leader>ahr to execute .http requests)",
      install = "Install via apt install curl / brew install curl",
    },
  }

  for _, tool in ipairs(http_tools) do
    if vim.fn.executable(tool.name) == 1 then
      vim.health.ok(string.format("%s: installed and executable", tool.name))
    else
      vim.health.info(string.format("%s: NOT found on $PATH (%s. Suggestion: %s)", tool.name, tool.desc, tool.install))
    end
  end

  local kulala_ok = pcall(require, "kulala")
  if kulala_ok then
    vim.health.ok("kulala.nvim: resolvable (.http execution engine available)")
  else
    vim.health.warn("kulala.nvim: not resolvable -- open a .http file to lazy-load it, or run :Lazy sync")
  end

  vim.health.start("TetraVim gRPC & Protobufs (Story 3.4)")

  local grpc_tools = {
    {
      name = "grpcurl",
      desc = "grpcurl (required for the <leader>ag list/describe/invoke keymaps)",
      install = "Install via :MasonInstall grpcurl / brew install grpcurl / "
        .. "go install github.com/fullstorydev/grpcurl/cmd/grpcurl@latest",
    },
    {
      name = "buf",
      desc = "buf (the `proto` conform formatter -- <leader>agf / format-on-save)",
      install = "Install via :MasonInstall buf / brew install bufbuild/buf/buf",
    },
    {
      name = "protols",
      desc = "protols (Protocol Buffers language server -- .proto hover / go-to-definition)",
      install = "Install via :MasonInstall protols / cargo install protols",
    },
  }

  for _, tool in ipairs(grpc_tools) do
    if vim.fn.executable(tool.name) == 1 then
      vim.health.ok(string.format("%s: installed and executable", tool.name))
    else
      vim.health.info(string.format("%s: NOT found on $PATH (%s. Suggestion: %s)", tool.name, tool.desc, tool.install))
    end
  end

  -- vim.treesitter.language.add() does not raise when the parser is absent,
  -- so probe with get_string_parser which does (see the SQL section above).
  local proto_parser_ok = pcall(vim.treesitter.get_string_parser, "", "proto")
  if proto_parser_ok then
    vim.health.ok("proto Tree-sitter parser: installed (.proto syntax highlighting available)")
  else
    vim.health.warn("proto Tree-sitter parser: NOT installed. Suggestion: :TSInstall proto")
  end

  vim.health.start("TetraVim Advanced Git Conflict Resolution (Story 4.1)")

  if vim.fn.executable("git") == 1 then
    local git_ok, git_res = pcall(function()
      return vim.system({ "git", "--version" }, { text = true, timeout = 2000 }):wait()
    end)

    local stdout
    if git_ok and type(git_res) == "table" and git_res.code == 0 then
      stdout = git_res.stdout or ""
    end
    local major, minor = (stdout or ""):match("(%d+)%.(%d+)")
    major, minor = tonumber(major), tonumber(minor)

    if not major then
      vim.health.warn(
        "git: installed, but `git --version` did not return a recognizable version -- ensure it is git >= 2.30"
      )
    elseif major > 2 or (major == 2 and minor >= 30) then
      vim.health.ok(string.format("git: installed (v%d.%d; >= 2.30 advised)", major, minor))
    else
      vim.health.warn(
        string.format("git: v%d.%d found -- git >= 2.30 is advised for the merge-conflict workflow", major, minor)
      )
    end
  else
    vim.health.error(
      "git: NOT found on $PATH -- the <leader>gc conflict/compare commands are unavailable. Suggestion: install git"
    )
  end

  -- Distinguish "diffview.nvim is not installed at all" (an error the user
  -- fixes with :Lazy install) from "installed but not yet lazy-loaded" (a
  -- benign warn -- pressing <leader>gco loads it).
  local lz_ok, lz_cfg = pcall(require, "lazy.core.config")
  local diffview_plugin = lz_ok and lz_cfg.plugins and lz_cfg.plugins["diffview.nvim"] or nil
  if not diffview_plugin then
    vim.health.error(
      "diffview.nvim: not installed -- run :Lazy install (spec lives in lua/tetravim/plugins/tools-diffview.lua)"
    )
  elseif not package.loaded["diffview"] then
    vim.health.warn(
      "diffview.nvim: installed but not yet lazy-loaded -- press <leader>gco / run :DiffviewOpen to load it"
    )
  else
    vim.health.ok("diffview.nvim: loaded (3-way merge tool & file-history engine available)")
  end

  -- diffview.nvim's hard dependency -- without it diffview cannot load at all.
  if pcall(require, "plenary") then
    vim.health.ok("plenary.nvim: resolvable (diffview.nvim's hard dependency)")
  else
    vim.health.warn("plenary.nvim: not resolvable -- diffview's hard dependency; run :Lazy sync")
  end

  vim.health.start("TetraVim Code Reviews (GitHub/GitLab) (Story 4.2)")
  if vim.fn.executable("gh") == 1 then
    vim.health.ok("gh: installed and executable (GitHub PR review support available)")
  else
    vim.health.info("gh: NOT found on $PATH (GitHub PR review support unavailable). Suggestion: install gh")
  end
  if vim.fn.executable("glab") == 1 then
    vim.health.ok("glab: installed and executable (GitLab PR review support available)")
  else
    vim.health.info("glab: NOT found on $PATH (GitLab PR review support unavailable). Suggestion: install glab")
  end

  vim.health.start("TetraVim Visual Test Runner -- neotest-java (SPEC-1.3)")

  if pcall(require, "neotest-java") then
    vim.health.ok("neotest-java: resolvable (JVM test tree discovery available)")
  else
    vim.health.info("neotest-java: not resolvable -- open a java buffer to lazy-load it, or run :Lazy sync")
  end

  local njava_ok, njava = pcall(require, "tetravim.util.neotest_java")
  if njava_ok then
    if njava.is_installed() then
      vim.health.ok(
        string.format("JUnit Platform Console Standalone %s: present (%s)", njava.version, njava.jar_path())
      )
    elseif vim.fn.executable("curl") == 1 then
      vim.health.info(
        "JUnit Platform Console Standalone jar: not downloaded yet -- fetched automatically on first test run "
          .. "(or run :NeotestJava setup)"
      )
    else
      vim.health.warn(
        "JUnit Platform Console Standalone jar: missing and curl is unavailable -- install curl or download it manually"
      )
    end
  else
    vim.health.error("tetravim.util.neotest_java: failed to load (" .. tostring(njava) .. ")")
  end

  if njava_ok then
    if njava.has_java_sources(vim.fn.getcwd()) then
      vim.health.ok("Current project: has .java sources -- neotest-java adapter is active here")
    else
      vim.health.info(
        "Current project: no .java sources found -- neotest-java stays inactive here (it is Java-only; "
          .. "use the Gradle/Maven test tasks for Kotlin/Scala)"
      )
    end
  end

  vim.health.start("TetraVim JVM & Diagnostic Linting -- nvim-lint (Story 3.x)")

  if pcall(require, "lint") then
    vim.health.ok("nvim-lint: loaded (auto-lint on BufWritePost/BufEnter; toggle with <leader>ul / <leader>uL)")
  else
    vim.health.info("nvim-lint: not loaded yet -- open a lintable buffer to lazy-load it, or run :Lazy sync")
  end

  for _, l in ipairs({
    { bin = "checkstyle", ft = "Java", install = ":MasonInstall checkstyle" },
    { bin = "ktlint", ft = "Kotlin", install = ":MasonInstall ktlint" },
    { bin = "npm-groovy-lint", ft = "Groovy", install = ":MasonInstall npm-groovy-lint or npm i -g npm-groovy-lint" },
  }) do
    if vim.fn.executable(l.bin) == 1 then
      vim.health.ok(("%s: installed and executable (%s linting on save)"):format(l.bin, l.ft))
    else
      vim.health.info(("%s: NOT found on $PATH (%s linting disabled). Suggestion: %s"):format(l.bin, l.ft, l.install))
    end
  end

  -- Scala: Metals already provides semantic diagnostics; scalastyle is the
  -- optional style linter (not in Mason -- install via coursier) and needs a
  -- rules file, scalafmt is the formatter used by conform + <leader>xlF.
  local tvlint_ok, tvlint = pcall(require, "tetravim.util.lint")
  if vim.fn.executable("scalastyle") == 1 then
    local cfg = tvlint_ok and tvlint.scalastyle_config() or nil
    if cfg then
      vim.health.ok("scalastyle: installed + config found (" .. vim.fn.fnamemodify(cfg, ":~:.") .. ")")
    else
      vim.health.info(
        "scalastyle: installed but no scalastyle-config.xml up-tree -- add one to enable Scala style linting"
      )
    end
  else
    vim.health.info(
      "scalastyle: NOT found on $PATH (optional Scala style linter). Suggestion: coursier install scalastyle"
    )
  end
  if vim.fn.executable("scalafmt") == 1 then
    vim.health.ok("scalafmt: installed and executable (Scala formatting via conform + <leader>xlF)")
  else
    vim.health.info(
      "scalafmt: NOT found on $PATH (Scala falls back to Metals LSP formatting). Suggestion: coursier install scalafmt"
    )
  end

  -- Buffer autofix <leader>xlf / project-wide <leader>xlp (check) / <leader>xlF (fix)
  if tvlint_ok and type(tvlint.project_plan) == "function" then
    local can_check = #tvlint.project_plan("check")
    local can_fix = #tvlint.project_plan("fix")
    vim.health.ok(
      ("Project lint: <leader>xlp can run %d checker(s), <leader>xlF can run %d fixer(s) in this repo"):format(
        can_check,
        can_fix
      )
    )
    if type(tvlint.buffer_fix_argv) == "table" then
      local fts = vim.tbl_keys(tvlint.buffer_fix_argv)
      table.sort(fts)
      vim.health.ok(
        ("Buffer autofix: <leader>xlf rewrites the current file for filetype(s) %s"):format(table.concat(fts, ", "))
      )
    end
  end

  vim.health.start("TetraVim Code Quality & Security -- SonarLint (Story 6.1)")

  local sonar = require("tetravim.util.sonar")
  if sonar.has_language_server() then
    vim.health.ok("sonarlint-language-server: installed and executable (Java/Kotlin/Scala SonarQube-rule diagnostics)")
    local jars = sonar.analyzer_paths()
    if #jars > 0 then
      vim.health.ok(string.format("SonarLint analyzers: %d bundled jar(s) found under the Mason package", #jars))
    else
      vim.health.info(
        "SonarLint analyzers: none bundled with the Mason package -- standalone analysis relies on connected mode "
          .. "or the language server's own defaults"
      )
    end
  else
    vim.health.info(
      "sonarlint-language-server: NOT found on $PATH (SonarQube-rule diagnostics unavailable). "
        .. "Suggestion: :MasonInstall sonarlint-language-server"
    )
  end

  if pcall(require, "sonarlint") then
    vim.health.ok("sonarlint.nvim: resolvable (SonarLint LS bridge available)")
  else
    vim.health.info(
      "sonarlint.nvim: not resolvable -- open a java/kotlin/scala buffer to lazy-load it, or run :Lazy sync"
    )
  end

  local sonar_props = sonar.find_project_settings()
  if sonar_props and sonar_props["sonar.projectKey"] then
    vim.health.ok(
      "sonar-project.properties: found (quality profile bound to '" .. sonar_props["sonar.projectKey"] .. "')"
    )
  else
    vim.health.info("sonar-project.properties: not found in the current directory (SonarLint default rules apply)")
  end

  -- Whole-codebase analysis (<leader>xsp / :TetraVimSonarScan).
  local backend = sonar.choose_backend(sonar_props, sonar.has_scanner())
  if sonar.has_scanner() then
    vim.health.ok("sonar-scanner: installed and executable (connected-mode project scan available)")
  else
    vim.health.info(
      "sonar-scanner: NOT found on $PATH -- <leader>xsp falls back to a server-free SonarLint sweep. "
        .. "Suggestion: npm install -g sonarqube-scanner, or a release from "
        .. "https://docs.sonarsource.com/sonarqube-server/analyzing-source-code/scanners/sonarscanner/"
    )
  end
  local n_sources = #sonar.collect_sources()
  vim.health.ok(
    ("Project scan: <leader>xsp will use the '%s' backend here (%d Java/Kotlin/Scala source(s) in this repo)"):format(
      backend,
      n_sources
    )
  )

  vim.health.info("Scala SonarLint rules require SonarQube connected mode -- no standalone Scala analyzer is bundled")

  vim.health.start("TetraVim Code Quality & Security -- CVE Scanning (Story 6.2)")

  if vim.fn.executable("osv-scanner") == 1 then
    vim.health.ok(
      "osv-scanner: installed and executable (<leader>xvb build-file + <leader>xvp whole-project CVE scan available)"
    )
  else
    vim.health.info(
      "osv-scanner: NOT found on $PATH (the <leader>xvb / <leader>xvp dependency CVE scans are unavailable). "
        .. "Suggestion: brew install osv-scanner / go install github.com/google/osv-scanner/cmd/osv-scanner@latest"
    )
  end

  vim.health.start("TetraVim Asynchronous LSP & Resilience (Story 5.1)")

  local resilience_ok, resilience = pcall(require, "tetravim.util.lsp_resilience")
  if resilience_ok and type(resilience.health) == "function" then
    resilience.health()
  else
    vim.health.error("tetravim.util.lsp_resilience: failed to load (" .. tostring(resilience) .. ")")
  end

  vim.health.start("TetraVim Headless Setup & Telemetry (Story 5.2)")

  local setup_script = vim.fn.stdpath("config") .. "/scripts/headless-setup.sh"
  if vim.fn.executable(setup_script) == 1 then
    vim.health.ok("scripts/headless-setup.sh: present and executable (non-interactive provisioning)")
  else
    vim.health.warn("scripts/headless-setup.sh: missing or not executable")
  end

  local json_ok, core_health = pcall(require, "tetravim.core.health")
  if json_ok and type(core_health.json) == "function" then
    local decoded_ok = pcall(function()
      return vim.json.decode(core_health.json())
    end)
    if decoded_ok then
      vim.health.ok(
        ":CheckHealthJson emits valid machine-readable JSON (neovim_version, lsp_clients, plugin_count, ...)"
      )
    else
      vim.health.error("tetravim.core.health.json() did not return decodable JSON")
    end
  else
    vim.health.error("tetravim.core.health: failed to load or missing json()")
  end

  if vim.g.tetravim_telemetry_enabled then
    vim.health.info(
      "Telemetry is ENABLED -- notifications are appended to "
        .. vim.fn.stdpath("config")
        .. "/telemetry.log (toggle with :TetraVimTelemetryDisable)"
    )
  else
    vim.health.info("Telemetry is disabled (opt in with :TetraVimTelemetryEnable to export notifications as JSON)")
  end

  vim.health.start("TetraVim Colour Scheme")

  local theme_ok, tetris = pcall(require, "tetravim.theme.tetris")
  if not theme_ok then
    vim.health.error("tetravim.theme.tetris: failed to load (" .. tostring(tetris) .. ")")
  else
    local pal = tetris.palette or {}
    if pal.bg == "#111216" and pal.cyan == "#00F0F0" and pal.purple == "#A000F0" then
      vim.health.ok("Tetris palette module loaded (canonical hex values present)")
    else
      vim.health.warn("Tetris palette module loaded but hex values are not the canonical TetraVim set")
    end

    if vim.g.colors_name == "tetravim" then
      vim.health.ok("Active colourscheme: 'tetravim'")
    else
      vim.health.warn(
        "colors_name is '"
          .. tostring(vim.g.colors_name)
          .. "' (expected 'tetravim') -- run ':colorscheme tetravim' or check core/options.lua"
      )
    end
  end

  vim.health.start("TetraVim Project Generator Wizard")

  if vim.fn.executable("curl") == 1 then
    vim.health.ok("curl: installed and executable (Spring Initializr download)")
  else
    vim.health.warn("curl: NOT found on $PATH (required for Spring Initializr project generator)")
  end

  if vim.fn.executable("unzip") == 1 then
    vim.health.ok("unzip: installed and executable (Spring Initializr project unpack)")
  else
    vim.health.warn("unzip: NOT found on $PATH (required for Spring Initializr project generator)")
  end

  if vim.fn.executable("mvn") == 1 then
    vim.health.ok("mvn: installed and executable (Maven project scaffolding & build)")
  else
    vim.health.info("mvn: NOT found on $PATH (optional -- needed for Maven Archetype generator)")
  end

  if vim.fn.executable("gradle") == 1 then
    vim.health.ok("gradle: installed and executable (Gradle init project scaffolding)")
  else
    vim.health.info("gradle: NOT found on $PATH (optional -- needed for Gradle init generator)")
  end

  vim.health.start("TetraVim New File from Template (IDEA-style New)")

  do
    local ok, ft = pcall(require, "tetravim.util.filetemplate")
    if not ok then
      vim.health.error("tetravim.util.filetemplate: failed to load (" .. tostring(ft) .. ")")
    else
      vim.health.ok(
        ("built-in templates: %d registered (Java / Kotlin / Scala / Groovy / Web / DevOps / ...)"):format(
          ft.builtin_count()
        )
      )
      local udir = ft.user_dir()
      if vim.fn.isdirectory(udir) == 1 then
        local n = vim.tbl_count(ft.load_user_templates())
        vim.health.ok(("user templates: %d found in %s"):format(n, udir))
      else
        vim.health.info(
          "user templates: none -- drop files into " .. udir .. " to add your own (one file per template)"
        )
      end
      vim.health.info("keys: <leader>fn / <leader>n / :TetraVimNewFile")
      if vim.g.tetravim_new_file_prompt == false then
        vim.health.info("new-file skeleton prompt: disabled (vim.g.tetravim_new_file_prompt = false)")
      else
        vim.health.ok("new-file skeleton prompt: on -- opening a new empty file of a known type offers a template")
      end
    end
  end

  vim.health.start("TetraVim IDE-Parity Language Servers (Python / SQL / Web / Templates)")

  -- Executable names as exposed on $PATH once Mason installs each package
  -- (mason.nvim prepends ~/.local/share/nvim/mason/bin). mason-tool-installer
  -- fetches all of these on VimEnter, so a miss here is normal on a cold
  -- checkout -- hence info, not warn. See docs/ide-parity.md for the full map.
  local parity_servers = {
    { bin = "basedpyright-langserver", desc = "Python type checker LSP (IDEA 'Python')" },
    { bin = "ruff", desc = "Python lint + format LSP (IDEA 'Python')" },
    { bin = "sql-language-server", desc = "SQL language server (IDEA Database tools)" },
    { bin = "vue-language-server", desc = "Vue / Volar LSP (IDEA 'Vue.js')" },
    { bin = "svelteserver", desc = "Svelte LSP (IDEA 'Svelte')" },
    { bin = "astro-ls", desc = "Astro LSP (IDEA 'Astro')" },
    { bin = "ngserver", desc = "Angular LSP (IDEA 'Angular')" },
    { bin = "prisma-language-server", desc = "Prisma ORM LSP (IDEA 'Prisma ORM')" },
    { bin = "marksman", desc = "Markdown LSP -- links / headings (IDEA 'Markdown')" },
    { bin = "vscode-eslint-language-server", desc = "ESLint LSP -- diagnostics + fix-all" },
    { bin = "tailwindcss-language-server", desc = "Tailwind CSS LSP -- class completion" },
    { bin = "emmet-language-server", desc = "Emmet LSP -- abbreviation expansion" },
    { bin = "djlint", desc = "Jinja2 / Django template format + lint" },
    { bin = "ltex-ls", desc = "Natural-language grammar / style LSP (IDEA 'Grazie')" },
    { bin = "deno", desc = "Deno LSP (runtime-provided; not a Mason package)" },
  }
  for _, s in ipairs(parity_servers) do
    if vim.fn.executable(s.bin) == 1 then
      vim.health.ok(string.format("%s: installed and executable (%s)", s.bin, s.desc))
    else
      vim.health.info(string.format("%s: NOT found on $PATH (%s). Suggestion: :MasonToolsInstall", s.bin, s.desc))
    end
  end

  vim.health.start("TetraVim IDE-Parity Editor Tools (Run / TODO / Structure / History)")

  -- Pure-Lua/Vimscript plugins fetched by lazy.nvim -- no external binary, so
  -- the probe is just "did the module load". A miss means `:Lazy sync` has
  -- not run yet. See docs/ide-parity.md ("Editor / IDE tool windows").
  local editor_plugins = {
    { mod = "overseer", desc = "Generic task runner (IDEA 'Run Anything' / Run Configurations) -- <leader>r" },
    { mod = "todo-comments", desc = "TODO / FIXME scanner + list (IDEA 'TODO' tool window) -- ]t / <leader>xt" },
    { mod = "outline", desc = "Docked symbol tree (IDEA 'Structure') -- <leader>cs" },
    { mod = "grug-far", desc = "Project-wide find & replace (IDEA 'Replace in Path') -- <leader>sr" },
    { mod = "marks", desc = "Gutter marks + bookmarks (IDEA 'Bookmarks') -- m* / <leader>m" },
    { mod = "package-info", desc = "package.json version lens (IDEA npm inlays) -- <leader>cn* in package.json" },
    {
      mod = "neogen",
      desc = "Javadoc / KDoc / docstring stub generator (IDEA 'Generate... > Javadoc') -- <leader>cg / <leader>cG",
    },
  }
  for _, p in ipairs(editor_plugins) do
    if pcall(require, p.mod) then
      vim.health.ok(string.format("%s: loaded (%s)", p.mod, p.desc))
    else
      vim.health.info(string.format("%s: not loaded (%s). Suggestion: :Lazy sync", p.mod, p.desc))
    end
  end

  -- undotree is Vimscript-only (no Lua module); probe the command it defines.
  if vim.fn.exists(":UndotreeToggle") == 2 then
    vim.health.ok("undotree: available (persistent undo timeline / IDEA 'Local History') -- <leader>uu")
  else
    vim.health.info("undotree: not loaded (IDEA 'Local History'). Suggestion: :Lazy sync")
  end

  -- jdtls decompiler bundle -- IDEA bundled decompiler parity. Ships as jars
  -- under the dgileadi/vscode-java-decompiler lazy plugin; ftplugin/java.lua
  -- globs them into the jdtls bundle list.
  local decompiler_root = vim.fn.stdpath("data") .. "/lazy/vscode-java-decompiler/server"
  local decompiler_jars = vim.fn.isdirectory(decompiler_root) == 1
      and vim.fn.glob(decompiler_root .. "/*.jar", true, true)
    or {}
  if type(decompiler_jars) == "table" and #decompiler_jars > 0 then
    vim.health.ok(
      string.format(
        "vscode-java-decompiler: %d bundle jar(s) -> jdtls (decompile source-less .class)",
        #decompiler_jars
      )
    )
  else
    vim.health.info("vscode-java-decompiler: no bundle jars found. Suggestion: :Lazy sync")
  end

  -- Keymap hygiene. TetraVim feeds which-key from four registration channels
  -- (core/keymaps, core/lang-keymaps, core/devops, util/jvm) plus plugin
  -- `keys=` specs. Nothing stops two of them claiming the same <leader>
  -- sequence, and Neovim silently keeps only the last binding -- so a drift
  -- like that is invisible until you press the key and get the wrong action.
  -- Flag the one shape that IS observable at runtime: a lhs that is both a
  -- complete mapping and a strict prefix of another mapping (e.g. a bare
  -- <leader>G that is also the <leader>G* group prefix). That stalls for
  -- 'timeoutlen' on every press and confuses which-key's group rendering.
  vim.health.start("TetraVim Keymap Hygiene (leader-prefix collisions)")
  local leader = vim.g.mapleader
  if type(leader) ~= "string" or leader == "" then
    leader = "\\"
  end
  local shadow_lines = {}
  for _, mode in ipairs({ "n", "x", "o" }) do
    local leader_lhs = {}
    for _, m in ipairs(vim.api.nvim_get_keymap(mode)) do
      local lhs = m.lhs or ""
      if lhs:sub(1, #leader) == leader and #lhs > #leader then
        leader_lhs[#leader_lhs + 1] = { lhs = lhs, desc = m.desc or m.rhs or "" }
      end
    end
    local reported = {}
    for _, a in ipairs(leader_lhs) do
      if not reported[a.lhs] then
        for _, b in ipairs(leader_lhs) do
          if a.lhs ~= b.lhs and b.lhs:sub(1, #a.lhs) == a.lhs then
            reported[a.lhs] = true
            shadow_lines[#shadow_lines + 1] = string.format(
              "[%s] %s is a full mapping (%s) and also the prefix of %s",
              mode,
              vim.fn.keytrans(a.lhs),
              a.desc ~= "" and a.desc or "no desc",
              vim.fn.keytrans(b.lhs)
            )
            break
          end
        end
      end
    end
  end
  if #shadow_lines == 0 then
    vim.health.ok("No <leader> mapping is also a prefix of another mapping")
  else
    for _, line in ipairs(shadow_lines) do
      vim.health.warn(line .. " -- pressing it stalls for 'timeoutlen'; move the action to a leaf key")
    end
  end
end

return M
