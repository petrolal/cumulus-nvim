-- TetraVim Core Treesitter Engine
--
-- Every other plugin spec (cloud-terraform.lua, cloud-containers-k8s.lua,
-- lsp-devops.lua, lsp-java.lua, lsp-kotlin.lua, lsp-groovy.lua, lsp-html.lua,
-- lsp-toml.lua) only ever *extends* `opts.ensure_installed` via
-- `vim.list_extend(opts.ensure_installed, {...})` -- none of them ever gave
-- it a starting value, and nothing in the repo ever consumed it. lazy.nvim's
-- default config fallback for a plugin with only `opts` calls
-- `require("nvim-treesitter").setup(opts)`, but the installed nvim-treesitter
-- (rewritten "main" branch, see lazy-lock.json) dropped the old
-- `ensure_installed`/`highlight` config surface entirely -- `setup()` now
-- only understands `install_dir`. So every parser list in this codebase was
-- being silently discarded: no parser was ever downloaded, and Treesitter
-- highlighting was never enabled for any filetype.
--
-- Fix: seed `ensure_installed` with a literal base table so the other
-- fragments have something to extend, then explicitly install the merged
-- list via `require("nvim-treesitter").install()` and enable highlighting
-- per the upstream-documented `vim.treesitter.start()` FileType autocmd
-- (see nvim-treesitter README "Highlighting" section).
return {
  {
    "nvim-treesitter/nvim-treesitter",
    build = ":TSUpdate",
    event = { "BufReadPre", "BufNewFile" },
    opts = {
      ensure_installed = {
        "lua",
        "vim",
        "vimdoc",
        "markdown",
        "markdown_inline",
        "query",
      },
    },
    config = function(_, opts)
      require("nvim-treesitter").setup({})

      if type(opts.ensure_installed) == "table" and #opts.ensure_installed > 0 then
        require("nvim-treesitter").install(opts.ensure_installed)
      end

      vim.api.nvim_create_autocmd("FileType", {
        group = vim.api.nvim_create_augroup("tetravim_treesitter_highlight", { clear = true }),
        callback = function(event)
          -- Skip parsing very large / generated files (protobuf, jOOQ,
          -- OpenAPI codegen, delomboked sources -- routine in JVM work). Full
          -- Tree-sitter parsing on a multi-MB single file freezes the UI the
          -- way IntelliJ's "file too large, code insight disabled" guards
          -- against. snacks.bigfile also covers this, but keep the guard here
          -- so it holds even if snacks is unavailable.
          local ok_stat, stat = pcall((vim.uv or vim.loop).fs_stat, vim.api.nvim_buf_get_name(event.buf))
          if ok_stat and stat and stat.size > 1024 * 1024 then
            return
          end
          pcall(vim.treesitter.start, event.buf)
        end,
      })
    end,
  },
}
