-- TetraVim Docker / Compose runtime dashboard  (tetravim.util.cloud.docker)
--
-- A docked, refreshable list of containers and images for the local Docker
-- daemon -- the native answer to IDEA Ultimate's "Services" / Docker tool
-- window. Driven entirely by the `docker` CLI (no daemon socket client, no
-- extra plugin); `docker ps` / `docker images` are read asynchronously with
-- `vim.system` and rendered through the shared tetravim.util.panel substrate.
--
--   <CR>  docker inspect the row under the cursor (into a split)
--   l     follow logs for the container under the cursor (terminal)
--   s     start OR stop the container under the cursor (smart toggle), refresh
--   R     restart the container under the cursor, then refresh
--   e     exec a shell in the container under the cursor (terminal)
--   d     remove the container / image under the cursor (confirm first), refresh
--   u     docker compose up -d   at the nearest compose root
--   U     docker compose down    at the nearest compose root
--   r     refresh          q  close

local panel = require("tetravim.util.panel")
local split = require("tetravim.util.split")
local term = require("tetravim.util.term")
local ui = require("tetravim.util.ui")

local M = {}

local NAME_HINT = "tetravim-docker"

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

--- Decode `docker ... --format {{json .}}` NDJSON output into a list of tables,
--- silently skipping any line that will not parse.
local function decode_ndjson(stdout)
  local rows = {}
  for line in (stdout or ""):gmatch("[^\n]+") do
    local ok, obj = pcall(vim.json.decode, line)
    if ok and type(obj) == "table" then
      rows[#rows + 1] = obj
    end
  end
  return rows
end

--- Run `docker <args>` and hand stdout (or the error text) to the shared split.
local function docker_show(args, filetype)
  local argv = { "docker" }
  vim.list_extend(argv, args)
  vim.system(argv, { text = true, timeout = 15000 }, function(res)
    vim.schedule(function()
      local body
      if res.code == 124 then
        body = "docker timed out: docker " .. table.concat(args, " ")
      elseif res.code ~= 0 then
        body = trim(res.stderr) ~= "" and trim(res.stderr) or trim(res.stdout)
        if body == "" then
          body = "docker exited " .. tostring(res.code)
        end
      else
        body = res.stdout or ""
      end
      split.open(body, { filetype = filetype, name_hint = "tetravim-docker-detail" })
    end)
  end)
end

--- Run a one-shot `docker <args>` lifecycle command, then refresh the panel.
local function docker_action(args, ok_msg, ctx)
  local argv = { "docker" }
  vim.list_extend(argv, args)
  vim.system(argv, { text = true, timeout = 30000 }, function(res)
    vim.schedule(function()
      if res.code == 0 then
        if ok_msg then
          ui.notify_info(ok_msg)
        end
      else
        ui.notify_err(trim(res.stderr) ~= "" and trim(res.stderr) or ("docker " .. args[1] .. " failed"))
      end
      if ctx and ctx.refresh then
        ctx.refresh()
      end
    end)
  end)
end

local function container_running(state)
  state = (state or ""):lower()
  return state == "running" or state == "paused" or state == "restarting"
end

--- `.Ports` from `docker ps` is a long comma string; keep it short for the row.
local function short_ports(p)
  p = trim(p)
  if p == "" then
    return ""
  end
  if #p > 34 then
    return p:sub(1, 31) .. "..."
  end
  return p
end

local function build_rows(containers, images)
  local rows = {}

  rows[#rows + 1] = { text = string.format("▸ Containers (%d)", #containers) }
  if #containers == 0 then
    rows[#rows + 1] = { text = "    (none)" }
  end
  table.sort(containers, function(a, b)
    return (a.Names or "") < (b.Names or "")
  end)
  for _, c in ipairs(containers) do
    local running = container_running(c.State)
    local mark = running and "●" or "○"
    rows[#rows + 1] = {
      text = string.format(
        "    %s %-30s %-24s %s",
        mark,
        c.Names or "?",
        (c.Image or ""):sub(1, 24),
        short_ports(c.Ports)
      ),
      item = { type = "container", id = c.ID, name = c.Names, image = c.Image, running = running },
    }
  end

  rows[#rows + 1] = { text = "" }
  rows[#rows + 1] = { text = string.format("▸ Images (%d)", #images) }
  if #images == 0 then
    rows[#rows + 1] = { text = "    (none)" }
  end
  table.sort(images, function(a, b)
    return ((a.Repository or "") .. (a.Tag or "")) < ((b.Repository or "") .. (b.Tag or ""))
  end)
  for _, im in ipairs(images) do
    local ref = (im.Repository or "<none>") .. ":" .. (im.Tag or "<none>")
    rows[#rows + 1] = {
      text = string.format("    %-46s %-14s %s", ref, im.ID or "", im.Size or ""),
      item = { type = "image", id = im.ID, ref = ref },
    }
  end

  return rows
end

local function inspect(item)
  if not item or not item.id then
    return
  end
  docker_show({ "inspect", item.id }, "json")
end

local function logs(item)
  if not item or item.type ~= "container" then
    ui.notify_warn("logs: put the cursor on a container row")
    return
  end
  term.run_term(sh({ "docker", "logs", "-f", "--tail", "200", item.name or item.id }), {
    title = "docker logs " .. (item.name or item.id),
  })
end

local function exec_shell(item)
  if not item or item.type ~= "container" then
    ui.notify_warn("exec: put the cursor on a container row")
    return
  end
  if not item.running then
    ui.notify_warn("exec: container is not running")
    return
  end
  term.run_term(sh({ "docker", "exec", "-it", item.name or item.id, "/bin/sh" }), {
    title = "docker exec " .. (item.name or item.id),
  })
end

local function toggle(item, ctx)
  if not item or item.type ~= "container" then
    ui.notify_warn("start/stop: put the cursor on a container row")
    return
  end
  local verb = item.running and "stop" or "start"
  docker_action({ verb, item.name or item.id }, verb .. " " .. (item.name or item.id), ctx)
end

local function restart(item, ctx)
  if not item or item.type ~= "container" then
    ui.notify_warn("restart: put the cursor on a container row")
    return
  end
  docker_action({ "restart", item.name or item.id }, "restart " .. (item.name or item.id), ctx)
end

local function remove(item, ctx)
  if not item then
    return
  end
  if item.type == "container" then
    if vim.fn.confirm("Remove container " .. (item.name or item.id) .. "?", "&Yes\n&No", 2) ~= 1 then
      return
    end
    local args = item.running and { "rm", "-f", item.name or item.id } or { "rm", item.name or item.id }
    docker_action(args, "removed " .. (item.name or item.id), ctx)
  elseif item.type == "image" then
    if vim.fn.confirm("Remove image " .. (item.ref or item.id) .. "?", "&Yes\n&No", 2) ~= 1 then
      return
    end
    docker_action({ "rmi", item.id }, "removed image " .. (item.ref or item.id), ctx)
  end
end

--- Resolve the nearest compose root via the shared devops finder.
local function compose_root()
  local ok, devops = pcall(require, "tetravim.core.devops")
  if not ok then
    return nil
  end
  return devops.find_docker_root()
end

local function compose(subcmd)
  local root = compose_root()
  if not root then
    ui.notify_warn("no compose file (compose.yaml / docker-compose.yml) found in the workspace")
    return
  end
  term.run_term("docker compose " .. subcmd, { cwd = root, title = "docker compose " .. subcmd })
end

--- Entry point (`<leader>odd`). Guards `docker`, then fetches containers +
--- images asynchronously and renders them.
function M.open()
  if vim.fn.executable("docker") ~= 1 then
    ui.notify_warn("docker not found on $PATH -- install Docker to use the runtime dashboard")
    return
  end

  vim.system(
    { "docker", "ps", "-a", "--no-trunc", "--format", "{{json .}}" },
    { text = true, timeout = 15000 },
    function(ps_res)
      vim.system({ "docker", "images", "--format", "{{json .}}" }, { text = true, timeout = 15000 }, function(im_res)
        vim.schedule(function()
          local daemon_err
          if ps_res.code == 124 then
            daemon_err = "docker ps timed out"
          elseif ps_res.code ~= 0 then
            daemon_err = trim(ps_res.stderr) ~= "" and trim(ps_res.stderr) or "docker daemon unreachable"
          end

          local containers = ps_res.code == 0 and decode_ndjson(ps_res.stdout) or {}
          local images = im_res.code == 0 and decode_ndjson(im_res.stdout) or {}

          local header = {
            "TetraVim Docker  ·  " .. #containers .. " container(s), " .. #images .. " image(s)",
            "<CR> inspect  l logs  s start/stop  R restart  e shell  d rm  u compose-up  U compose-down",
            "r refresh   q close",
            "",
          }
          if daemon_err then
            header[#header + 1] = "docker error: " .. daemon_err
          end

          panel.render({
            name_hint = NAME_HINT,
            filetype = "tetravim-docker",
            header = header,
            rows = build_rows(containers, images),
            on_select = function(item)
              inspect(item)
            end,
            refresh = function()
              M.open()
            end,
            keymaps = {
              l = function(item)
                logs(item)
              end,
              s = function(item, ctx)
                toggle(item, ctx)
              end,
              R = function(item, ctx)
                restart(item, ctx)
              end,
              e = function(item)
                exec_shell(item)
              end,
              d = function(item, ctx)
                remove(item, ctx)
              end,
              u = function()
                compose("up -d")
              end,
              U = function()
                compose("down")
              end,
            },
          })
        end)
      end)
    end
  )
end

return M
