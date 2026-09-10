-- TetraVim neotest-java JUnit jar bootstrapper
--
-- `neotest-java` needs the "JUnit Platform Console Standalone" jar present under
-- `stdpath("data")/neotest-java/` before it can build a test spec. Upstream only
-- fetches it through the interactive `:NeotestJava setup` (a `vim.ui.select`
-- consent prompt), so on a fresh clone the first `<leader>tr` throws:
--
--   Junit Platform Console Standalone jar not found at .../junit-platform-console-standalone-6.0.3.jar
--
-- This module downloads the pinned jar non-interactively (curl) and verifies its
-- SHA-256 against the value `neotest-java` ships in `default_config.lua`.

local M = {}

-- Keep in sync with neotest-java's LATEST_PINNED_VERSION in default_config.lua.
M.version = "6.0.3"
M.sha256 = "3ba0d6150af79214a1411f9ea2fbef864eef68b68c89a17f672c0b89bff9d3a2"

local function url()
  return ("https://repo1.maven.org/maven2/org/junit/platform/junit-platform-console-standalone/%s/junit-platform-console-standalone-%s.jar"):format(
    M.version,
    M.version
  )
end

function M.jar_path()
  return table.concat({
    vim.fn.stdpath("data"),
    "neotest-java",
    "junit-platform-console-standalone-" .. M.version .. ".jar",
  }, "/")
end

function M.is_installed()
  return vim.fn.filereadable(M.jar_path()) == 1
end

-- Directories that never hold hand-written sources; skipped when sniffing a
-- project so a Kotlin/Scala tree isn't misread as Java because of generated
-- stubs or an unpacked dependency jar under build/.
local PRUNE = {
  [".git"] = true,
  [".gradle"] = true,
  [".mvn"] = true,
  [".idea"] = true,
  ["build"] = true,
  ["target"] = true,
  ["out"] = true,
  ["bin"] = true,
  ["node_modules"] = true,
}

--- Does this directory tree contain any hand-written `.java` source file?
--- neotest-java only supports Java, but its `root_finder` happily claims any
--- Gradle/Maven project -- including Kotlin- or Scala-only ones -- which then
--- blows up in `client_provider` ("No Java file found in the directory").
--- @param dir string project root to sniff
--- @param max_depth integer|nil directory levels to descend (default 8)
--- @return boolean
function M.has_java_sources(dir, max_depth)
  max_depth = max_depth or 8
  local stack = { { path = dir, depth = 0 } }
  while #stack > 0 do
    local cur = table.remove(stack)
    local ok, entries = pcall(vim.fn.readdir, cur.path)
    if ok then
      for _, name in ipairs(entries) do
        local full = cur.path .. "/" .. name
        if name:match("%.java$") and vim.fn.isdirectory(full) == 0 then
          return true
        end
        if
          vim.fn.isdirectory(full) == 1
          and not PRUNE[name]
          and name:sub(1, 1) ~= "."
          and cur.depth + 1 <= max_depth
        then
          stack[#stack + 1] = { path = full, depth = cur.depth + 1 }
        end
      end
    end
  end
  return false
end

-- Which local hashing tool to use, if any. Resolved once.
local function sha_cmd(path)
  if vim.fn.executable("sha256sum") == 1 then
    return { "sha256sum", path }
  end
  if vim.fn.executable("shasum") == 1 then
    return { "shasum", "-a", "256", path }
  end
  return nil
end

local function file_sha256(path)
  local cmd = sha_cmd(path)
  if not cmd then
    return nil
  end
  return (vim.fn.system(cmd):match("^(%x+)"))
end

local function warn(enabled, msg)
  if enabled then
    require("tetravim.util.notify").notify_warn(msg, "TetraVim Test")
  end
end

local function info(enabled, msg)
  if enabled then
    require("tetravim.util.notify").notify_info(msg, "TetraVim Test")
  end
end

-- curl flags shared by both paths: fail on HTTP errors, follow redirects,
-- stay quiet, and -- crucially -- bound how long a dead network / hung
-- proxy can stall the download.
local CURL_ARGS = { "-fsSL", "--connect-timeout", "10", "--max-time", "120", "--create-dirs" }

--- Validate a freshly downloaded jar against the pinned checksum, deleting it
--- and warning on mismatch. `got` is the hex digest already computed by the
--- caller (nil when no hashing tool is available -- treated as "can't verify,
--- keep it").
local function check_or_discard(path, got, notify)
  if got and got:lower() ~= M.sha256 then
    vim.fn.delete(path)
    warn(notify, "neotest-java: JUnit jar checksum mismatch -- download discarded")
    return false
  end
  info(notify, "neotest-java: downloaded JUnit Platform Console Standalone " .. M.version)
  return true
end

--- Blocking download + verify. Used only from the lazy.nvim `build` step,
--- which already runs off the UI thread during `:Lazy sync`.
--- @param notify boolean|nil
--- @return boolean available
function M.ensure_blocking(notify)
  if M.is_installed() then
    return true
  end
  if vim.fn.executable("curl") ~= 1 then
    warn(notify, "neotest-java: curl not found -- run :NeotestJava setup to download the JUnit jar")
    return false
  end

  local path = M.jar_path()
  vim.fn.mkdir(vim.fn.fnamemodify(path, ":h"), "p")
  local args = vim.list_extend({ "curl" }, vim.deepcopy(CURL_ARGS))
  vim.list_extend(args, { "--output", path, url() })
  local out = vim.fn.system(args)
  if vim.v.shell_error ~= 0 then
    vim.fn.delete(path)
    warn(notify, "neotest-java: failed to download the JUnit jar (" .. vim.trim(out) .. ")")
    return false
  end

  return check_or_discard(path, file_sha256(path), notify)
end

--- Ensure the JUnit standalone jar is present, downloading it if missing.
--- Non-blocking: the download and checksum both run through `vim.system`
--- (libuv, off the UI thread), so opening the first Java file never freezes
--- Neovim while ~15 MB comes down from Maven Central. Returns immediately;
--- the optional callback fires with the eventual availability.
--- @param notify boolean|nil emit a single user-facing message on download/failure
--- @param callback fun(available: boolean)|nil
--- @return boolean available_now true only when the jar was already on disk
function M.ensure(notify, callback)
  local function done(ok)
    if callback then
      callback(ok)
    end
  end

  if M.is_installed() then
    done(true)
    return true
  end
  if vim.fn.executable("curl") ~= 1 then
    warn(notify, "neotest-java: curl not found -- run :NeotestJava setup to download the JUnit jar")
    done(false)
    return false
  end

  local path = M.jar_path()
  vim.fn.mkdir(vim.fn.fnamemodify(path, ":h"), "p")
  local args = vim.list_extend({ "curl" }, vim.deepcopy(CURL_ARGS))
  vim.list_extend(args, { "--output", path, url() })

  vim.system(args, { text = true }, function(res)
    if res.code ~= 0 then
      vim.fn.delete(path)
      vim.schedule(function()
        warn(notify, "neotest-java: failed to download the JUnit jar (" .. vim.trim(res.stderr or "") .. ")")
        done(false)
      end)
      return
    end

    local cmd = sha_cmd(path)
    if not cmd then
      vim.schedule(function()
        done(check_or_discard(path, nil, notify))
      end)
      return
    end

    vim.system(cmd, { text = true }, function(sha_res)
      local got = (sha_res.code == 0) and (sha_res.stdout or ""):match("^(%x+)") or nil
      vim.schedule(function()
        done(check_or_discard(path, got, notify))
      end)
    end)
  end)

  return false
end

return M
