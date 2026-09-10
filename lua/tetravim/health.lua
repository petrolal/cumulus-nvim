-- TetraVim Healthcheck Module (Story 27.2, Story 35.1 & Story 6.1)

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

  vim.health.start("AWS CloudFormation & SAM DevOps Tooling")

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

  vim.health.start("Ansible Automation Tooling")

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

  vim.health.start("TetraVim CI/CD YAML -- GitHub Actions & GitLab CI")

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

  vim.health.start("TetraVim Embedded Database Explorer")

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

  vim.health.start("TetraVim HTTP Client & REST API Explorer")

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

  vim.health.start("TetraVim gRPC & Protobufs")

  local grpc_tools = {
    {
      name = "grpcurl",
      desc = "grpcurl (required for the <leader>ag list/describe/invoke keymaps)",
      -- Not in mason-registry (removed upstream) -- install it out of band.
      install = "Install via brew install grpcurl / your distro's package / "
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

  vim.health.start("TetraVim Endpoints Panel (Spring / OpenAPI)")

  -- <leader>ae -- tetravim.util.endpoints merges Spring MVC mappings with JSON
  -- OpenAPI specs into a docked panel. It needs a scanner for the ripgrep
  -- fallback and, ideally, an attached Spring Boot LS for compiler-accurate
  -- mappings; neither is strictly required (an OpenAPI spec alone still fills
  -- the panel), so absence is informational, not a failure.
  if vim.fn.executable("rg") == 1 then
    vim.health.ok("rg: installed (fast Spring controller scan for the Endpoints panel)")
  elseif vim.fn.executable("grep") == 1 then
    vim.health.info("rg: NOT found -- falling back to grep for the Spring controller scan (slower)")
  else
    vim.health.warn(
      "neither rg nor grep on $PATH -- the Spring scan for <leader>ae cannot run (OpenAPI specs still work)"
    )
  end

  local endpoints_ok, endpoints = pcall(require, "tetravim.util.endpoints_panel")
  if endpoints_ok and type(endpoints.open) == "function" then
    vim.health.ok("tetravim.util.endpoints_panel: loaded (<leader>ae opens the Endpoints panel)")
  else
    vim.health.warn("tetravim.util.endpoints_panel: not resolvable -- <leader>ae will error")
  end

  local spring_ls_ok = false
  local spring_lsp_ok, spring_lsp = pcall(require, "tetravim.util.spring_lsp")
  if spring_lsp_ok then
    local avail_ok, avail = pcall(spring_lsp.available)
    spring_ls_ok = avail_ok and avail == true
  end
  if spring_ls_ok then
    vim.health.ok("Spring Boot LS: attached -- endpoint list uses the workspace/symbol model")
  else
    vim.health.info(
      "Spring Boot LS: not attached -- endpoint list uses the ripgrep + Tree-sitter scan "
        .. "(open a Spring project's Java file to attach vscode-spring-boot-tools)"
    )
  end

  vim.health.start("TetraVim Kubernetes Cluster Explorer")

  -- <leader>oke -- tetravim.util.k8s renders a `kubectl`-driven resource tree
  -- (Deployments / Pods / Services for the active context + namespace) in the
  -- shared split. `kubectl` is required; a reachable cluster is nice-to-have.
  if vim.fn.executable("kubectl") == 1 then
    vim.health.ok("kubectl: installed (<leader>oke opens the cluster explorer)")
    local ctx_ok, ctx_res = pcall(function()
      return vim.system({ "kubectl", "config", "current-context" }, { text = true, timeout = 3000 }):wait()
    end)
    if ctx_ok and type(ctx_res) == "table" and ctx_res.code == 0 and (ctx_res.stdout or ""):match("%S") then
      vim.health.ok("kube-context: " .. (ctx_res.stdout or ""):gsub("%s+$", ""))
    else
      vim.health.info("kube-context: none selected (`kubectl config use-context <name>` to pick one)")
    end
  else
    vim.health.warn("kubectl: NOT found on $PATH -- <leader>oke (Kubernetes cluster explorer) is unavailable")
  end

  local k8s_ok, k8s_mod = pcall(require, "tetravim.util.k8s")
  if k8s_ok and type(k8s_mod.open) == "function" then
    vim.health.ok("tetravim.util.k8s: loaded")
  else
    vim.health.warn("tetravim.util.k8s: not resolvable -- <leader>oke will error")
  end

  vim.health.start("TetraVim Docker Runtime Dashboard")

  -- <leader>odd -- tetravim.util.docker lists containers + images for the local
  -- daemon in the shared split. `docker` is required; a running daemon is
  -- needed for the panel to show anything.
  if vim.fn.executable("docker") == 1 then
    vim.health.ok("docker: installed (<leader>odd opens the runtime dashboard)")
    local info_ok, info_res = pcall(function()
      return vim.system({ "docker", "info", "--format", "{{.ServerVersion}}" }, { text = true, timeout = 3000 }):wait()
    end)
    if info_ok and type(info_res) == "table" and info_res.code == 0 and (info_res.stdout or ""):match("%S") then
      vim.health.ok("docker daemon: reachable (server " .. (info_res.stdout or ""):gsub("%s+$", "") .. ")")
    else
      vim.health.info("docker daemon: not reachable -- start Docker for the dashboard to populate")
    end
  else
    vim.health.warn("docker: NOT found on $PATH -- <leader>odd (Docker runtime dashboard) is unavailable")
  end

  local docker_ok, docker_mod = pcall(require, "tetravim.util.docker")
  if docker_ok and type(docker_mod.open) == "function" then
    vim.health.ok("tetravim.util.docker: loaded")
  else
    vim.health.warn("tetravim.util.docker: not resolvable -- <leader>odd will error")
  end

  vim.health.start("TetraVim Advanced Git Conflict Resolution")

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

  vim.health.start("TetraVim Code Reviews (GitHub/GitLab)")
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

  vim.health.start("TetraVim Visual Test Runner -- neotest-java")

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
          .. "Kotlin/Groovy route through tetravim.util.jvm_test, Scala through neotest-scala)"
      )
    end
  end

  if pcall(require, "neotest-scala") then
    vim.health.ok("neotest-scala: resolvable (Scala test tree discovery available)")
  else
    vim.health.info("neotest-scala: not resolvable -- open a scala buffer to lazy-load it, or run :Lazy sync")
  end

  -- Kotlin / Groovy have no neotest adapter here; tetravim.util.jvm_test runs
  -- their tests straight through the build wrapper and parses the JUnit XML.
  local jvmtest_ok = pcall(require, "tetravim.util.jvm_test")
  if jvmtest_ok then
    local cwd = vim.fn.getcwd()
    local has_gradle = vim.fn.executable("gradle") == 1 or vim.fn.filereadable(cwd .. "/gradlew") == 1
    local has_maven = vim.fn.executable("mvn") == 1 or vim.fn.filereadable(cwd .. "/mvnw") == 1
    if has_gradle or has_maven then
      vim.health.ok("tetravim.util.jvm_test: build wrapper reachable (Kotlin/Groovy test running available)")
    else
      vim.health.info(
        "tetravim.util.jvm_test: loaded, but no gradle/mvn on $PATH and no wrapper in cwd -- "
          .. "Kotlin/Groovy test running needs one"
      )
    end
  else
    vim.health.error("tetravim.util.jvm_test: failed to load")
  end

  vim.health.start("TetraVim JVM & Diagnostic Linting -- nvim-lint")

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

  vim.health.start("TetraVim Code Quality & Security -- SonarLint")

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

  vim.health.start("TetraVim Code Quality & Security -- CVE Scanning")

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

  vim.health.start("TetraVim JVM Continuous Profiling -- async-profiler")

  local profiler_ok, profiling = pcall(require, "tetravim.util.profiling")
  local profiler_found = profiler_ok and profiling.profiler_cmd()
  if profiler_found then
    vim.health.ok(
      ("%s: installed and executable (<leader>jps start / <leader>jpx stop / <leader>jpv view available)"):format(
        profiler_found
      )
    )
  else
    vim.health.info(
      "async-profiler: NOT found on $PATH (looked for 'asprof', 'profiler.sh', 'async-profiler'). "
        .. "The <leader>jp profiling keymaps error until it is installed. "
        .. "Suggestion: run `bash bootstrap.sh`, or grab a release from "
        .. "https://github.com/async-profiler/async-profiler/releases"
    )
  end

  if vim.fn.has("mac") == 0 and vim.fn.filereadable("/proc/sys/kernel/perf_event_paranoid") == 1 then
    local paranoid = tonumber((vim.fn.readfile("/proc/sys/kernel/perf_event_paranoid")[1] or ""):match("%-?%d+"))
    if paranoid and paranoid <= 1 then
      vim.health.ok(("kernel.perf_event_paranoid=%d (async-profiler can sample a running JVM)"):format(paranoid))
    elseif paranoid then
      vim.health.warn(
        ("kernel.perf_event_paranoid=%d -- async-profiler needs <= 1 to sample the JVM. "):format(paranoid)
          .. "Run: sudo sysctl kernel.perf_event_paranoid=1 kernel.kptr_restrict=0"
      )
    end
  end

  vim.health.start("TetraVim Asynchronous LSP & Resilience")

  local resilience_ok, resilience = pcall(require, "tetravim.util.lsp_resilience")
  if resilience_ok and type(resilience.health) == "function" then
    resilience.health()
  else
    vim.health.error("tetravim.util.lsp_resilience: failed to load (" .. tostring(resilience) .. ")")
  end

  -- JetBrains kotlin-lsp shares a single on-disk RocksDB workspace index and
  -- fails every request when a second intellij-server races it for the lock --
  -- lsp-kotlin.lua refuses to start a second instance (TETRAVIM_KOTLIN_LSP_FORCE
  -- overrides). Surface which state we're in.
  if
    vim.fn.executable("intellij-server") == 1
    or vim.fn.filereadable(vim.fn.stdpath("data") .. "/mason/bin/intellij-server") == 1
  then
    local another = vim.fn.executable("pgrep") == 1
      and (function()
        vim.fn.system({ "pgrep", "-f", "intellij-server" })
        return vim.v.shell_error == 0
      end)()
    if vim.env.TETRAVIM_KOTLIN_LSP_FORCE == "1" then
      vim.health.warn(
        "Kotlin LSP: TETRAVIM_KOTLIN_LSP_FORCE=1 -- lock-contention guard disabled (concurrent index locks may crash the server)"
      )
    elseif another then
      vim.health.warn(
        "Kotlin LSP: an intellij-server is already running -- a second one is suppressed to avoid a workspace-index lock crash (:LspStart kotlin_lsp after the other session exits)"
      )
    else
      vim.health.ok("Kotlin LSP: intellij-server present, no competing instance -- workspace index is free")
    end
  end

  vim.health.start("TetraVim Headless Setup & Telemetry")

  local setup_ok, setup_mod = pcall(require, "tetravim.core.setup")
  if setup_ok and type(setup_mod.run) == "function" then
    vim.health.ok("tetravim.core.setup: native provisioning pipeline available (:TetraVimSetup)")
  else
    vim.health.warn("tetravim.core.setup: failed to load")
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
    -- The canonical palette uses tinted (readable) versions for code text.
    -- Pure spec hexes live in cyan_pure / purple_pure (chrome / ANSI accents).
    if pal.bg == "#111216" and pal.cyan == "#4EC9D9" and pal.purple == "#C792EA" then
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
    { mod = "package-info", desc = "package.json version lens (IDEA npm inlays) -- <leader>cp* in package.json" },
    {
      mod = "neogen",
      desc = "Javadoc / KDoc / docstring stub generator (IDEA 'Generate... > Javadoc') -- <leader>cg / <leader>cG",
    },
    { mod = "fidget", desc = "LSP / indexing progress widget (IDEA 'indexing' status bar)" },
    { mod = "trouble", desc = "Diagnostics / quickfix panel (IDEA 'Problems' tool window) -- <leader>xx" },
    { mod = "neogit", desc = "Full Git tool window (IDEA 'Git' / 'Commit') -- <leader>gn" },
  }
  for _, p in ipairs(editor_plugins) do
    if pcall(require, p.mod) then
      vim.health.ok(string.format("%s: loaded (%s)", p.mod, p.desc))
    else
      vim.health.info(string.format("%s: not loaded (%s). Suggestion: :Lazy sync", p.mod, p.desc))
    end
  end

  -- undotree (persistent undo timeline / IDEA 'Local History')
  local ok_undotree = pcall(require, "undotree")
  if
    ok_undotree
    or vim.fn.exists(":UndotreeToggle") == 2
    or vim.fn.isdirectory(vim.fn.stdpath("data") .. "/lazy/undotree") == 1
  then
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
