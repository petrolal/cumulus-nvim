-- TetraVim Test Runner Specs (SPEC-1.3: Visual Test Runner & Coverage)
--
-- Integrates neotest with neotest-java for visual test tree discovery,
-- nearest test execution, and DAP debugging across JVM projects.

local function run_nearest()
  local ok, neotest = pcall(require, "neotest")
  if not ok then
    vim.notify("neotest is not available", vim.log.levels.WARN, { title = "TetraVim Test" })
    return
  end
  local file = vim.api.nvim_buf_get_name(0)
  if not file or file == "" or vim.bo.buftype ~= "" then
    vim.notify("Current buffer is not a valid test file", vim.log.levels.WARN, { title = "TetraVim Test" })
    return
  end
  local call_ok, err = pcall(function()
    neotest.run.run()
  end)
  if not call_ok then
    vim.notify("Failed to run nearest test: " .. tostring(err), vim.log.levels.WARN, { title = "TetraVim Test" })
  end
end

local function run_file()
  local ok, neotest = pcall(require, "neotest")
  if not ok then
    vim.notify("neotest is not available", vim.log.levels.WARN, { title = "TetraVim Test" })
    return
  end
  local file = vim.api.nvim_buf_get_name(0)
  if not file or file == "" or vim.bo.buftype ~= "" then
    vim.notify("Current buffer is not a runnable test file", vim.log.levels.WARN, { title = "TetraVim Test" })
    return
  end
  local call_ok, err = pcall(function()
    neotest.run.run(file)
  end)
  if not call_ok then
    vim.notify("Failed to run test file: " .. tostring(err), vim.log.levels.WARN, { title = "TetraVim Test" })
  end
end

local function toggle_summary()
  local ok, neotest = pcall(require, "neotest")
  if not ok then
    vim.notify("neotest is not available", vim.log.levels.WARN, { title = "TetraVim Test" })
    return
  end
  pcall(function()
    neotest.summary.toggle()
  end)
end

local function toggle_output()
  local ok, neotest = pcall(require, "neotest")
  if not ok then
    vim.notify("neotest is not available", vim.log.levels.WARN, { title = "TetraVim Test" })
    return
  end
  pcall(function()
    neotest.output_panel.toggle()
  end)
end

local function debug_nearest()
  local ok, neotest = pcall(require, "neotest")
  if not ok then
    vim.notify("neotest is not available", vim.log.levels.WARN, { title = "TetraVim Test" })
    return
  end
  local dap_ok, _ = pcall(require, "dap")
  if not dap_ok then
    vim.notify("DAP debugger is not configured", vim.log.levels.WARN, { title = "TetraVim Test" })
    return
  end
  local call_ok, err = pcall(function()
    neotest.run.run({ strategy = "dap" })
  end)
  if not call_ok then
    vim.notify("Failed to debug nearest test: " .. tostring(err), vim.log.levels.WARN, { title = "TetraVim Test" })
  end
end

return {
  {
    "nvim-neotest/neotest",
    dependencies = {
      "nvim-lua/plenary.nvim",
      "nvim-neotest/nvim-nio",
      "antoinemadec/FixCursorHold.nvim",
      "nvim-treesitter/nvim-treesitter",
      {
        "rcasia/neotest-java",
        -- Upstream ships the JUnit Platform Console Standalone jar only via the
        -- interactive `:NeotestJava setup`; fetch it non-interactively so a
        -- fresh clone can run tests without a manual step. This runs during
        -- `:Lazy sync` (off the UI thread), so the blocking variant is fine
        -- and preferable -- the jar is guaranteed present when sync returns.
        build = function()
          require("tetravim.util.neotest_java").ensure_blocking(true)
        end,
      },
      -- Scala test tree. Kotlin/Groovy have no neotest adapter and route
      -- through `tetravim.util.jvm_test` (in-repo Gradle/Maven runner) instead.
      "stevanmilic/neotest-scala",
    },
    -- Adapters registered below cover `.java` (neotest-java) and `.scala` /
    -- `.sbt` (neotest-scala); gate the plugin load on those filetypes so
    -- neotest never loads where it has no adapter. Kotlin is handled outside
    -- neotest entirely (`ftplugin/kotlin.lua` -> `tetravim.util.jvm_test`).
    ft = { "java", "scala", "sbt" },
    keys = {
      {
        "<leader>tr",
        run_nearest,
        desc = "Run Nearest Test",
      },
      {
        "<leader>tf",
        run_file,
        desc = "Run Test File",
      },
      {
        "<leader>ts",
        toggle_summary,
        desc = "Toggle Test Summary",
      },
      {
        "<leader>to",
        toggle_output,
        desc = "Toggle Test Output Panel",
      },
      {
        "<leader>td",
        debug_nearest,
        desc = "Debug Nearest Test (DAP)",
      },
    },
    opts = function()
      local adapters = {}
      local ok_java, neotest_java = pcall(require, "neotest-java")
      if ok_java then
        local adapter = neotest_java({})

        -- neotest-java is Java-only, but its root_finder claims any Gradle/Maven
        -- project -- including Kotlin/Scala-only ones -- and then asserts deep in
        -- client_provider ("No Java file found in the directory"). Decline any
        -- project tree with no hand-written .java sources, and any non-.java
        -- buffer, so those runs fall through instead of crashing.
        local nj = require("tetravim.util.neotest_java")
        local base_root = adapter.root
        local base_is_test_file = adapter.is_test_file
        local java_root_cache = {}

        adapter.root = function(dir)
          local root = base_root(dir)
          if not root then
            return nil
          end
          local cached = java_root_cache[root]
          if cached == nil then
            cached = nj.has_java_sources(root)
            java_root_cache[root] = cached
          end
          return cached and root or nil
        end

        adapter.is_test_file = function(file)
          if type(file) ~= "string" or not file:match("%.java$") then
            return false
          end
          return base_is_test_file(file)
        end

        table.insert(adapters, adapter)
      end

      local ok_scala, neotest_scala = pcall(require, "neotest-scala")
      if ok_scala then
        -- runner + framework auto-detect from the build (bloop/sbt, munit/
        -- scalatest/specs2/utest); no config needed for the common case.
        local ok_build, scala_adapter = pcall(neotest_scala, {})
        if ok_build and scala_adapter then
          table.insert(adapters, scala_adapter)
        end
      end

      return {
        adapters = adapters,
        status = { virtual_text = true },
        output = { open_on_run = true },
      }
    end,
    config = function(_, opts)
      -- `build` covers install/update; guard here too for clones synced before
      -- this spec landed, or a build step that ran without network access.
      -- This fires on the first Java file open, so it must NOT block the UI --
      -- the async variant downloads the ~15 MB jar off the main thread and
      -- the next `<leader>tr` picks it up once it lands.
      pcall(function()
        require("tetravim.util.neotest_java").ensure(true)
      end)
      local neotest = require("neotest")
      neotest.setup(opts)
    end,
  },
}
