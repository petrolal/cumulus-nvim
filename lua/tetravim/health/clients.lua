-- TetraVim Healthcheck -- Completion, database explorer, HTTP client, gRPC, endpoints panel, Kubernetes, Docker
-- Carved out of the former monolithic lua/tetravim/health.lua
-- (Story 27.2 / Story 35.1 / Story 6.1). Orchestrated by health/init.lua;
-- sections run in the original order so :checkhealth output is unchanged.

local M = {}

function M.check()
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
end

return M
