-- TetraVim JVM framework LSP activation gate
--
-- The Quarkus (`com.redhat.quarkus.ls`), Qute (`com.redhat.qute.ls`) and
-- lsp4mp (`org.eclipse.lsp4mp.ls`) servers are each a separate ~1 GiB JVM that
-- stacks on top of jdtls + the Spring Boot LS. On a machine already running an
-- IDE-sized jdtls that is enough to push a 8-16 GiB laptop into swap, so their
-- activation is opt-in rather than "on whenever the jars exist":
--
--   * a persisted flag (`stdpath("state")/tetravim/jvm-lsp-active`) records the
--     opt-in; `lsp-quarkus.lua` only wires the launch autocmds when it is set,
--   * a `MemAvailable` guard refuses to auto-activate below `LOW_RAM_MB`,
--   * `<leader>jsq` flips the flag and (when enabling) activates immediately,
--   * `:checkhealth tetravim` reports the flag plus live per-server `VmRSS`.
--
-- `rss_report()` scans `/proc` for the language-server JVMs by classpath marker
-- rather than asking the LSP clients for a pid (Neovim does not expose one).

local M = {}

--- Refuse to auto-activate the extra JVMs when `MemAvailable` is under this.
M.LOW_RAM_MB = 3072

local function state_file()
  return vim.fn.stdpath("state") .. "/tetravim/jvm-lsp-active"
end

--- `MemAvailable` from `/proc/meminfo`, in MiB. nil off Linux / on parse failure.
---@return integer|nil
function M.available_ram_mb()
  local f = io.open("/proc/meminfo", "r")
  if not f then
    return nil
  end
  local txt = f:read("*a") or ""
  f:close()
  local kb = txt:match("MemAvailable:%s+(%d+)")
  if not kb then
    return nil
  end
  return math.floor(tonumber(kb) / 1024)
end

--- Has the user opted into the Quarkus / MicroProfile servers?
---@return boolean
function M.is_enabled()
  return vim.fn.filereadable(state_file()) == 1
end

local function persist(on)
  local path = state_file()
  if on then
    vim.fn.mkdir(vim.fs.dirname(path), "p")
    local fh = io.open(path, "w")
    if fh then
      fh:write("1\n")
      fh:close()
    end
  else
    vim.fn.delete(path)
  end
end

--- Why activation is currently refused, or nil when it is allowed.
---@return string|nil
function M.reason_blocked()
  local ok, fw = pcall(require, "tetravim.util.jvm.frameworks")
  if not ok or not fw.quarkus_ready() then
    return "jars not fetched -- run :TetraVimFetchJvmLspJars"
  end
  local ram = M.available_ram_mb()
  if ram and ram < M.LOW_RAM_MB then
    return string.format("only %d MiB RAM available (< %d MiB guard)", ram, M.LOW_RAM_MB)
  end
  return nil
end

--- Should `lsp-quarkus.lua` wire the launch autocmds when it loads?
--- Opt-in flag AND jars present AND enough free RAM.
---@return boolean
function M.should_autostart()
  return M.is_enabled() and M.reason_blocked() == nil
end

local activated = false

--- Run the quarkus / microprofile `.setup()` + `.launch.setup()` chain once.
--- Idempotent; returns false when the jars are missing.
---@return boolean
function M.activate()
  if activated then
    return true
  end
  local ok, fw = pcall(require, "tetravim.util.jvm.frameworks")
  if not ok then
    return false
  end
  local qp = fw.quarkus_paths()
  local mp = fw.microprofile_paths()
  if not (qp and mp) then
    return false
  end

  local java_bin = fw.java_cmd()
  local caps = require("tetravim.util.lsp.capabilities").make()

  -- Order matters: `quarkus.setup` registers `com.redhat.quarkus.ls.jar` with
  -- the microprofile module, so it must run before the lsp4mp launch builds its
  -- classpath.
  require("quarkus").setup({
    java_bin = java_bin,
    ls_path = qp.ls_path,
    jdt_extensions_path = qp.jdt_extensions_path,
    microprofile_ext_path = qp.microprofile_ext_path,
  })
  require("microprofile").setup({
    java_bin = java_bin,
    ls_path = mp.ls_path,
    jdt_extensions_path = mp.jdt_extensions_path,
  })
  require("quarkus.launch").setup({ capabilities = vim.deepcopy(caps) })
  require("microprofile.launch").setup({ capabilities = vim.deepcopy(caps) })
  activated = true
  return true
end

--- `<leader>jsq`: flip the opt-in flag. Enabling activates immediately and kicks
--- the FileType autocmd for the current buffer so the servers spawn now.
function M.toggle()
  local notify = require("tetravim.util.notify")
  if M.is_enabled() then
    persist(false)
    notify.notify_info(
      "Quarkus / MicroProfile LSP disabled -- restart Neovim to stop the running servers",
      "TetraVim JVM"
    )
    return
  end

  local blocked = M.reason_blocked()
  if blocked then
    notify.notify_warn("Cannot enable Quarkus / MicroProfile LSP: " .. blocked, "TetraVim JVM")
    return
  end

  persist(true)
  if not M.activate() then
    persist(false)
    notify.notify_warn("Quarkus / MicroProfile jars missing -- run :TetraVimFetchJvmLspJars", "TetraVim JVM")
    return
  end

  local ft = vim.bo.filetype
  if ft == "java" or ft == "yaml" or ft == "jproperties" or ft == "html" then
    pcall(vim.api.nvim_exec_autocmds, "FileType", { pattern = ft })
  end
  notify.notify_info(
    "Quarkus / MicroProfile LSP enabled (~1 GiB JVM each; open an application.properties / .java buffer to spawn)",
    "TetraVim JVM"
  )
end

local RSS_MARKERS = {
  { label = "jdtls (Java LSP)", pat = "org%.eclipse%.jdt%.ls" },
  { label = "spring-boot LS", pat = "spring%-boot%-language%-server" },
  { label = "quarkus LS", pat = "com%.redhat%.quarkus%.ls" },
  { label = "qute LS", pat = "com%.redhat%.qute%.ls" },
  { label = "lsp4mp (MicroProfile LS)", pat = "org%.eclipse%.lsp4mp%.ls" },
}

--- Live JVM language servers found under `/proc`, with resident memory.
--- Empty off Linux. One entry per matched process.
---@return { label: string, pid: integer, rss_mb: integer|nil }[]
function M.rss_report()
  local out = {}
  if vim.fn.has("linux") ~= 1 then
    return out
  end
  local ok, entries = pcall(vim.fn.readdir, "/proc")
  if not ok then
    return out
  end
  for _, pid in ipairs(entries) do
    if pid:match("^%d+$") then
      local cf = io.open("/proc/" .. pid .. "/cmdline", "r")
      if cf then
        local cmd = (cf:read("*a") or ""):gsub("%z", " ")
        cf:close()
        for _, m in ipairs(RSS_MARKERS) do
          if cmd:find(m.pat) then
            local rss_mb
            local sf = io.open("/proc/" .. pid .. "/status", "r")
            if sf then
              local st = sf:read("*a") or ""
              sf:close()
              local kb = st:match("VmRSS:%s+(%d+)")
              rss_mb = kb and math.floor(tonumber(kb) / 1024) or nil
            end
            out[#out + 1] = { label = m.label, pid = tonumber(pid), rss_mb = rss_mb }
          end
        end
      end
    end
  end
  return out
end

return M
