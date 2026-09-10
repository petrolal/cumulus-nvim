-- lua/tetravim/tests/ide_parity_spec.lua
--
-- Keeps the three IDE-parity lists from drifting apart:
--   * lua/tetravim/health.lua  -- "IDE-Parity Language Servers" probe (bins on $PATH)
--   * lua/tetravim/plugins/tools-mason.lua -- ensure_installed (Mason package names)
--   * docs/ide-parity.md       -- the human-facing map
--
-- health.lua promises "run :MasonToolsInstall and this server appears". If a
-- probed binary has no corresponding Mason package in ensure_installed, that
-- promise is silently broken -- this spec fails instead.

local function read(path)
  local fh = assert(io.open(path, "r"))
  local body = fh:read("*a")
  fh:close()
  return body
end

-- Executable name (as health.lua probes it) -> Mason package (as ensure_installed
-- lists it). `deno` is intentionally absent: its LSP is the runtime itself, there
-- is no Mason package (see tools-mason.lua + lsp-deno.lua).
local BIN_TO_MASON = {
  ["basedpyright-langserver"] = "basedpyright",
  ["ruff"] = "ruff",
  ["sql-language-server"] = "sqlls",
  ["vue-language-server"] = "vue-language-server",
  ["svelteserver"] = "svelte-language-server",
  ["astro-ls"] = "astro-language-server",
  ["ngserver"] = "angular-language-server",
  ["prisma-language-server"] = "prisma-language-server",
  ["marksman"] = "marksman",
  ["vscode-eslint-language-server"] = "eslint-lsp",
  ["tailwindcss-language-server"] = "tailwindcss-language-server",
  ["emmet-language-server"] = "emmet-language-server",
  ["djlint"] = "djlint",
  ["ltex-ls"] = "ltex-ls",
}
local RUNTIME_PROVIDED = { deno = true }

describe("IDE-parity server lists stay in sync", function()
  -- ensure_installed straight from the live spec (no source parsing).
  local mason_spec = require("tetravim.plugins.tools-mason")
  local ensure_installed
  for _, s in ipairs(mason_spec) do
    if s.opts and s.opts.ensure_installed then
      ensure_installed = s.opts.ensure_installed
    end
  end
  local mason_set = {}
  for _, pkg in ipairs(ensure_installed or {}) do
    mason_set[pkg] = true
  end

  -- Bins from the "IDE-Parity Language Servers" block of the healthcheck.
  local health_src = require("tetravim.tests.helpers").health_source()
  local parity_block = health_src:match(
    'vim%.health%.start%("TetraVim IDE%-Parity Language Servers.-vim%.health%.start%('
  ) or ""
  local probed_bins = {}
  for bin in parity_block:gmatch('bin%s*=%s*"([^"]+)"') do
    probed_bins[#probed_bins + 1] = bin
  end

  it("health.lua actually has an IDE-parity language-server block", function()
    assert.is_true(#probed_bins > 5, "parity block not found / not parsed in health.lua")
  end)

  it("every probed binary is either Mason-installable or runtime-provided", function()
    local missing = {}
    for _, bin in ipairs(probed_bins) do
      if not RUNTIME_PROVIDED[bin] then
        local pkg = BIN_TO_MASON[bin]
        if not pkg then
          missing[#missing + 1] = bin .. " (no bin->Mason mapping in this spec)"
        elseif not mason_set[pkg] then
          missing[#missing + 1] = bin .. " -> " .. pkg .. " (not in ensure_installed)"
        end
      end
    end
    assert.are.equal(0, #missing, "parity servers not covered by Mason:\n  " .. table.concat(missing, "\n  "))
  end)

  it("every mapped Mason parity package is still in ensure_installed", function()
    local gone = {}
    for _, pkg in pairs(BIN_TO_MASON) do
      if not mason_set[pkg] then
        gone[#gone + 1] = pkg
      end
    end
    assert.are.equal(0, #gone, "packages dropped from ensure_installed:\n  " .. table.concat(gone, "\n  "))
  end)

  it("docs/ide-parity.md exists and references the healthcheck section", function()
    local doc = read("docs/ide-parity.md")
    assert.is_truthy(doc:find("IDE-Parity Language Servers", 1, true), "doc no longer points at the health section")
  end)
end)
