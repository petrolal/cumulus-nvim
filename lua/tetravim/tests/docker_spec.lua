-- Docker / Compose runtime dashboard (item 12) -- tetravim.util.docker +
-- tetravim.util.panel.
--
-- The busted child has no Docker daemon and (usually) no `docker` CLI, so
-- behaviour that needs a live daemon is not exercised: this covers the module
-- surface, that open() is total when the CLI is absent, and the static wiring
-- into the keymap / health / docs surfaces.

local function read(path)
  local fh = assert(io.open(path, "r"))
  local body = fh:read("*a")
  fh:close()
  return body
end

describe("tetravim.util.docker", function()
  local docker = require("tetravim.util.docker")

  it("exposes open()", function()
    assert.is_table(docker)
    assert.is_function(docker.open)
  end)

  it("open() never throws synchronously (docker present or not)", function()
    assert.has_no.errors(function()
      docker.open()
    end)
  end)

  it("open() warns and returns when docker is unavailable", function()
    if vim.fn.executable("docker") == 1 then
      return
    end
    local warned = false
    local ui = require("tetravim.util.ui")
    local orig = ui.notify_warn
    ui.notify_warn = function()
      warned = true
    end
    docker.open()
    ui.notify_warn = orig
    assert.is_true(warned)
  end)
end)

describe("Docker runtime dashboard -- static wiring", function()
  it("core/devops.lua binds <leader>odd to tetravim.util.docker.open", function()
    local body = read("lua/tetravim/core/devops.lua")
    assert.is_truthy(body:match('"<leader>odd"'))
    assert.is_truthy(body:match('require%("tetravim%.util%.docker"%)%.open'))
    assert.is_truthy(body:match('desc = "Runtime Dashboard"'))
  end)

  it("health.lua has the Docker Runtime Dashboard section", function()
    assert.is_truthy(read("lua/tetravim/health.lua"):match("TetraVim Docker Runtime Dashboard"))
  end)

  it("docs/ide-parity.md documents the dashboard with <leader>odd", function()
    local body = read("docs/ide-parity.md")
    assert.is_truthy(body:match("Docker tool window"))
    assert.is_truthy(body:match("<leader>odd"))
  end)
end)
