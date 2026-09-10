-- Java JDTLS Ftplugin Auto-Launcher (Story 4.1, Story 13.3 & Story 37.1)

-- SPEC-2.1: Project-Wide Safe Rename -- buffer-local override of the global
-- <leader>cr (plain vim.lsp.buf.rename() in core/keymaps.lua). Installed
-- UNCONDITIONALLY for every Java buffer, not gated on LSP attach: the I/O
-- matrix requires that pressing <leader>cr in a Java buffer with no JDTLS
-- client still produces a visible "no project-wide rename available" notify
-- (via project_rename's own guard) rather than silently falling through to
-- the default rename. The global mapping for non-JVM filetypes is untouched.
vim.keymap.set("n", "<leader>cr", function()
  require("tetravim.util.refactor").project_rename()
end, { buffer = 0, desc = "Project-Wide Rename (Java)" })

local ok, jdtls = pcall(require, "jdtls")
if not ok then
  return
end

-- The bundle-jar globs and lazy.core `opts` lookup below are identical for
-- every Java buffer in a session, so they run once and the result is parked in
-- tetravim.util.jdtls_config; subsequent Java buffers skip straight to the
-- per-file work (root dir / workspace `-data` / heap-bounded cmd).
local jdtls_config_cache = require("tetravim.util.jdtls_config")
local static = jdtls_config_cache.get()

if not static then
  local bundles = {}

  local java_debug_path = vim.fn.expand("~/.local/share/nvim/mason/packages/java-debug-adapter/extension/server")
  local java_debug_jars = vim.fn.glob(java_debug_path .. "/com.microsoft.java.debug.plugin-*.jar", true, true)
  if type(java_debug_jars) == "table" and #java_debug_jars > 0 then
    vim.list_extend(bundles, java_debug_jars)
  end

  local java_test_path = vim.fn.expand("~/.local/share/nvim/mason/packages/java-test/extension/server")
  local java_test_jars = vim.fn.glob(java_test_path .. "/*.jar", true, true)
  if type(java_test_jars) == "table" and #java_test_jars > 0 then
    vim.list_extend(bundles, java_test_jars)
  end

  -- Story 37.1: IDEA bundled-decompiler parity. The dgileadi/vscode-java-decompiler
  -- lazy plugin (see lua/tetravim/plugins/lsp-java.lua) ships Fernflower/CFR/
  -- Procyon bundle jars under its server/ dir; feeding them to jdtls makes
  -- go-to-definition on a source-less library `.class` open a decompiled buffer.
  -- Paired with `java.contentProvider.preferred = "fernflower"` in lsp-java.lua.
  local decompiler_root = vim.fn.stdpath("data") .. "/lazy/vscode-java-decompiler/server"
  if vim.fn.isdirectory(decompiler_root) == 1 then
    local decompiler_jars = vim.fn.glob(decompiler_root .. "/*.jar", true, true)
    if type(decompiler_jars) == "table" and #decompiler_jars > 0 then
      vim.list_extend(bundles, decompiler_jars)
    end
  end

  -- Spring Boot / Quarkus / MicroProfile JDT extensions. Each `java_extensions()`
  -- returns {} when its plugin or backing jars are absent (see lsp-spring-boot.lua
  -- / lsp-quarkus.lua), so on a machine without the framework tooling this whole
  -- block is a no-op. With the jars present, jdtls gains Spring symbol indexing,
  -- `@ConfigurationProperties` / `@ConfigProperty` metadata and Qute Java support.
  for _, mod in ipairs({ "spring_boot", "microprofile", "quarkus" }) do
    local ext_ok, ext = pcall(function()
      return require(mod).java_extensions()
    end)
    if ext_ok and type(ext) == "table" and #ext > 0 then
      vim.list_extend(bundles, ext)
    end
  end

  local opts = {}
  local lazy_ok, lazy_config = pcall(require, "lazy.core.config")
  if lazy_ok and lazy_config and lazy_config.spec and lazy_config.spec.plugins["nvim-jdtls"] then
    local plugin = lazy_config.spec.plugins["nvim-jdtls"]
    local lazy_plugin_ok, lazy_plugin = pcall(require, "lazy.core.plugin")
    if lazy_plugin_ok then
      opts = lazy_plugin.values(plugin, "opts", false) or {}
    end
  end

  static = { bundles = bundles, opts = opts }
  jdtls_config_cache.set(static)
end

local bundles = static.bundles
local opts = static.opts

local fname = vim.api.nvim_buf_get_name(0)
local cmd = opts.full_cmd and opts.full_cmd({ "jdtls" }) or { "jdtls" }
local root_dir = (opts.root_dir and opts.root_dir(fname))
  or jdtls.setup.find_root({ ".git", "mvnw", "gradlew", "pom.xml", "build.gradle", "build.gradle.kts" }, fname)
  or (fname and fname ~= "" and vim.fs.dirname(fname))
  or vim.fn.getcwd()

local project_name = vim.fs.basename(root_dir)
if not project_name or project_name == "" then
  project_name = vim.fn.fnamemodify(root_dir, ":p:h:t")
end
local workspace_dir = vim.fn.stdpath("cache") .. "/jdtls/workspace/" .. project_name
local has_data = false
for _, arg in ipairs(cmd) do
  if type(arg) == "string" and (arg == "-data" or arg:find("^-data")) then
    has_data = true
    break
  end
end
if not has_data then
  table.insert(cmd, "-data")
  table.insert(cmd, workspace_dir)
end

-- Story 5.1: bound the JDTLS JVM heap so indexing a large monorepo cannot
-- OOM the machine, and auto-restart (bounded) if the server process crashes.
local resilience = require("tetravim.util.lsp_resilience")
cmd = resilience.apply_memory_limit(cmd, {
  xmx = resilience.JDTLS_MAX_HEAP,
  xms = resilience.JDTLS_MIN_HEAP,
})

-- Story 5.1: never-attached crash streaks (jdtls dies before `on_attach`
-- ever fires) would otherwise leak their restart budget across ftplugin
-- reloads. Reset the window here when there is no live jdtls client yet.
if #(vim.lsp.get_clients({ name = "jdtls" }) or {}) == 0 then
  resilience.reset("jdtls")
end

-- The buffer this ftplugin instance fired for. The auto-restart callback
-- below is a closure captured at first start; by the time a crash fires it
-- days later the user may have moved on, so it re-checks this buffer is
-- still a live Java buffer before resurrecting jdtls.
local ftplugin_bufnr = vim.api.nvim_get_current_buf()

-- Build a fresh config table for every (re)start so an auto-restart after a
-- crash never re-submits a table that `start_or_attach` has already mutated.
local function make_config()
  return {
    cmd = cmd,
    root_dir = root_dir,
    settings = opts.settings,
    -- Debounce document-change syncs and use incremental sync so a fast
    -- typist doesn't flood jdtls with full-document didChange payloads.
    flags = {
      debounce_text_changes = 150,
      allow_incremental_sync = true,
    },
    -- Shared cmp-nvim-lsp completion capabilities (same table lsp-core.lua
    -- gives every other server) so jdtls emits snippet edits, resolvable
    -- Javadoc and import text-edits for the completion popup.
    capabilities = require("tetravim.util.lsp_capabilities").make(),
    on_exit = resilience.make_on_exit("jdtls", function()
      -- Only resurrect jdtls if the buffer that started it is still open and
      -- still Java -- otherwise a crash long after the user closed every Java
      -- file would spin the server back up for nothing.
      if
        not (
          vim.api.nvim_buf_is_valid(ftplugin_bufnr)
          and vim.api.nvim_buf_is_loaded(ftplugin_bufnr)
          and vim.bo[ftplugin_bufnr].filetype == "java"
        )
      then
        return
      end
      jdtls.start_or_attach(make_config())
    end),
    init_options = {
      bundles = bundles,
    },
    on_attach = function(client, bufnr)
      -- Story 5.1: a clean attach means the previous crash streak (if any) is
      -- over -- start a fresh restart window.
      resilience.reset("jdtls")
      jdtls.setup_dap({ hotcodereplace = "auto" })
      local ok_dap, jdtls_dap = pcall(require, "jdtls.dap")
      if ok_dap and jdtls_dap.setup_dap_main_class_configs then
        jdtls_dap.setup_dap_main_class_configs()
      end
      -- Setup Spring Boot DAP configurations (SPEC-006)
      local ok_sb, springboot_debug = pcall(require, "tetravim.util.springboot-debug")
      if ok_sb and springboot_debug.setup_springboot_dap then
        springboot_debug.setup_springboot_dap(root_dir)
      end
      if opts.on_attach then
        opts.on_attach(client, bufnr)
      end
      -- Attach notification is handled generically for every LSP client
      -- (including jdtls) by the LspAttach autocmd in lsp-core.lua.

      -- SPEC-2.1: <leader>cr is installed unconditionally at the top of this
      -- ftplugin (see there) so the no-client case still notifies -- not
      -- re-bound here.

      -- SPEC-2.2: Intelligent Extraction
      -- Wires up: extract_interface, inline, extract_method, extract_variable, extract_constant
      require("tetravim.util.extract").setup_keymaps(bufnr, "Java")
    end,
  }
end

jdtls.start_or_attach(make_config())
