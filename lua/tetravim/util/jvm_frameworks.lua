-- TetraVim JVM framework language-server path resolver
--
-- Spring Boot, Quarkus and MicroProfile ship their editor intelligence as
-- VS Code extensions, not as plain LSP servers:
--
--   * Spring Boot LS  -> Mason package `vscode-spring-boot-tools`
--                        (`application.{properties,yml}` completion,
--                        `@ConfigurationProperties` metadata, bean navigation)
--   * Quarkus / lsp4mp -> Red Hat `vscode-quarkus` + `vscode-microprofile`
--                        `.vsix` bundles -- NOT in Mason. `scripts/
--                        fetch-jvm-lsp-jars.sh` downloads them from Open VSX
--                        into `$TETRAVIM_JVM_LSP_DIR` (default
--                        `stdpath("data")/tetravim/jvm-lsp`) laid out as:
--
--                          <dir>/quarkus/server/com.redhat.qute.ls-uber.jar
--                          <dir>/quarkus/server/com.redhat.quarkus.ls.jar
--                          <dir>/quarkus/jars/*.jar        (JDT extensions)
--                          <dir>/microprofile/server/org.eclipse.lsp4mp.ls-uber.jar
--                          <dir>/microprofile/jars/*.jar   (JDT extensions)
--
-- This module resolves those paths and reports readiness so the plugin specs
-- (`lsp-spring-boot.lua`, `lsp-quarkus.lua`), `ftplugin/java.lua` (jdtls
-- `bundles`) and `:checkhealth tetravim` can all degrade gracefully when the
-- tooling is not installed.

local M = {}

--- Base directory the Quarkus / MicroProfile jars are unpacked into.
---@return string
function M.dir()
  local override = vim.env.TETRAVIM_JVM_LSP_DIR
  if override and override ~= "" then
    return vim.fn.expand(override)
  end
  return vim.fn.stdpath("data") .. "/tetravim/jvm-lsp"
end

--- Absolute `java` binary from the distro's JDK 21 discovery, or nil to let the
--- plugin fall back to `$JAVA_HOME/bin/java` / `java` on `$PATH`.
---@return string|nil
function M.java_cmd()
  local ok, jvm = pcall(require, "tetravim.util.jvm")
  if not ok or type(jvm.find_java21_home) ~= "function" then
    return nil
  end
  local home = jvm.find_java21_home()
  if not home or home == "" then
    return nil
  end
  local bin = home .. "/bin/java"
  if vim.fn.executable(bin) == 1 then
    return bin
  end
  return nil
end

local function readable(path)
  return vim.fn.filereadable(path) == 1
end

--- Paths to feed `require("quarkus").setup{}`.
--- Returns nil when the `vscode-quarkus` jars have not been fetched.
---@return { ls_path: string, jdt_extensions_path: string, microprofile_ext_path: string }|nil
function M.quarkus_paths()
  local server = M.dir() .. "/quarkus/server"
  if not readable(server .. "/com.redhat.qute.ls-uber.jar") then
    return nil
  end
  if not readable(server .. "/com.redhat.quarkus.ls.jar") then
    return nil
  end
  return {
    ls_path = server,
    jdt_extensions_path = M.dir() .. "/quarkus/jars",
    microprofile_ext_path = server,
  }
end

--- Paths to feed `require("microprofile").setup{}`.
--- Returns nil when the `vscode-microprofile` jars have not been fetched.
---@return { ls_path: string, jdt_extensions_path: string }|nil
function M.microprofile_paths()
  local server = M.dir() .. "/microprofile/server"
  if not readable(server .. "/org.eclipse.lsp4mp.ls-uber.jar") then
    return nil
  end
  return {
    ls_path = server,
    jdt_extensions_path = M.dir() .. "/microprofile/jars",
  }
end

--- The Quarkus stack needs BOTH bundles: lsp4mp is the property-completion
--- engine and `com.redhat.quarkus.ls.jar` layers the `quarkus.*` namespace on
--- top of it.
---@return boolean
function M.quarkus_ready()
  return M.quarkus_paths() ~= nil and M.microprofile_paths() ~= nil
end

--- Locate the Spring Boot language-server jar installed by Mason.
---@return string|nil
function M.spring_boot_ls_jar()
  local candidates = {
    vim.fn.expand("~/.local/share/nvim/mason/share/vscode-spring-boot-tools/language-server.jar"),
  }
  local pkg = vim.fn.expand("~/.local/share/nvim/mason/packages/vscode-spring-boot-tools")
  if vim.fn.isdirectory(pkg) == 1 then
    for _, hit in ipairs(vim.fn.glob(pkg .. "/**/spring-boot-language-server*.jar", true, true)) do
      table.insert(candidates, hit)
    end
    for _, hit in ipairs(vim.fn.glob(pkg .. "/**/language-server.jar", true, true)) do
      table.insert(candidates, hit)
    end
  end
  for _, path in ipairs(candidates) do
    if readable(path) then
      return path
    end
  end
  return nil
end

---@return boolean
function M.spring_boot_ready()
  return M.spring_boot_ls_jar() ~= nil
end

