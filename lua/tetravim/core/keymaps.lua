-- TetraVim Core Keymaps (Story 1.1, Story 4.1 & Epic 9)

local map = vim.keymap.set

-- Leader alternatives for window navigation
map("n", "<leader>ww", "<C-w>w", { desc = "Cycle windows" })
map("n", "<leader>wh", "<C-w>h", { desc = "Focus left window" })
map("n", "<leader>wj", "<C-w>j", { desc = "Focus lower window" })
map("n", "<leader>wk", "<C-w>k", { desc = "Focus upper window" })
map("n", "<leader>wl", "<C-w>l", { desc = "Focus right window" })

-- File explorer shortcut required by the smoke test
vim.keymap.set("n", "<leader>e", function()
  require("oil").open()
end, { desc = "Open file explorer (oil.nvim)" })

-- Visual Selection & Line Movement Chords (Story 9.2)
map("v", "J", ":m '>+1<cr>gv=gv", { desc = "Move Down" })
map("v", "K", ":m '<-2<cr>gv=gv", { desc = "Move Up" })
map("v", "<", "<gv", { desc = "Outdent and Reselect" })
map("v", ">", ">gv", { desc = "Indent and Reselect" })
map("n", "n", "nzzzv", { desc = "Next Search Centered" })
map("n", "N", "Nzzzv", { desc = "Prev Search Centered" })

-- LSP Diagnostics & Symbol Navigation Chords (Story 9.3 & Story 13.2)
map("n", "[d", function()
  vim.diagnostic.jump({ count = -1 })
end, { desc = "Prev Diagnostic" })
map("n", "]d", function()
  vim.diagnostic.jump({ count = 1 })
end, { desc = "Next Diagnostic" })
map("n", "[e", function()
  vim.diagnostic.jump({ count = -1, severity = vim.diagnostic.severity.ERROR })
end, { desc = "Prev Error" })
map("n", "]e", function()
  vim.diagnostic.jump({ count = 1, severity = vim.diagnostic.severity.ERROR })
end, { desc = "Next Error" })
map("n", "<leader>ca", function()
  vim.lsp.buf.code_action()
end, { desc = "Code Action" })
map("n", "<leader>cr", function()
  vim.lsp.buf.rename()
end, { desc = "Rename Symbol" })

-- Global code group keymaps: format, diagnostics, codelens, organize
-- imports, source action, rename file, lsp info (Story 34.2)
map("n", "<leader>cd", function()
  vim.diagnostic.open_float()
end, { desc = "Line Diagnostics" })
map({ "n", "x" }, "<leader>cf", function()
  require("tetravim.util.format").format({ force = true })
end, { desc = "Format" })
map({ "n", "x" }, "<leader>cF", function()
  require("conform").format({ formatters = { "injected" }, timeout_ms = 3000 })
end, { desc = "Format Injected Langs" })
map({ "n", "x" }, "<leader>cc", function()
  vim.lsp.codelens.run()
end, { desc = "Run Codelens" })
map("n", "<leader>cC", function()
  vim.lsp.codelens.refresh()
end, { desc = "Refresh & Display Codelens" })
map("n", "<leader>co", function()
  vim.lsp.buf.code_action({
    context = { only = { "source.organizeImports" }, diagnostics = {} },
    apply = true,
  })
end, { desc = "Organize Imports" })
map("n", "<leader>cA", function()
  vim.lsp.buf.code_action({
    context = { only = { "source" }, diagnostics = {} },
  })
end, { desc = "Source Action" })
map("n", "<leader>cR", function()
  local old_name = vim.api.nvim_buf_get_name(0)
  vim.ui.input({ prompt = "New file name: ", default = vim.fn.fnamemodify(old_name, ":t") }, function(new_name)
    if not new_name or new_name == "" then
      return
    end
    local new_path = vim.fn.fnamemodify(old_name, ":h") .. "/" .. new_name
    vim.lsp.util.rename(old_name, new_path)
    vim.cmd("edit " .. vim.fn.fnameescape(new_path))
  end)
end, { desc = "Rename File" })
-- `:LspInfo` (nvim-lspconfig) is a dead command on Neovim 0.11+: its
-- plugin/lspconfig.lua skips defining LspInfo/LspStart/LspStop entirely
-- once Neovim's own native `:lsp` command exists (see
-- `vim.fn.exists(':lsp')` check in nvim-lspconfig's plugin file). That
-- native `:lsp` only has enable/disable/restart/stop subcommands, no info
-- view, so `:checkhealth vim.lsp` is the actual replacement -- it lists
-- active clients, capabilities, and file-watcher status.
map("n", "<leader>cl", "<cmd>checkhealth vim.lsp<cr>", { desc = "Lsp Info" })

