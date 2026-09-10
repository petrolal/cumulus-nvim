-- Session cache for the project-independent slice of the jdtls launch config.
--
-- ftplugin/java.lua re-executes for every Java buffer opened in a session. The
-- JDT bundle-jar globs (java-debug / java-test / decompiler / framework
-- extensions) and the lazy.core `opts` introspection that feed it don't change
-- between buffers, so the ftplugin resolves them once on the first Java buffer
-- and parks the result here; later buffers reuse it and only recompute the
-- genuinely per-file bits (root dir, workspace `-data`, heap-bounded cmd).

local M = {}

local cache

--- @return { bundles: string[], opts: table }|nil
function M.get()
  return cache
end

--- @param value { bundles: string[], opts: table }
function M.set(value)
  cache = value
end

--- Test seam: force the next ftplugin load to recompute from scratch.
function M.reset()
  cache = nil
end

return M
