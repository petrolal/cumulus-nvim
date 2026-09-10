-- TetraVim Spring Boot Debug Configuration (Story 2.3)
-- Detects Spring Boot applications and launches debugging with DAP integration.

local M = {}

--- Insert configuration into table, deduplicating by non-nil name.
---@param configs table[]
---@param new_config table|nil
local function dedup_insert(configs, new_config)
  if not new_config then
    return
  end
  if new_config.name then
    for _, cfg in ipairs(configs) do
      if cfg.name == new_config.name then
        return
      end
    end
  end
  table.insert(configs, new_config)
end

M.dedup_insert = dedup_insert

--- Launch Spring Boot application with debug configuration
function M.launch_debug()
  local ok_spring, spring = pcall(require, "tetravim.util.spring")
  if not ok_spring or not spring then
    vim.notify("Spring module unavailable", vim.log.levels.WARN)
    return
  end

  local ok_dap, dap = pcall(require, "dap")
  if not ok_dap or not dap then
    vim.notify("nvim-dap is not installed", vim.log.levels.WARN)
    return
  end

  local cwd = vim.fn.getcwd()
  spring.build_dap_config(cwd, function(dap_result)
    if not dap_result or not dap_result.launch then
      vim.notify("Failed to generate debug configuration", vim.log.levels.WARN)
      return
    end

    dap.configurations = dap.configurations or {}
    if not dap.configurations.java then
      dap.configurations.java = {}
    end

    if dap_result.configurations and #dap_result.configurations > 0 then
      for _, config in ipairs(dap_result.configurations) do
        dedup_insert(dap.configurations.java, config)
      end
    else
      dedup_insert(dap.configurations.java, dap_result.launch)
      if dap_result.attach then
        dedup_insert(dap.configurations.java, dap_result.attach)
      end
    end

    dap.continue()
  end)
end

--- Inject Spring Boot DAP configurations (called from ftplugin/java.lua)
---@param root_dir? string Root project directory
function M.setup_springboot_dap(root_dir)
  local ok_spring, spring = pcall(require, "tetravim.util.spring")
  if not ok_spring or not spring then
    return
  end

  spring.build_dap_config(root_dir, function(dap_result)
    if not dap_result or not dap_result.launch then
      return
    end

    local ok_dap, dap = pcall(require, "dap")
    if not ok_dap or not dap then
      return
    end

    if not dap.configurations.java then
      dap.configurations.java = {}
    end

    if dap_result.configurations and #dap_result.configurations > 0 then
      for _, config in ipairs(dap_result.configurations) do
        dedup_insert(dap.configurations.java, config)
      end
    else
      dedup_insert(dap.configurations.java, dap_result.launch)
      if dap_result.attach then
        dedup_insert(dap.configurations.java, dap_result.attach)
      end
    end
  end)
end

return M
