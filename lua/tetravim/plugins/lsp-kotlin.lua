local jvm = require("tetravim.util.jvm")

local storage_path = vim.fn.stdpath("cache") .. "/kotlin-language-server"
vim.fn.mkdir(storage_path, "p")

local function kotlin_on_attach(client, bufnr)
  -- SPEC-2.2: Intelligent Extraction
  -- Wires up: extract_interface, inline, extract_method, extract_variable, extract_constant
  require("tetravim.util.extract").setup_keymaps(bufnr, "Kotlin")
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
local has_kotlin_lsp = vim.fn.executable("intellij-server") == 1
  or vim.fn.filereadable(mason_server_bin) == 1
local kotlin_lsp_bin = vim.fn.filereadable(mason_server_bin) == 1 and mason_server_bin or "intellij-server"

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
          root_dir = resolve_root,
          on_attach = kotlin_on_attach,
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