-- Per-language <leader>c* subgroups (Story 34.1): build/lint/format commands
-- for a given language stack only appear as buffer-local keymaps while
-- editing a matching filetype, so <leader>c no longer mixes e.g. Maven
-- keymaps into a Python or Terraform buffer's popup. See lang-keymaps.lua.
local lang_keymaps = require("tetravim.core.lang-keymaps")

-- Shared by many keymap callbacks below; hoisted so we don't re-require per press.
local ui = require("tetravim.util.ui")
local grpc = require("tetravim.util.grpc")

-- ==============================================================================
-- ⭐ JVM PLATFORM KEYMAP SUITE (<leader>j) - Unconditionally Registered
-- ==============================================================================
local jvm = require("tetravim.util.jvm")
local jvm_ok, jvm_err = pcall(jvm.setup_keymaps)
if not jvm_ok then
  vim.notify("Failed to register JVM keymaps: " .. tostring(jvm_err), vim.log.levels.WARN, { title = "TetraVim JVM" })
end

-- ==============================================================================
-- 󱁢 Infrastructure & DevOps Platform Suite (<leader>o) - Globally Registered
-- ==============================================================================
local devops = require("tetravim.core.devops")
local ok, err = pcall(devops.setup_keymaps)
if not ok then
  vim.notify("Failed to register DevOps keymaps: " .. tostring(err), vim.log.levels.WARN, { title = "TetraVim DevOps" })
end

lang_keymaps.setup()

-- Plugin & Package Management Keymaps (<leader>l)
map("n", "<leader>ll", "<cmd>Lazy<cr>", { desc = "Lazy Plugin Manager" })
map("n", "<leader>lm", "<cmd>Mason<cr>", { desc = "Mason Tool Manager" })
map("n", "<leader>lc", "<cmd>checkhealth<cr>", { desc = "Checkhealth System" })

-- Buffer keymaps (<leader>b) all live in one place -- the which-key `keys`
-- spec in lua/tetravim/plugins/editor-snacks.lua (bp/bn/bd/bD/bo/bi/bb/b1-9).

-- Window Management Splits & Navigation (<leader>w)
map("n", "<leader>ws", "<cmd>split<cr>", { desc = "Split Window Horizontally" })
map("n", "<leader>wv", "<cmd>vsplit<cr>", { desc = "Split Window Vertically" })
map("n", "<leader>wd", "<cmd>close<cr>", { desc = "Close Window" })

-- Session & Quit Keymaps (Story 10.1 & Story 29.1)
map("n", "<leader>qq", "<cmd>confirm qa<cr>", { desc = "Quit Neovim (Confirm)" })
map("n", "<leader>qQ", "<cmd>qa!<cr>", { desc = "Force Quit Neovim (No Save)" })

-- Database Client Keymaps (vim-dadbod UI) -- <leader>ad, under the shared
-- <leader>a "api/data" group (was the Shift-prefixed <leader>D).
map("n", "<leader>adu", "<cmd>DBUIToggle<cr>", { desc = "Toggle Database UI" })
map("n", "<leader>adf", "<cmd>DBUIFindBuffer<cr>", { desc = "Find DB Buffer" })
map("n", "<leader>ada", "<cmd>DBUIAddConnection<cr>", { desc = "Add DB Connection" })