--- Fetch and unpack the Quarkus and MicroProfile language server bundles from Open VSX.
--- Can run synchronously (opts.sync = true) or asynchronously in the background.
---@param opts? { force?: boolean, sync?: boolean, silent?: boolean }
---@param on_complete? fun(ok: boolean, msg: string)
---@return boolean, string
function M.fetch_jars(opts, on_complete)
  opts = opts or {}
  local force = opts.force or false
  local sync = opts.sync or false
  local silent = opts.silent or false

  local function notify(msg, level)
    if not silent then
      vim.notify("[TetraVim JVM LSP] " .. msg, level or vim.log.levels.INFO)
    end
  end

  for _, bin in ipairs({ "curl", "unzip" }) do
    if vim.fn.executable(bin) ~= 1 then
      local err = string.format("'%s' is not executable on $PATH -- cannot fetch JVM LSP jars.", bin)
      notify(err, vim.log.levels.WARN)
      if on_complete then
        on_complete(false, err)
      end
      return false, err
    end
  end

  local function exec_cmd(cmd_array)
    local co = coroutine.running()
    if not co or sync then
      return vim.system(cmd_array, { text = true }):wait()
    end
    vim.system(cmd_array, { text = true }, function(res)
      vim.schedule(function()
        coroutine.resume(co, res)
      end)
    end)
    return coroutine.yield()
  end

  local base_dir = M.dir()
  vim.fn.mkdir(base_dir, "p")

  local function runner()
    local tmp_dir = vim.fn.tempname() .. "_jvm_lsp"
    vim.fn.mkdir(tmp_dir, "p")

    local extensions = {
      {
        slug = "quarkus",
        ns = "redhat",
        name = "vscode-quarkus",
        version = vim.env.TETRAVIM_QUARKUS_VERSION or "latest",
        title = "Quarkus Language Server",
      },
      {
        slug = "microprofile",
        ns = "redhat",
        name = "vscode-microprofile",
        version = vim.env.TETRAVIM_MICROPROFILE_VERSION or "latest",
        title = "MicroProfile Language Server",
      },
    }

    local any_failed = false

    for _, ext in ipairs(extensions) do
      local dest = base_dir .. "/" .. ext.slug
      local stamp = dest .. "/.version"

      local api_url = string.format("https://open-vsx.org/api/%s/%s/%s", ext.ns, ext.name, ext.version)
      local meta_res = exec_cmd({ "curl", "-fsSL", api_url })

      if not meta_res or meta_res.code ~= 0 or not meta_res.stdout or meta_res.stdout == "" then
        notify(
          string.format("Could not resolve %s (%s) on Open VSX -- skipping.", ext.name, ext.version),
          vim.log.levels.WARN
        )
        any_failed = true
      else
        local ok_json, meta = pcall(vim.json.decode, meta_res.stdout)
        if not ok_json or not meta then
          notify(string.format("Failed to parse Open VSX metadata for %s", ext.name), vim.log.levels.WARN)
          any_failed = true
        else
          local rver = meta.version or ext.version
          local dl_url = (meta.files and meta.files.download) or meta.download
          if not dl_url or dl_url == "" then
            notify(string.format("No download URL found for %s %s", ext.name, rver), vim.log.levels.WARN)
            any_failed = true
          else
            local is_up_to_date = false
            if not force and vim.fn.filereadable(stamp) == 1 then
              local f = io.open(stamp, "r")
              if f then
                local current_ver = vim.trim(f:read("*a") or "")
                f:close()
                if current_ver == rver then
                  is_up_to_date = true
                end
              end
            end

            if is_up_to_date then
              notify(string.format("%s: already at %s (up to date)", ext.title, rver), vim.log.levels.INFO)
            else
              notify(string.format("%s: downloading %s %s...", ext.title, ext.name, rver), vim.log.levels.INFO)
              local vsix_file = tmp_dir .. "/" .. ext.slug .. ".vsix"
              local dl_res = exec_cmd({ "curl", "-fsSL", "-o", vsix_file, dl_url })
              if not dl_res or dl_res.code ~= 0 then
                notify(string.format("Download failed for %s (%s)", ext.name, dl_url), vim.log.levels.WARN)
                any_failed = true
              else
                local unpack_dir = tmp_dir .. "/" .. ext.slug
                vim.fn.delete(unpack_dir, "rf")
                vim.fn.mkdir(unpack_dir, "p")

                exec_cmd({ "unzip", "-qq", vsix_file, "extension/server/*", "extension/jars/*", "-d", unpack_dir })

                local server_dir = unpack_dir .. "/extension/server"
                if vim.fn.isdirectory(server_dir) ~= 1 then
                  notify(string.format("%s: no extension/server/ found in archive", ext.title), vim.log.levels.WARN)
                  any_failed = true
                else
                  vim.fn.delete(dest, "rf")
                  vim.fn.mkdir(dest, "p")
                  exec_cmd({ "mv", server_dir, dest .. "/server" })

                  local jars_dir = unpack_dir .. "/extension/jars"
                  if vim.fn.isdirectory(jars_dir) == 1 then
                    exec_cmd({ "mv", jars_dir, dest .. "/jars" })
                  else
                    vim.fn.mkdir(dest .. "/jars", "p")
                  end

                  local f = io.open(stamp, "w")
                  if f then
                    f:write(rver .. "\n")
                    f:close()
                  end
                  notify(string.format("%s: installed %s -> %s", ext.title, rver, dest), vim.log.levels.INFO)
                end
              end
            end
          end
        end
      end
    end

    vim.fn.delete(tmp_dir, "rf")

    local success = not any_failed
    local msg = success and "Quarkus / MicroProfile language servers are ready."
      or "One or more JVM LSP bundles failed to install."
    notify(msg, success and vim.log.levels.INFO or vim.log.levels.WARN)

    if on_complete then
      on_complete(success, msg)
    end
    return success, msg
  end

  if sync then
    return runner()
  else
    coroutine.wrap(runner)()
    return true, "JVM LSP installation started in background"
  end
end

return M
