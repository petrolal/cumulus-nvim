-- TetraVim Native Setup & Headless Provisioning Module
--
-- Consolidates headless provisioning and maintenance routines into a single
-- native Lua pipeline:
--   1. Lazy.nvim plugin sync
--   2. Mason tool-chain installation
--   3. Quarkus / MicroProfile JVM LSP jars fetch (Open VSX)
--   4. Tree-sitter parsers install & compilation
--   5. Machine-readable health snapshot
--
-- Can be driven headlessly or interactively via :TetraVimSetup

local M = {}

--- Run the full setup pipeline.
--- @param opts? table { sync?: boolean, silent?: boolean, parsers?: string[] }
--- @return table summary { ok: boolean, degraded: string[], health: table }
function M.run(opts)
  opts = opts or {}
  local degraded = {}

  local function log(msg)
    if not opts.silent then
      io.write(string.format("[tetravim.setup] %s\n", msg))
    end
  end

  log("Starting TetraVim native provisioning...")

  -- 1. Plugin sync (if Lazy is available)
  local lazy_ok, lazy = pcall(require, "lazy")
  if lazy_ok and lazy.sync then
    log("1/5 Syncing plugins...")
    local ok = pcall(function()
      lazy.sync({ wait = true, show = not opts.silent })
    end)
    if not ok then
      log("WARNING: Lazy sync encountered an issue")
      table.insert(degraded, "lazy-plugins")
    end
  end

  -- 2. Mason tool-chain
  log("2/5 Installing Mason tool-chain...")
  local mason_installer_ok, mason_installer = pcall(require, "mason-tool-installer")
  if mason_installer_ok and mason_installer.run then
    local ok = pcall(function()
      mason_installer.run()
    end)
    if not ok then
      log("WARNING: Mason tools installation failed")
      table.insert(degraded, "mason-tools")
    end
  else
    -- Fallback via vim command
    pcall(vim.cmd, "MasonToolsInstall")
  end

  -- 3. JVM LSP Jars (Quarkus / MicroProfile)
  log("3/5 Fetching Quarkus / MicroProfile JVM LSP jars...")
  local jvm_fw_ok, jvm_fw = pcall(require, "tetravim.util.jvm.frameworks")
  if jvm_fw_ok and jvm_fw.fetch_jars then
    local fetch_ok = jvm_fw.fetch_jars({ sync = true, silent = opts.silent })
    if not fetch_ok then
      log("WARNING: JVM LSP jar fetch failed (Quarkus/MicroProfile)")
      table.insert(degraded, "jvm-lsp-jars")
    end
  end

  -- 4. Tree-sitter parsers
  log("4/5 Installing Tree-sitter parsers...")
  local ts_ok, ts = pcall(require, "nvim-treesitter")
  if ts_ok and ts.install then
    local parsers = opts.parsers or { "java", "kotlin", "scala", "lua", "regex" }
    local res = ts.install(parsers)
    if res and res.wait then
      pcall(function()
        res:wait(120000)
      end)
    end
  end

  -- 5. Health Snapshot
  log("5/5 Generating health snapshot...")
  local health_ok, health_mod = pcall(require, "tetravim.core.health_json")
  local health_snapshot = {}
  if health_ok and health_mod.json then
    pcall(function()
      health_snapshot = vim.json.decode(health_mod.json())
    end)
  end

  local is_clean = #degraded == 0
  if is_clean then
    log("Provisioning complete: all steps clean.")
  else
    log("Provisioning complete (DEGRADED): " .. table.concat(degraded, ", "))
  end

  return {
    ok = is_clean,
    degraded = degraded,
    health = health_snapshot,
  }
end

--- Register the :TetraVimSetup user command
function M.setup()
  vim.api.nvim_create_user_command("TetraVimSetup", function(cmd_opts)
    local sync = cmd_opts.bang or false
    M.run({ sync = sync, silent = false })
  end, {
    bang = true,
    desc = "Run the full TetraVim native provisioning and setup pipeline",
  })
end

return M
