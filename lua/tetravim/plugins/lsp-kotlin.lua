local jvm = require("tetravim.util.jvm.jvm")

local storage_path = vim.fn.stdpath("cache") .. "/kotlin-language-server"
vim.fn.mkdir(storage_path, "p")

local function kotlin_on_attach(client, bufnr)
  -- SPEC-2.2: Intelligent Extraction
  -- Wires up: extract_interface, inline, extract_method, extract_variable, extract_constant
  require("tetravim.util.edit.extract").setup_keymaps(bufnr, "Kotlin")
end

local function resolve_root(fname_or_buf, on_dir)
  local fname = type(fname_or_buf) == "number" and vim.api.nvim_buf_get_name(fname_or_buf) or fname_or_buf
  local util = require("lspconfig.util")
  local root = util.root_pattern(
    "settings.gradle",
    "settings.gradle.kts",
    "build.gradle",
    "build.gradle.kts",
    "pom.xml",
    "workspace.json",
    ".git"
  )(fname)
  local resolved = root or (fname and fname ~= "" and vim.fs.dirname(fname)) or vim.fn.getcwd()
  if on_dir then
    on_dir(resolved)
  end
  return resolved
end

-- Prefer JetBrains' official kotlin-lsp (intellij-server) when installed;
-- fall back to fwcd/kotlin-language-server otherwise.
local mason_server_bin = vim.fn.stdpath("data") .. "/mason/bin/intellij-server"
local has_kotlin_lsp = vim.fn.executable("intellij-server") == 1 or vim.fn.filereadable(mason_server_bin) == 1
local kotlin_lsp_bin = vim.fn.filereadable(mason_server_bin) == 1 and mason_server_bin or "intellij-server"

-- JetBrains' intellij-server keeps ONE RocksDB workspace index per project under
-- ~/.cache/JetBrains/analyzer/workspaces/<hash>/index/kotlin-server/rocks/v*/LOCK
-- and guards it with a POSIX fcntl lock. A second intellij-server against the
-- same index loses the lock race and fails *every* request -- `initialize`
-- included -- with
--   RPC[Error] RequestFailed "While lock file: .../kotlin-server/rocks/vNNN/LOCK:
--   Resource temporarily unavailable"
-- which nvim surfaces as an uncaught `vim.schedule callback` error (client.lua
-- asserts on the initialize error) and then the generic resilience layer
-- restart-thrashes into the same wall.
--
-- fcntl locks are invisible to flock(1), so we gate on the real precondition
-- instead: is another intellij-server already alive? (Caveat: this also
-- suppresses a legitimate second project whose index hash differs -- rare, and
-- far better than a crash loop. Escape hatch: TETRAVIM_KOTLIN_LSP_FORCE=1.)
local function foreign_kotlin_lsp()
  if vim.env.TETRAVIM_KOTLIN_LSP_FORCE == "1" then
    return false
  end
  if vim.fn.executable("pgrep") ~= 1 then
    return false
  end
  vim.fn.system({ "pgrep", "-f", "intellij-server" })
  return vim.v.shell_error == 0
end

-- Deferred suppression gate. This precondition used to be evaluated at
-- module-load time, but `foreign_kotlin_lsp()` shells out to `pgrep`
-- synchronously -- on the eager startup path that the CI startup-time budget
-- guards. Run it lazily instead, from `kotlin_lsp_root` below, when the first
-- Kotlin buffer actually asks the server to start; warn at most once per
-- session.
local suppressed_notified = false

local function kotlin_lsp_root(fname_or_buf, on_dir)
  if foreign_kotlin_lsp() then
    if not suppressed_notified then
      suppressed_notified = true
      vim.schedule(function()
        require("tetravim.util.ui").notify_warn(
          "Kotlin LSP: another Neovim/IDE already holds the JetBrains workspace index -- "
            .. "not starting a second intellij-server (it would fail every request). "
            .. "Close the other session, or set TETRAVIM_KOTLIN_LSP_FORCE=1, then :LspStart kotlin_lsp.",
          "kotlin-lsp"
        )
      end)
    end
    -- Do not call on_dir: with a function root_dir that never resolves, no
    -- client is started for this buffer -- and a later buffer retries, so
    -- closing the other session recovers without a config reload.
    return
  end
  return resolve_root(fname_or_buf, on_dir)
end

local resilience = require("tetravim.util.lsp.resilience")

-- Bespoke on_exit: re-fire FileType so a genuine crash re-attaches (mirrors the
-- generic path in lsp-core.lua), but if a foreign intellij-server is holding the
-- shared index at exit time, back off silently-once instead of thrashing.
local function kotlin_lsp_refire()
  pcall(vim.lsp.enable, "kotlin_lsp", false)
  pcall(vim.lsp.enable, "kotlin_lsp")
  vim.schedule(function()
    for _, bufnr in ipairs(vim.api.nvim_list_bufs()) do
      if vim.api.nvim_buf_is_loaded(bufnr) and vim.bo[bufnr].buftype == "" and vim.bo[bufnr].filetype == "kotlin" then
        pcall(vim.api.nvim_exec_autocmds, "FileType", { buffer = bufnr })
      end
    end
  end)
