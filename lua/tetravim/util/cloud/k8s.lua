-- TetraVim Kubernetes cluster explorer  (tetravim.util.cloud.k8s)
--
-- A docked, refreshable resource tree for the active kube-context -- the
-- native answer to IDEA Ultimate's "Kubernetes" tool window. Everything is
-- driven by the `kubectl` CLI (no client library, no extra plugin); results
-- are fetched asynchronously with `vim.system` and rendered through the shared
-- tetravim.util.panel substrate.
--
-- Layout: one group per kind (Deployment / Pod / Service) for the current
-- namespace, with the live context + namespace shown in the header.
--
--   <CR>  kubectl describe the row under the cursor (into a split)
--   y     kubectl get -o yaml the row under the cursor
--   l     follow logs for the Pod under the cursor (terminal)
--   x     exec a shell in the Pod under the cursor (terminal)
--   d     kubectl delete the row under the cursor (confirm first), then refresh
--   s     switch namespace (picker)
--   c     switch kube-context (picker)
--   r     refresh          q  close

local panel = require("tetravim.util.panel")
local split = require("tetravim.util.split")
local term = require("tetravim.util.term")
local ui = require("tetravim.util.ui")

local M = {}

local NAME_HINT = "tetravim-k8s"
local KINDS = { "Deployment", "Pod", "Service" }

--- Namespace override chosen via `s`; nil means "use the context default".
M._namespace = nil