-- HTTP Client & REST API Explorer Keymaps (kulala.nvim -- SPEC-3.2). The
-- plugin itself is wired up in tools-http.lua; the two custom pieces this
-- story adds (OpenAPI-to-.http generation, jq response filtering) live in
-- tetravim.util.openapi / tetravim.util.http. Response/generated-template
-- output always renders in a persistent split, never a floating window,
-- per this epic's established UX pattern.
-- Thin wrapper over the shared persistent-split renderer (util/split.lua),
-- kept for the historical call-site signature (text, filetype, name_hint).
-- Vertical split matches tools-http.lua's kulala.nvim `split_direction =
-- "right"` so generated-template / jq-filtered output opens in the same
-- orientation as kulala's own response split.
local function tetravim_http_open_in_split(text, filetype, name_hint)
  require("tetravim.util.split").open(text, { filetype = filetype, name_hint = name_hint })
end

map("n", "<leader>ahr", function()
  if vim.bo.filetype ~= "http" then
    ui.notify_err("Open a .http file first -- <leader>ahr only runs requests from a .http buffer")
    return
  end
  local ok, kulala = pcall(require, "kulala")
  if not ok then
    ui.notify_err("kulala.nvim is not available -- open a .http file first")
    return
  end
  -- Guard kulala.run() so a malformed .http buffer surfaces a clean
  -- notification instead of a raw Lua stack trace.
  local run_ok, run_err = pcall(kulala.run)
  if not run_ok then
    ui.notify_err("Failed to run HTTP request: " .. tostring(run_err))
  end
end, { desc = "Run HTTP Request" })

map("n", "<leader>aho", function()
  vim.ui.input({ prompt = "OpenAPI JSON spec path: ", completion = "file" }, function(spec_path)
    if not spec_path or spec_path == "" then
      return
    end
    local http_text = require("tetravim.util.openapi").generate_http_from_spec(spec_path)
    if not http_text then
      return -- tetravim.util.openapi already warned via ui.notify_warn
    end
    tetravim_http_open_in_split(http_text, "http", "generated")
    ui.notify_info("Generated .http request template from " .. spec_path)
  end)
end, { desc = "Generate .http from OpenAPI Spec" })

map("n", "<leader>ahj", function()
  local ft = vim.bo.filetype

  -- A .http source buffer is not a response -- jq has nothing useful to do
  -- with it. Send the user to the response window (or a JSON buffer) rather
  -- than shelling out to jq on request syntax.
  if ft == "http" then
    ui.notify_err(
      "<leader>ahj filters a JSON response, not a .http source -- move to the response window or a JSON buffer first"
    )
    return
  end

  local json_text = table.concat(vim.api.nvim_buf_get_lines(0, 0, -1, false), "\n")
  if json_text == "" then
    ui.notify_warn("Current buffer is empty -- nothing to filter")
    return
  end

  -- Soft heads-up only -- jq can still usefully filter JSON Lines / a
  -- concatenated stream of JSON values that vim.json.decode (which expects
  -- exactly one top-level value) rejects, so a decode failure here warns but
  -- does NOT abort the filter. kulala's own response window
  -- (filetype=kulala_ui) renders a known-good body, so skip the check there.
  if ft ~= "kulala_ui" and not require("tetravim.util.http").looks_like_json(json_text) then
    ui.notify_warn("Current buffer does not look like valid JSON -- jq may fail or produce unexpected output")
  end

  vim.ui.input({ prompt = "jq filter (e.g. .data): " }, function(filter_expr)
    if not filter_expr or filter_expr == "" then
      return
    end
    require("tetravim.util.http").jq_filter(json_text, filter_expr, function(result_text)
      tetravim_http_open_in_split(result_text, "json", "jq-filtered")
    end)
  end)
end, { desc = "jq-Filter JSON Response/Buffer" })

-- gRPC & Protobufs Integration Keymaps (SPEC-3.4). The `.proto` LSP
-- (protols), Tree-sitter parser and `buf` formatter are wired in
-- lsp-proto.lua / core-treesitter.lua / tools-formatting.lua; the two
-- custom pieces this story adds -- reflection-driven service/method
-- browsing and structured RPC execution -- live in tetravim.util.grpc.
-- Every gRPC output renders in the shared persistent split via
-- tetravim_http_open_in_split, never a floating window.
local function tetravim_grpc_prompt_addr(cb)
  vim.ui.input({ prompt = "gRPC server (host:port): ", default = "localhost:50051" }, function(addr)
    if not addr or vim.trim(addr) == "" then
      return
    end
    cb(vim.trim(addr))
  end)
end

-- Open the editable JSON request skeleton in a persistent "grpc-request"
-- split and bind a buffer-local <CR> that reads it back, refuses malformed
-- JSON (never handing it to grpcurl), invokes the RPC async and renders the
-- response in a persistent "grpc-response" json split.
local function tetravim_grpc_open_request(addr, method, skeleton_text)
  tetravim_http_open_in_split(skeleton_text, "json", "grpc-request")
  local bufnr = vim.api.nvim_get_current_buf()
  vim.keymap.set("n", "<CR>", function()
    local payload = table.concat(vim.api.nvim_buf_get_lines(bufnr, 0, -1, false), "\n")
    if not require("tetravim.util.http").looks_like_json(payload) then
      ui.notify_err("gRPC request buffer is not valid JSON -- fix it before pressing <CR> (nothing sent)")
      return
    end
    grpc.invoke(addr, method, payload, function(response)
      tetravim_http_open_in_split(response, "json", "grpc-response")
    end)
  end, { buffer = bufnr, desc = "Invoke RPC with this payload" })
  ui.notify_info("Edit the payload, then press <CR> in this buffer to invoke " .. method)
end

-- Given a fully-qualified method ("pkg.Service/Method" or
-- "pkg.Service.Method"), resolve its request message type via `grpcurl
-- describe`, then a second `describe -msg-template` for that type, and open
-- the generated skeleton for editing.
local function tetravim_grpc_build_request(addr, method)
  grpc.describe(addr, (method:gsub("/", ".")), function(method_desc)
    local parsed = grpc.parse_methods(method_desc)
    if #parsed == 0 or parsed[1].request_type == "" then
      ui.notify_err("Could not determine the request type for " .. method)
      return
    end
    grpc.describe(addr, parsed[1].request_type, function(type_desc)
      local template = grpc.extract_msg_template(type_desc)
      local skeleton = grpc.request_skeleton(template or "")
      if not skeleton then
        return -- request_skeleton already warned
      end
      tetravim_grpc_open_request(addr, method, skeleton)
    end)
  end)
end

map("n", "<leader>agg", function()
  require("grpcui").open()
end, { desc = "UI (grpcurl)" })
map("n", "<leader>agl", function()
  tetravim_grpc_prompt_addr(function(addr)
    grpc.list_services(addr, function(out)
      local services = grpc.parse_service_list(out)
      if #services == 0 then
        ui.notify_warn("No gRPC services reported by " .. addr)
        return
      end
      vim.ui.select(services, { prompt = "gRPC service:" }, function(service)
        if not service then
          return
        end
        grpc.describe(addr, service, function(service_desc)
          local methods = grpc.parse_methods(service_desc)
          if #methods == 0 then
            tetravim_http_open_in_split(service_desc, "proto", "grpc-describe")
            return
          end
          local labels = {}
          for _, m in ipairs(methods) do
            table.insert(labels, m.name)
          end
          vim.ui.select(labels, { prompt = service .. " method:" }, function(choice, idx)
            if not choice or not idx then
              return
            end
            tetravim_grpc_build_request(addr, service .. "/" .. methods[idx].name)
          end)
        end)
      end)
    end)
  end)
end, { desc = "List Services & Methods" })

map("n", "<leader>agm", function()
  local default_symbol = vim.fn.expand("<cword>")
  vim.ui.input({ prompt = "gRPC symbol to describe: ", default = default_symbol }, function(symbol)
    if not symbol or vim.trim(symbol) == "" then
      return
    end
    tetravim_grpc_prompt_addr(function(addr)
      grpc.describe(addr, vim.trim(symbol), function(desc)
        tetravim_http_open_in_split(desc, "proto", "grpc-describe")
      end)
    end)
  end)
end, { desc = "Describe Symbol" })

map("n", "<leader>agi", function()
  vim.ui.input({ prompt = "gRPC method (pkg.Service/Method): " }, function(method)
    if not method or vim.trim(method) == "" then
      return
    end
    tetravim_grpc_prompt_addr(function(addr)
      tetravim_grpc_build_request(addr, vim.trim(method))
    end)
  end)
end, { desc = "Generate Request Skeleton" })

map("n", "<leader>agf", function()
  if vim.bo.filetype ~= "proto" then
    ui.notify_err("<leader>agf formats a .proto buffer -- open one first")
    return
  end
  local ok, conform = pcall(require, "conform")
  if not ok then
    ui.notify_err("conform.nvim is not available")
    return
  end
  conform.format({ bufnr = 0, async = false, lsp_fallback = true })
end, { desc = "Format .proto Buffer (buf)" })

-- State toggles under <leader>u -- autoformat (uf buffer / uF global),
-- autolint (ul buffer / uL global) and background transparency (ut) -- are
-- registered as Snacks.toggle instances in the config() of
-- lua/tetravim/plugins/editor-snacks.lua, so which-key shows their live
-- on/off state. util/format, util/lint and util/transparency hold the logic.

-- Universal File Operations: Save, Save All, Save As (Epic 33)
local function save_current_file()
  local name = vim.api.nvim_buf_get_name(0)
  if name == "" then
    -- Unnamed/scratch buffer: prompt for a file name instead of crashing with E32
    vim.notify("Buffer has no file name — use :saveas or :w <filename>", vim.log.levels.WARN)
    return
  end
  vim.cmd("update")
  local short = vim.fn.fnamemodify(name, ":t")
  vim.notify("Saved " .. short, vim.log.levels.INFO)
end

map({ "n", "i" }, "<C-s>", save_current_file, { desc = "Save Current File" })
map("n", "<leader>fs", save_current_file, { desc = "Save Current File" })

map("n", "<leader>fa", function()
  vim.cmd("wall")
  vim.notify("Saved all modified files", vim.log.levels.INFO)
end, { desc = "Save All Files" })

map("n", "<leader>fS", function()
  local current = vim.fn.expand("%:p")
  vim.ui.input({ prompt = " Save As: ", default = current }, function(input)
    if input and #input > 0 then
      vim.cmd("saveas! " .. vim.fn.fnameescape(input))
      vim.notify("Saved as: " .. input, vim.log.levels.INFO)
    end
  end)
end, { desc = "Save As..." })

-- New File from Template: IntelliJ IDEA Ultimate "New > Java Class / Kotlin
-- Class / HTML File / ..." parity. Context-aware picker; JVM package derived
-- from the target directory's position under a source root.
local function new_file_from_template()
  require("tetravim.util.filetemplate").new_file()
end
map("n", "<leader>fn", new_file_from_template, { desc = "New File from Template" })
map("n", "<leader>n", new_file_from_template, { desc = "New File from Template" })
vim.api.nvim_create_user_command("TetraVimNewFile", new_file_from_template, {
  desc = "Create a file from a template (IDEA-style New)",
})
vim.api.nvim_create_user_command("NewFromTemplate", new_file_from_template, {
  desc = "Create a file from a template (IDEA-style New)",
})

-- ==============================================================================
-- 󰒃 Code Quality & Security Suite (<leader>x) - Epic 6
-- ==============================================================================
-- SonarQube/SonarLint rule diagnostics (Story 6.1) and osv-scanner CVE
-- scanning of Maven/Gradle build files (Story 6.2). SonarLint analysis is
-- driven by the language server wired in lsp-sonarlint.lua; the CVE scan is a
-- pure async shell-out to `osv-scanner` in tetravim.util.cve whose findings
-- are published as buffer diagnostics on the offending dependency lines.
--
-- Keys are grouped by feature type. Within each type "b" is the current-buffer
-- action and "p" is the whole-project action, so Shift always just means
-- "widen from buffer to project". Lint's file-writing "fix" pass is a separate
-- letter ("f" buffer / "F" project) rather than a Shifted "check":
--
--   <leader>xd  diagnostics : xdb line float        | xdp project quickfix
--   <leader>xl  lint        : xlb buffer check      | xlp project check
--                             xlf buffer fix        | xlF project fix
--   <leader>xs  sonar       : xsb buffer rule desc  | xsp project scan
--   <leader>xv  cve         : xvb build-file scan   | xvp project scan
--                             xvc clear diagnostics

-- --- Diagnostics -----------------------------------------------------------
map("n", "<leader>xdb", function()
  vim.diagnostic.open_float(nil, { source = true })
end, { desc = "Line (Buffer)" })

map("n", "<leader>xdp", function()
  vim.diagnostic.setqflist({ open = true, title = "Project diagnostics" })
end, { desc = "All Project (Quickfix)" })

-- --- Lint ----------------------------------------------------------------
-- Buffer: lint / autofix the current file (ignores the <leader>ul autolint
-- toggle). Project: shell out to each stack's own CLI (ktlint,
-- npm-groovy-lint, checkstyle, google-java-format, scalafmt) over the whole
-- repo and render a combined report in a persistent split. The "f"/"F" fix
-- variants rewrite files in place, then reload the affected buffers.
map("n", "<leader>xlb", function()
  require("tetravim.util.lint").lint_now()
end, { desc = "Check Buffer" })
map("n", "<leader>xlp", function()
  require("tetravim.util.lint").project_run("check")
end, { desc = "Check All Code (Project)" })
map("n", "<leader>xlf", function()
  require("tetravim.util.lint").fix_now()
end, { desc = "Fix Buffer (writes file)" })
map("n", "<leader>xlF", function()
  require("tetravim.util.lint").project_run("fix")
end, { desc = "Fix All Code (Project)" })

-- --- Sonar -------------------------------------------------------------
-- Buffer: SonarLint analyzes java/kotlin/scala buffers automatically via the
-- language server; <leader>xsb surfaces the rule description for the finding
-- under the cursor. Project: <leader>xsp runs a whole-codebase analysis --
-- `sonar-scanner` (connected mode) when a sonar-project.properties declares
-- `sonar.host.url` and the CLI is installed, otherwise a server-free sweep
-- that feeds every Java/Kotlin/Scala source to the SonarLint LS and dumps
-- every finding into the quickfix list. See tetravim.util.sonar.project_scan.
map("n", "<leader>xsb", function()
  if not pcall(require, "sonarlint") then
    ui.notify_err("sonarlint.nvim is not available -- run :Lazy sync / :MasonInstall sonarlint-language-server")
    return
  end
  -- sonarlint.nvim exposes rule descriptions via a user command in recent
  -- versions; fall back to code actions (where the LS surfaces "Open rule
  -- description") when that command is absent.
  if vim.fn.exists(":SonarlintShowRuleDescription") == 2 then
    vim.cmd("SonarlintShowRuleDescription")
  else
    vim.lsp.buf.code_action()
  end
end, { desc = "Rule Description (Buffer)" })

map("n", "<leader>xsp", function()
  require("tetravim.util.sonar").project_scan()
end, { desc = "Scan Whole Project" })

-- --- CVE / vulnerabilities -------------------------------------------
-- Buffer: scan the open Maven/Gradle build file and publish WARN diagnostics
-- on each vulnerable dependency line. Project: `osv-scanner -r` over the
-- whole tree, rendered in a persistent split (findings span many files).
map("n", "<leader>xvb", function()
  local cve = require("tetravim.util.cve")
  local bufnr = vim.api.nvim_get_current_buf()
  local path = vim.api.nvim_buf_get_name(bufnr)
  local name = vim.fs.basename(path)
  -- Accept the Maven POM and any Gradle build script (`build.gradle`,
  -- `settings.gradle`, `*.gradle.kts`, module-named `*.gradle`).
  local is_build_file = name == "pom.xml" or name:match("%.gradle$") ~= nil or name:match("%.gradle%.kts$") ~= nil
  if not is_build_file then
    ui.notify_err("<leader>xvb scans a Maven/Gradle build file -- open pom.xml or a *.gradle script first")
    return
  end
  if path == "" or not vim.uv.fs_stat(path) then
    ui.notify_err("<leader>xvb: this buffer is not backed by a file on disk yet -- save it first")
    return
  end
  ui.notify_info("Scanning " .. name .. " for known CVEs (osv-scanner)...")
  cve.scan(path, function(findings, err)
    if not findings then
      -- The scan failed / timed out -- cve.scan already notified. Leave any
      -- existing diagnostics in place rather than acting on a stale result.
      return
    end
    if #findings == 0 then
      cve.clear_diagnostics(bufnr)
      ui.notify_info("osv-scanner: no known vulnerabilities in " .. name)
      return
    end
    cve.publish_diagnostics(bufnr, findings)
    ui.notify_warn(
      string.format(
        "osv-scanner: %d vulnerable dependenc%s in %s -- see diagnostics",
        #findings,
        #findings == 1 and "y" or "ies",
        name
      )
    )
  end)
end, { desc = "Scan Build File (Buffer)" })

map("n", "<leader>xvp", function()
  require("tetravim.util.cve").project_scan()
end, { desc = "Scan Whole Project" })

map("n", "<leader>xvc", function()
  local bufnr = vim.api.nvim_get_current_buf()
  require("tetravim.util.cve").clear_diagnostics(bufnr)
  ui.notify_info("Cleared CVE diagnostics for this buffer")
end, { desc = "Clear Scan Diagnostics" })
