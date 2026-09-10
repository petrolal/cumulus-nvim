-- Shared helpers for the plenary/busted specs.

local M = {}

--- Concatenated source of every `lua/tetravim/health/*.lua` module.
--- The healthcheck used to be one file (`lua/tetravim/health.lua`); it is now
--- split into `lua/tetravim/health/{init,platform,jvm,devops,clients,quality,editor}.lua`.
--- Static "does the healthcheck cover feature X" specs read this instead of a
--- single file so they keep working across the split.
--- @param root string|nil repo root (defaults to the current working directory)
--- @return string
function M.health_source(root)
  root = root or vim.fn.getcwd()
  local dir = root .. "/lua/tetravim/health"
  local parts = {}
  for _, name in ipairs(vim.fn.readdir(dir)) do
    if name:match("%.lua$") then
      local fh = assert(io.open(dir .. "/" .. name, "r"), "could not open " .. dir .. "/" .. name)
      table.insert(parts, fh:read("*a"))
      fh:close()
    end
  end
  return table.concat(parts, "\n")
end

return M