--- kubectl argv -> shell string, each token individually escaped (mirrors the
--- convention in tetravim.core.devops).
local function sh(parts)
  local out = {}
  for _, p in ipairs(parts) do
    out[#out + 1] = vim.fn.shellescape(p)
  end
  return table.concat(out, " ")
end

local function trim(s)
  return (s or ""):gsub("%s+$", "")
end

--- Run `kubectl <args>` for JSON, hand the decoded table (or nil + message) to
--- `cb` on the main loop.
local function kubectl_json(args, cb)
  local argv = { "kubectl" }
  vim.list_extend(argv, args)
  vim.system(argv, { text = true, timeout = 15000 }, function(res)
    vim.schedule(function()
      if res.code == 124 then
        cb(nil, "kubectl timed out: kubectl " .. table.concat(args, " "))
        return
      end
      if res.code ~= 0 then
        cb(nil, trim(res.stderr) ~= "" and trim(res.stderr) or "kubectl exited " .. tostring(res.code))
        return
      end
      local ok, decoded = pcall(vim.json.decode, res.stdout or "")
      if not ok or type(decoded) ~= "table" then
        cb(nil, "could not parse kubectl JSON output")
        return
      end
      cb(decoded, nil)
    end)
  end)
end

--- Run `kubectl <args>` for text and drop stdout (or the error text) into the
--- shared detail split.
local function kubectl_show(args, filetype)
  local argv = { "kubectl" }
  vim.list_extend(argv, args)
  vim.system(argv, { text = true, timeout = 15000 }, function(res)
    vim.schedule(function()
      local body
      if res.code == 124 then
        body = "kubectl timed out: kubectl " .. table.concat(args, " ")
      elseif res.code ~= 0 then
        body = trim(res.stderr) ~= "" and trim(res.stderr) or trim(res.stdout)
        if body == "" then
          body = "kubectl exited " .. tostring(res.code)
        end
      else
        body = res.stdout or ""
      end
      split.open(body, { filetype = filetype, name_hint = "tetravim-k8s-detail" })
    end)
  end)
end

--- One-line summary for a resource row.
local function row_text(item)
  local name = (item.metadata and item.metadata.name) or "?"
  if item.kind == "Pod" then
    local phase = (item.status and item.status.phase) or "?"
    local cs = (item.status and item.status.containerStatuses) or {}
    local ready, restarts = 0, 0
    for _, c in ipairs(cs) do
      if c.ready then
        ready = ready + 1
      end
      restarts = restarts + (c.restartCount or 0)
    end
    return string.format("%-44s %-10s %d/%d  restarts=%d", name, phase, ready, #cs, restarts)
  elseif item.kind == "Deployment" then
    local st = item.status or {}
    local spec = item.spec or {}
    return string.format("%-44s ready %s/%s", name, st.readyReplicas or 0, spec.replicas or 0)
  elseif item.kind == "Service" then
    local spec = item.spec or {}
    local ports = {}
    for _, p in ipairs(spec.ports or {}) do
      ports[#ports + 1] = tostring(p.port) .. (p.nodePort and (":" .. tostring(p.nodePort)) or "")
    end
    return string.format(
      "%-44s %-12s %-15s [%s]",
      name,
      spec.type or "ClusterIP",
      spec.clusterIP or "-",
      table.concat(ports, ",")
    )
  end
  return name
end

--- Bucket the mixed `kubectl get pods,deployments,services` item list into the
--- interleaved { text, item } rows panel.render wants.
local function build_rows(items, ns)
  local buckets = {}
  for _, k in ipairs(KINDS) do
    buckets[k] = {}
  end
  for _, it in ipairs(items) do
    if buckets[it.kind] then
      table.insert(buckets[it.kind], it)
    end
  end

  local rows = {}
  for _, kind in ipairs(KINDS) do
    local list = buckets[kind]
    table.sort(list, function(a, b)
      return ((a.metadata or {}).name or "") < ((b.metadata or {}).name or "")
    end)
    if #rows > 0 then
      rows[#rows + 1] = { text = "" }
    end
    rows[#rows + 1] = { text = string.format("▸ %s (%d)", kind, #list) }
    if #list == 0 then
      rows[#rows + 1] = { text = "    (none)" }
    end
    for _, it in ipairs(list) do
      rows[#rows + 1] = {
        text = "    " .. row_text(it),
        item = {
          kind = kind,
          name = (it.metadata or {}).name,
          namespace = (it.metadata or {}).namespace or ns,
        },
      }
    end
  end
  return rows
end

local function describe(item)
  if not item or not item.name then
    return
  end
  kubectl_show({ "describe", item.kind:lower(), item.name, "-n", item.namespace }, "text")
end

local function show_yaml(item)
  if not item or not item.name then
    return
  end
  kubectl_show({ "get", item.kind:lower(), item.name, "-n", item.namespace, "-o", "yaml" }, "yaml")
end

local function logs(item)
  if not item or not item.name then
    return
  end
  if item.kind ~= "Pod" then
    ui.notify_warn("logs: put the cursor on a Pod row")
    return
  end
  term.run_term(sh({ "kubectl", "logs", "-f", "--tail", "200", item.name, "-n", item.namespace }), {
    title = "kubectl logs " .. item.name,
  })
end

local function exec_shell(item)
  if not item or not item.name then
    return
  end
  if item.kind ~= "Pod" then
    ui.notify_warn("exec: put the cursor on a Pod row")
    return
  end
  term.run_term(
    sh({ "kubectl", "exec", "-it", item.name, "-n", item.namespace, "--", "/bin/sh" }),
    { title = "kubectl exec " .. item.name }
  )
end

local function delete(item, ctx)
  if not item or not item.name then
    return
  end
  local prompt = string.format("Delete %s/%s in namespace %s?", item.kind, item.name, item.namespace)
  if vim.fn.confirm(prompt, "&Yes\n&No", 2) ~= 1 then
    return
  end
  vim.system(
    { "kubectl", "delete", item.kind:lower(), item.name, "-n", item.namespace },
    { text = true, timeout = 30000 },
    function(res)
      vim.schedule(function()
        if res.code == 0 then
          ui.notify_info(string.format("deleted %s/%s", item.kind, item.name))
        else
          ui.notify_err(trim(res.stderr) ~= "" and trim(res.stderr) or "kubectl delete failed")
        end
        if ctx and ctx.refresh then
          ctx.refresh()
        end
      end)
    end
  )
end

--- Pick a new namespace from `kubectl get namespaces` and re-open.
function M.switch_namespace()
  vim.system({ "kubectl", "get", "namespaces", "-o", "name" }, { text = true, timeout = 10000 }, function(res)
    vim.schedule(function()
      if res.code ~= 0 then
        ui.notify_err(
          "could not list namespaces: " .. (trim(res.stderr) ~= "" and trim(res.stderr) or "kubectl failed")
        )
        return
      end
      local names = {}
      for line in (res.stdout or ""):gmatch("[^\n]+") do
        names[#names + 1] = (line:gsub("^namespace/", ""))
      end
      if #names == 0 then
        ui.notify_warn("no namespaces returned")
        return
      end
      vim.ui.select(names, { prompt = "Kubernetes namespace" }, function(choice)
        if not choice then
          return
        end
        M._namespace = choice
        M.open()
      end)
    end)
  end)
end

--- Pick a new kube-context, `use-context` it, and re-open at its default ns.
function M.switch_context()
  vim.system({ "kubectl", "config", "get-contexts", "-o", "name" }, { text = true, timeout = 10000 }, function(res)
    vim.schedule(function()
      if res.code ~= 0 then
        ui.notify_err("could not list contexts")
        return
      end
      local names = {}
      for line in (res.stdout or ""):gmatch("[^\n]+") do
        names[#names + 1] = line
      end
      if #names == 0 then
        ui.notify_warn("no kube-contexts configured")
        return
      end
      vim.ui.select(names, { prompt = "kube-context" }, function(choice)
        if not choice then
          return
        end
        vim.system({ "kubectl", "config", "use-context", choice }, { text = true, timeout = 10000 }, function(sw)
          vim.schedule(function()
            if sw.code ~= 0 then
              ui.notify_err("use-context failed: " .. (trim(sw.stderr) ~= "" and trim(sw.stderr) or "kubectl failed"))
              return
            end
            M._namespace = nil
            ui.notify_info("kube-context -> " .. choice)
            M.open()
          end)
        end)
      end)
    end)
  end)
end

--- Resolve the namespace to show: the `s`-picker override, else the context
--- default (`kubectl config view --minify`), else "default".
local function resolve_namespace(cb)
  if M._namespace and M._namespace ~= "" then
    cb(M._namespace)
    return
  end
  vim.system(
    { "kubectl", "config", "view", "--minify", "--output", "jsonpath={..namespace}" },
    { text = true, timeout = 5000 },
    function(res)
      vim.schedule(function()
        local ns = res.code == 0 and trim(res.stdout) or ""
        cb(ns ~= "" and ns or "default")
      end)
    end
  )
end

--- Entry point (`<leader>oke`). Guards `kubectl`, resolves context + namespace,
--- then fetches and renders the resource tree.
function M.open()
  if vim.fn.executable("kubectl") ~= 1 then
    ui.notify_warn("kubectl not found on $PATH -- install kubectl to use the Kubernetes explorer")
    return
  end

  vim.system({ "kubectl", "config", "current-context" }, { text = true, timeout = 5000 }, function(ctx_res)
    vim.schedule(function()
      local context = ctx_res.code == 0 and trim(ctx_res.stdout) or nil
      if not context or context == "" then
        context = "(no current context)"
      end

      resolve_namespace(function(ns)
        kubectl_json({ "get", "pods,deployments,services", "-n", ns, "-o", "json" }, function(data, err)
          local items = (data and data.items) or {}
          local header = {
            "TetraVim Kubernetes  ·  " .. context,
            "namespace: " .. ns .. "   resources: " .. #items,
            "<CR> describe   y yaml   l logs   x shell   d delete   s ns   c ctx   r refresh   q close",
            "",
          }
          if err then
            header[#header + 1] = "kubectl error: " .. err
          elseif #items == 0 then
            header[#header + 1] = "No Deployments / Pods / Services in this namespace."
          end

          panel.render({
            name_hint = NAME_HINT,
            filetype = "tetravim-k8s",
            header = header,
            rows = build_rows(items, ns),
            on_select = function(item)
              describe(item)
            end,
            refresh = function()
              M.open()
            end,
            keymaps = {
              y = function(item)
                show_yaml(item)
              end,
              l = function(item)
                logs(item)
              end,
              x = function(item)
                exec_shell(item)
              end,
              d = function(item, pctx)
                delete(item, pctx)
              end,
              s = function()
                M.switch_namespace()
              end,
              c = function()
                M.switch_context()
              end,
            },
          })
        end)
      end)
    end)
  end)
end

return M
