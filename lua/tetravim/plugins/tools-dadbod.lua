-- TetraVim SQL Database Client (DataGrip Parity) -- SPEC-3.1

local ui = require("tetravim.util.ui")
local SQL_FILETYPES = { "sql", "mysql", "plsql" }
local DADBOD_SOURCE_NAME = "vim-dadbod-completion"

--- Register the vim-dadbod-completion cmp source on `bufnr`, merged
--- alongside whatever sources are already configured (LSP, buffer, etc.)
--- instead of replacing them. Safe to call more than once for the same
--- buffer (e.g. a re-fired FileType event) -- a `vim.b` flag plus an
--- explicit duplicate check both guard against accumulating repeat entries.
---@param bufnr integer
local function register_dadbod_completion(bufnr)
  if not vim.api.nvim_buf_is_valid(bufnr) then
    return
  end
  if vim.b[bufnr].tetravim_dadbod_completion_registered then
    return
  end

  local ok, cmp = pcall(require, "cmp")
  if
    not ok
    or type(cmp) ~= "table"
    or type(cmp.get_config) ~= "function"
    or type(cmp.setup) ~= "table"
    or type(cmp.setup.buffer) ~= "function"
  then
    return
  end

  -- cmp.get_config() can return nil/incomplete before cmp.setup() has ever
  -- run (e.g. this buffer's FileType fires before nvim-cmp's own
  -- InsertEnter-triggered load/setup) -- guard both the call and the shape
  -- of what it returns before indexing into it.
  local ok_cfg, cfg = pcall(cmp.get_config)
  if not ok_cfg or type(cfg) ~= "table" then
    return
  end

  local existing = type(cfg.sources) == "table" and cfg.sources or {}
  local sources = vim.deepcopy(existing)

  local already_present = false
  for _, source in ipairs(sources) do
    if source.name == DADBOD_SOURCE_NAME then
      already_present = true
      break
    end
  end
  if not already_present then
    table.insert(sources, 1, { name = DADBOD_SOURCE_NAME })
  end

  -- pcall nvim_buf_call itself: the buffer can be wiped between the
  -- nvim_buf_is_valid check above and here, and the error would otherwise
  -- escape the FileType autocmd callback.
  local call_ok, applied_ok = pcall(vim.api.nvim_buf_call, bufnr, function()
    return pcall(cmp.setup.buffer, { sources = sources })
  end)
  if call_ok and applied_ok then
    vim.b[bufnr].tetravim_dadbod_completion_registered = true
  end
end

--- Re-run Spring datasource auto-discovery against the CURRENT cwd and
--- assign the result to `vim.g.dbs`. Stateless (re-reads config files from
--- disk every call) -- shared between the plugin spec's `init()` (first
--- run, before lazy.nvim loads the plugin) and the `DirChanged` autocmd
--- registered in `config()` (re-run on every project switch).
---
--- On a successful scan: a non-empty result is assigned to `vim.g.dbs`; an
--- EMPTY result clears it back to `nil` (the frozen I/O-matrix "left unset"
--- state) -- which also clears any list left over from a previously-`:cd`'d
--- project, so switching into a datasource-less project doesn't keep
--- pointing at the old one. Only a discovery ERROR (the `not ok` branch)
--- leaves `vim.g.dbs` untouched.
local function discover_and_assign_datasources()
  local ok, dbs = pcall(function()
    return require("tetravim.util.clients.db").discover_datasources(vim.fn.getcwd())
  end)
  if ok then
    if type(dbs) == "table" then
      vim.g.dbs = #dbs > 0 and dbs or nil
    end
  else
    ui.notify_warn("Spring datasource auto-discovery failed: " .. tostring(dbs))
  end
end

return {
  {
    "tpope/vim-dadbod",
    cmd = { "DB", "DBUI", "DBUIToggle", "DBUIAddConnection", "DBUIFindBuffer" },
    -- Also load on sql/mysql/plsql FileType (not just the DB* commands) so
    -- the vim-dadbod-completion cmp source below gets registered as soon as
    -- a SQL buffer is opened, not only after the user has already run a DB
    -- command in some other buffer first. lazy.nvim re-fires the triggering
    -- FileType event after loading, so config()'s own FileType autocmd
    -- still fires for this exact buffer.
    ft = SQL_FILETYPES,
    dependencies = {
      "kristijanhusak/vim-dadbod-ui",
      "kristijanhusak/vim-dadbod-completion",
    },
    -- vim-dadbod-ui reads these g: globals (including g:dbs) from its own
    -- plugin/ script, which only runs once lazy.nvim loads the plugin --
    -- they must be set in init() (runs before load), not config() (runs
    -- after). Discovery is stateless: config files are re-read from disk on
    -- every call, nothing about the credentials is cached or persisted.
    init = function()
      vim.g.db_ui_use_nerd_fonts = 1
      vim.g.db_ui_show_help = 0

      discover_and_assign_datasources()
    end,
    config = function()
      vim.api.nvim_create_autocmd("FileType", {
        group = vim.api.nvim_create_augroup("tetravim_dadbod_completion", { clear = true }),
        pattern = SQL_FILETYPES,
        callback = function(event)
          register_dadbod_completion(event.buf)
        end,
      })

      -- Buffers whose filetype was already sql/mysql/plsql BEFORE this
      -- plugin finished loading (e.g. the plugin loaded via a `:DB*`
      -- command run from a different buffer, while a .sql buffer was
      -- already open) never fire FileType again on their own -- catch them
      -- up immediately instead of only covering buffers opened afterward.
      for _, bufnr in ipairs(vim.api.nvim_list_bufs()) do
        if vim.api.nvim_buf_is_loaded(bufnr) and vim.tbl_contains(SQL_FILETYPES, vim.bo[bufnr].filetype) then
          register_dadbod_completion(bufnr)
        end
      end

      -- init() only runs the discovery scan once, against the cwd Neovim
      -- happened to start in -- switching projects (`:cd`, oil.nvim, a
      -- session load, etc.) never re-scans, so vim.g.dbs silently keeps
      -- pointing at the FIRST project's datasources forever. Re-run
      -- discovery on every DirChanged so :DBUIToggle/:DBUIFindBuffer see
      -- the newly-`:cd`'d project's own datasources instead.
      vim.api.nvim_create_autocmd("DirChanged", {
        group = vim.api.nvim_create_augroup("tetravim_dadbod_discovery", { clear = true }),
        callback = function()
          -- vim.g.dbs is a single GLOBAL variable shared across every tab
          -- and window -- only react to a global-scope `:cd`, never a
          -- window/tab-local `:lcd`/`:tcd`, or switching directories in one
          -- tab would silently overwrite the datasource list every other
          -- tab/window sees.
          if vim.v.event.scope == "global" then
            discover_and_assign_datasources()
          end
        end,
      })
    end,
  },

  -- Extends nvim-treesitter's ensure_installed list (seeded in
  -- core-treesitter.lua) the same way lsp-toml.lua does for "toml" -- gets
  -- syntax highlighting for .sql buffers.
  {
    "nvim-treesitter/nvim-treesitter",
    opts = function(_, opts)
      if type(opts.ensure_installed) == "table" then
        vim.list_extend(opts.ensure_installed, { "sql" })
      end
    end,
  },
}