end

local kotlin_lsp_bounded_restart = resilience.make_on_exit("kotlin_lsp", kotlin_lsp_refire)

local function kotlin_lsp_on_exit(code, signal, client_id)
  if foreign_kotlin_lsp() then
    resilience.reset("kotlin_lsp")
    vim.schedule(function()
      require("tetravim.util.ui").notify_warn(
        "Kotlin LSP: workspace index is locked by another Neovim/IDE -- not restarting. "
          .. "Free it (or set TETRAVIM_KOTLIN_LSP_FORCE=1) and run :LspStart kotlin_lsp.",
        "kotlin-lsp"
      )
    end)
    return
  end
  return kotlin_lsp_bounded_restart(code, signal, client_id)
end

return {
  {
    "nvim-treesitter/nvim-treesitter",
    opts = function(_, opts)
      if type(opts.ensure_installed) == "table" then
        vim.list_extend(opts.ensure_installed, { "kotlin" })
      end
    end,
  },

  {
    "neovim/nvim-lspconfig",
    opts = {
      servers = {
        -- Official JetBrains Kotlin Language Server (IntelliJ IDEA engine)
        kotlin_lsp = {
          enabled = has_kotlin_lsp,
          cmd = { kotlin_lsp_bin, "--stdio" },
          -- kotlin_lsp_root layers the (now deferred) concurrent-index guard
          -- over resolve_root; the fallback server below keeps plain resolve_root.
          root_dir = kotlin_lsp_root,
          on_attach = kotlin_on_attach,
          on_exit = kotlin_lsp_on_exit,
        },

        -- Legacy fwcd/kotlin-language-server fallback
        kotlin_language_server = {
          enabled = not has_kotlin_lsp,
          init_options = {
            storagePath = storage_path,
          },
          cmd_env = (function()
            -- The kotlin-language-server launcher is a Gradle `application`
            -- start script, which execs the JVM with `$JAVA_OPTS` forwarded --
            -- so a heap ceiling here bounds KLS the same way
            -- lsp_resilience.apply_memory_limit bounds jdtls. Without it KLS
            -- routinely grows past 4 GiB indexing a large Gradle build.
            local env = { JAVA_OPTS = "-Xmx2g -Xms256m" }
            local java21_home = jvm.find_java21_home()
            if java21_home then
              env.JAVA_HOME = java21_home
            end
            return env
          end)(),
          root_dir = resolve_root,
          handlers = {
            -- kotlin-language-server's documentHighlight implementation crashes in Kotlin Compiler 2.x
            -- with UnsupportedOperationException (JSON-RPC error -32603) on annotated classes / doc comments.
            -- Silently suppress -32603 / errors so they do not produce disruptive error toasts.
            ["textDocument/documentHighlight"] = function(err, result, ctx, config)
              if err then
                return
              end
              return vim.lsp.handlers["textDocument/documentHighlight"](err, result, ctx, config)
            end,
          },
          on_init = function(client, _)
            client.server_capabilities.documentHighlightProvider = false
            client.server_capabilities.semanticTokensProvider = nil
          end,
          on_attach = function(client, bufnr)
            -- kotlin-language-server's documentHighlight implementation crashes in Kotlin Compiler 2.x
            -- with UnsupportedOperationException (JSON-RPC error -32603) on annotated classes / doc comments.
            -- Disabling documentHighlightProvider prevents Neovim from dispatching documentHighlight on CursorHold.
            client.server_capabilities.documentHighlightProvider = false

            -- KLS semantic tokens crash with EOF exceptions during buffer edits; Tree-sitter handles highlighting.
            client.server_capabilities.semanticTokensProvider = nil

            -- Clean up any lingering highlight autocmds and references from the buffer
            pcall(vim.api.nvim_clear_autocmds, { group = "tetravim_lsp_document_highlight", buffer = bufnr })
            pcall(vim.lsp.buf.clear_references)

            local root = client.config.root_dir or vim.fn.getcwd()
            if root and root ~= "" then
              local kls_files = vim.fn.glob(root .. "/kls_database*", false, true)
              for _, f in ipairs(kls_files) do
                vim.fn.delete(f)
              end
            end

            kotlin_on_attach(client, bufnr)
          end,
          settings = {
            kotlin = {
              storagePath = storage_path,
              compiler = {
                jvm = {
                  target = "21",
                },
              },
              hints = {
                typeHints = true,
                parameterHints = true,
                chainedMemberFunctionHints = true,
              },
            },
          },
        },
      },
    },
  },
}
