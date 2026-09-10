-- Kubernetes cluster explorer (item 11) -- tetravim.util.cloud.k8s + tetravim.util.panel.
--
-- The busted child has no cluster and (usually) no kubectl, so behaviour that
-- needs a live `kubectl` is not exercised here: this covers the module surface,
-- that the entry points are total when the CLI is absent, and the static wiring
-- into the keymap / health / docs surfaces.

local function read(path)
  local fh = assert(io.open(path, "r"))
  local body = fh:read("*a")
  fh:close()
  return body
end

describe("tetravim.util.cloud.k8s", function()
  local k8s = require("tetravim.util.cloud.k8s")

  it("exposes open / switch_namespace / switch_context", function()
    assert.is_table(k8s)
    assert.is_function(k8s.open)
    assert.is_function(k8s.switch_namespace)
    assert.is_function(k8s.switch_context)
  end)

  it("open() never throws synchronously (kubectl present or not)", function()
    assert.has_no.errors(function()
      k8s.open()
    end)
  end)

  it("open() warns and returns when kubectl is unavailable", function()
    if vim.fn.executable("kubectl") == 1 then
      return -- can't force the missing-binary branch on a box that has kubectl
    end
    local warned = false
    local ui = require("tetravim.util.ui")
    local orig = ui.notify_warn
    ui.notify_warn = function()
      warned = true
    end
    k8s.open()
    ui.notify_warn = orig
    assert.is_true(warned)
  end)
end)

describe("Kubernetes cluster explorer -- static wiring", function()
  it("core/devops.lua binds <leader>oke to tetravim.util.cloud.k8s.open", function()
    local body = read("lua/tetravim/core/devops.lua")
    assert.is_truthy(body:match('"<leader>oke"'))
    assert.is_truthy(body:match('require%("tetravim%.util%.cloud%.k8s"%)%.open'))
    assert.is_truthy(body:match('desc = "Cluster Explorer"'))
  end)

  it("the healthcheck has the Kubernetes Cluster Explorer section", function()
    assert.is_truthy(require("tetravim.tests.helpers").health_source():match("TetraVim Kubernetes Cluster Explorer"))
  end)

  it("docs/ide-parity.md documents the cluster explorer with <leader>oke", function()
    local body = read("docs/ide-parity.md")
    assert.is_truthy(body:match("Kubernetes tool window"))
    assert.is_truthy(body:match("<leader>oke"))
  end)
end)
