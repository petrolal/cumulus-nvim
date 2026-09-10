-- TetraVim Healthcheck entry point (`:checkhealth tetravim`).
--
-- Was a single 1200-line `M.check()` in lua/tetravim/health.lua; that function
-- is now split into the sibling modules below, one per concern group. Each
-- exposes its own `M.check()` and is invoked here in the original order, so the
-- rendered report is byte-for-byte the same. Tests still call
-- `require("tetravim.health").check()`.

local M = {}

local SECTIONS = {
  "tetravim.health.platform",
  "tetravim.health.jvm",
  "tetravim.health.devops",
  "tetravim.health.clients",
  "tetravim.health.quality",
  "tetravim.health.editor",
}

--- Load one section module, retrying once through a purged loader cache.
--- `vim.loader` (enabled in init.lua) keeps a compiled-chunk cache; a stale or
--- half-written entry -- e.g. two headless test jobs racing to warm a cold cache
--- for the same freshly-added file -- can make `require` hand back `true` instead
--- of the module table. Dropping the cache entry + `package.loaded` and requiring
--- again recompiles from source.
local function load_section(mod)
  local ok, section = pcall(require, mod)
  if ok and type(section) == "table" and type(section.check) == "function" then
    return section
  end
  package.loaded[mod] = nil
  if type(vim.loader) == "table" and type(vim.loader.reset) == "function" then
    pcall(vim.loader.reset, mod)
  end
  ok, section = pcall(require, mod)
  if ok and type(section) == "table" and type(section.check) == "function" then
    return section
  end
  return nil, section
end

function M.check()
  for _, mod in ipairs(SECTIONS) do
    local section, err = load_section(mod)
    if section then
      section.check()
    else
      vim.health.start(mod)
      vim.health.error("failed to load health section: " .. tostring(err))
    end
  end
end

return M
