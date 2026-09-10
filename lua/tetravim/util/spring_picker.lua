-- TetraVim Spring Boot Telescope Pickers (Story 2.3)
-- First-class Telescope pickers for REST endpoints and Spring Beans with dependency preview,
-- and Spring Boot application detection.

local spring = require("tetravim.util.spring")

local M = {}

--- Check and acquire all telescope modules in a single pcall guard.
---@return table|nil
local function get_telescope()
  local ok, tel = pcall(function()
    return {
      pickers = require("telescope.pickers"),
      finders = require("telescope.finders"),
      conf = require("telescope.config").values,
      actions = require("telescope.actions"),
      action_state = require("telescope.actions.state"),
      previewers = require("telescope.previewers"),
    }
  end)

  if not ok or not tel then
    vim.notify("telescope.nvim is required for Spring pickers", vim.log.levels.WARN)
    return nil
  end

  return tel
end

--- Pick a REST endpoint and jump to its controller definition line.
---@param opts? table Telescope options
function M.pick_endpoint(opts)
  opts = opts or {}
  local tel = get_telescope()
  if not tel then
    return
  end

  local root_info = spring.detect_root()
  if not root_info then
    vim.notify("No Maven/Gradle project root found", vim.log.levels.INFO)
    return
  end

  spring.find_endpoints(root_info.root, function(endpoints)
    if endpoints == nil then
      return
    end

    if #endpoints == 0 then
      vim.notify("No Spring Boot / JAX-RS endpoints found in project", vim.log.levels.INFO)
      return
    end

    -- Sort endpoints deterministically by path, then method
    table.sort(endpoints, function(a, b)
      if a.path == b.path then
        return (a.http_method or "") < (b.http_method or "")
      end
      return (a.path or "") < (b.path or "")
    end)

    local entries = {}
    for _, ep in ipairs(endpoints) do
      local display = string.format("[%s] %s  %s.%s", ep.http_method, ep.path, ep.class_name, ep.handler_name)
      table.insert(entries, {
        value = ep,
        display = display,
        ordinal = display,
        filename = ep.file,
        lnum = ep.line,
        col = 1,
      })
    end

    tel.pickers
      .new(opts, {
        prompt_title = "Spring Boot REST Endpoints",
        finder = tel.finders.new_table({
          results = entries,
          entry_maker = function(entry)
            return entry
          end,
        }),
        sorter = tel.conf.generic_sorter(opts),
        previewer = tel.conf.grep_previewer(opts),
        attach_mappings = function(prompt_bufnr, _)
          tel.actions.select_default:replace(function()
            tel.actions.close(prompt_bufnr)
            local selection = tel.action_state.get_selected_entry()
            if selection and selection.value and selection.value.file and selection.value.file ~= "" then
              local ok, _ = pcall(vim.cmd, "edit " .. vim.fn.fnameescape(selection.value.file))
              if ok and selection.value.line then
                pcall(vim.api.nvim_win_set_cursor, 0, { selection.value.line, 0 })
              end
            end
          end)
          return true
        end,
      })
      :find()
  end)
end

--- Pick a Spring Bean with dependency graph preview and jump to class declaration.
---@param opts? table Telescope options
function M.pick_bean(opts)
  opts = opts or {}
  local tel = get_telescope()
  if not tel then
    return
  end

  local root_info = spring.detect_root()
  if not root_info then
    vim.notify("No Maven/Gradle project root found", vim.log.levels.INFO)
    return
  end

  spring.find_beans(root_info.root, function(beans)
    if beans == nil then
      return
    end

    if #beans == 0 then
      vim.notify("No Spring stereotypes (@Component, @Service, etc.) found", vim.log.levels.INFO)
      return
    end

    -- Sort beans by bean_name
    table.sort(beans, function(a, b)
      return (a.bean_name or "") < (b.bean_name or "")
    end)

    -- Compute dependents graph
    local dependents_map = {}
    for _, b in ipairs(beans) do
      for _, dep in ipairs(b.injected_deps) do
        dependents_map[dep] = dependents_map[dep] or {}
        table.insert(dependents_map[dep], b.bean_name)
      end
    end

    local entries = {}
    for _, b in ipairs(beans) do
      local deps_str = #b.injected_deps > 0 and (" -> [" .. table.concat(b.injected_deps, ", ") .. "]") or ""
      local display = string.format("%s (%s)%s", b.bean_name, b.class_name, deps_str)
      table.insert(entries, {
        value = b,
        display = display,
        ordinal = display,
        filename = b.file,
        lnum = b.line,
        col = 1,
      })
    end

    local bean_previewer = tel.previewers.new_buffer_previewer({
      title = "Bean Dependency Graph",
      define_preview = function(self, entry, _)
        local bean = entry.value
        local lines = {
          "Bean: " .. bean.bean_name .. " (" .. bean.class_name .. ")",
          "File: " .. (bean.file or "") .. ":" .. tostring(bean.line or 1),
          "",
          "Direct Dependencies (" .. tostring(#bean.injected_deps) .. "):",
        }
        if #bean.injected_deps == 0 then
          table.insert(lines, "  (none)")
        else
          for _, dep in ipairs(bean.injected_deps) do
            table.insert(lines, "  -> " .. dep)
          end
        end
        table.insert(lines, "")
        local deps_on_this = dependents_map[bean.bean_name] or {}
        table.insert(lines, "Direct Dependents (" .. tostring(#deps_on_this) .. "):")
        if #deps_on_this == 0 then
          table.insert(lines, "  (none)")
        else
          for _, dep_bean in ipairs(deps_on_this) do
            table.insert(lines, "  <- " .. dep_bean)
          end
        end
        vim.api.nvim_buf_set_lines(self.state.bufnr, 0, -1, false, lines)
      end,
    })

    tel.pickers
      .new(opts, {
        prompt_title = "Spring Beans",
        finder = tel.finders.new_table({
          results = entries,
          entry_maker = function(entry)
            return entry
          end,
        }),
        sorter = tel.conf.generic_sorter(opts),
        previewer = bean_previewer,
        attach_mappings = function(prompt_bufnr, _)
          tel.actions.select_default:replace(function()
            tel.actions.close(prompt_bufnr)
            local selection = tel.action_state.get_selected_entry()
            if selection and selection.value and selection.value.file and selection.value.file ~= "" then
              local ok, _ = pcall(vim.cmd, "edit " .. vim.fn.fnameescape(selection.value.file))
              if ok and selection.value.line then
                pcall(vim.api.nvim_win_set_cursor, 0, { selection.value.line, 0 })
              end
            end
          end)
          return true
        end,
      })
      :find()
  end)
end

--- Detect Spring Boot app in workspace and notify details.
function M.detect_app()
  local root_info = spring.detect_root()
  if not root_info then
    vim.notify("No Maven/Gradle project root found", vim.log.levels.INFO)
    return
  end

  spring.find_main_class(root_info.root, function(main_class)
    if not main_class then
      vim.notify("No Spring Boot application found in project", vim.log.levels.INFO)
      return
    end

    vim.notify(
      string.format("Spring Boot: %s (%s) — %s", root_info.project_name, root_info.build_tool, main_class),
      vim.log.levels.INFO
    )
  end)
end

return M
