-- TetraVim JVM Platform Keymap Suite
--
-- Pure keymap registration for JVM platform operations (Maven, Gradle). Build
-- tool detection is native (tetravim.util.build); task/goal lists come from the
-- build tool itself; terminals run through tetravim.util.term. Test running is
-- delegated to neotest.

local notify = require("tetravim.util.notify")
local term = require("tetravim.util.term")
local build = require("tetravim.util.build")

local M = {}

M.keymaps_registered = false
M.offline_mode = false

-- Consistent notification helpers for JVM operations
local function notify_error(msg)
  notify.notify_warn(msg, "TetraVim JVM")
end

local function notify_info(msg)
  notify.notify_info(msg, "TetraVim JVM")
end

--- Optimize Java/Kotlin imports in the current buffer via JDTLS / LSP.
local function optimize_imports_buffer()
  local bufnr = vim.api.nvim_get_current_buf()
  local ft = vim.bo[bufnr].filetype

  if ft == "java" then
    local ok_jdtls, jdtls = pcall(require, "jdtls")
    if ok_jdtls and jdtls.organize_imports then
      jdtls.organize_imports()
      return
    end
  end

  local params = vim.lsp.util.make_range_params()
  params.context = { only = { "source.organizeImports" } }
  local responses = vim.lsp.buf_request_sync(bufnr, "textDocument/codeAction", params, 1000)
  if responses then
    for _, resp in pairs(responses) do
      for _, action in ipairs(resp.result or {}) do
        if
          action.kind == "source.organizeImports" or (action.title and action.title:lower():find("organize import"))
        then
          if action.edit then
            vim.lsp.util.apply_workspace_edit(action.edit, "utf-8")
          elseif action.command then
            vim.lsp.buf.execute_command(action.command)
          end
          vim.notify("Imports organized via LSP", vim.log.levels.INFO)
          return
        end
      end
    end
  end

  vim.notify("No LSP or organizer available to optimize imports", vim.log.levels.INFO)
end

-- Common Maven lifecycle phases and plugin goals offered by <leader>jbm.
local MAVEN_GOALS = {
  "clean",
  "compile",
  "test-compile",
  "test",
  "package",
  "verify",
  "install",
  "clean compile",
  "clean test",
  "clean package",
  "clean install",
  "dependency:tree",
  "dependency:analyze",
  "versions:display-dependency-updates",
  "help:effective-pom",
  "spring-boot:run",
  "spring-boot:build-image",
}

--- Parse `gradle tasks --all` output into a sorted, de-duplicated task list.
---@param output string
---@return string[]
local function parse_gradle_tasks(output)
  local seen, tasks = {}, {}
  for line in (output or ""):gmatch("[^\r\n]+") do
    -- Task lines look like "  bootRun - Runs this project as a Spring Boot application."
    -- or a bare "bootRun" under a group heading.
    local name = line:match("^([%w:_%-]+) %- ") or line:match("^([%w:_%-]+)%s*$")
    if name and not name:match("^%-+$") and not seen[name] then
      seen[name] = true
      tasks[#tasks + 1] = name
    end
  end
  table.sort(tasks)
  return tasks
end

--- WhichKey specification for the JVM platform keymap hierarchy
function M.whichkey_spec()
  return {
    { "<leader>j", group = "jvm platform", icon = "☕ " },
    { "<leader>jb", group = "build & tasks", icon = "󰒓 " },
    { "<leader>jt", group = "test runner", icon = "󰙨 " },
    { "<leader>jc", group = "code coverage", icon = "📊 " },
    { "<leader>jr", group = "run & execute", icon = "󰐊 " },
    { "<leader>js", group = "spring & frameworks", icon = "󱎘 " },
    { "<leader>jx", group = "refactor & jdtls", icon = "󰨞 " },
    { "<leader>jp", group = "profiling", icon = "⚡ " },
    { "<leader>jd", group = "dependencies", icon = "📦 " },
    { "<leader>jn", group = "new project", icon = "✨ " },
    { "<leader>ji", group = "info", icon = "ℹ " },
  }
end

--- Register all global JVM platform keymaps and WhichKey group specs
function M.setup_keymaps()
  if M.keymaps_registered then
    return
  end
  M.keymaps_registered = true

  local map = vim.keymap.set

  -- Helper function to get the appropriate build command with offline flag
  local function get_build_cmd(base_cmd, offline)
    if offline then
      if base_cmd:match("mvn") then
        return base_cmd .. " -o"
      elseif base_cmd:match("gradle") then
        return base_cmd .. " --offline"
      end
    end
    return base_cmd
  end

  -- Wrapper resolution (./mvnw|./gradlew -> upward wrapper -> system tool) lives
  -- in one place: tetravim.util.build.wrapper_cmd.
  local function get_mvn_cmd(root)
    return build.wrapper_cmd("maven", root)
  end

  local function get_gradle_cmd(root)
    return build.wrapper_cmd("gradle", root)
  end

  --- Resolve JVM project context (tool, root), prompting if multiple subprojects exist.
  ---@param callback fun(tool: "maven"|"gradle", root: string)
  ---@param filter_tool? "maven"|"gradle"
  local function with_jvm_project(callback, filter_tool)
    local tool, root = build.detect()
    if tool and root then
      if not filter_tool or tool == filter_tool then
        callback(tool, root)
        return
      end
    end

    local subprojects = build.find_subprojects and build.find_subprojects(vim.fn.getcwd()) or {}
    if filter_tool then
      local filtered = {}
      for _, sp in ipairs(subprojects) do
        if sp.tool == filter_tool then
          table.insert(filtered, sp)
        end
      end
      subprojects = filtered
    end

    if #subprojects == 0 then
      local name = filter_tool and (filter_tool:sub(1, 1):upper() .. filter_tool:sub(2)) or "Maven or Gradle"
      notify_error("No " .. name .. " project found in current directory or buffer")
      return
    elseif #subprojects == 1 then
      callback(subprojects[1].tool, subprojects[1].root)
      return
    end

    -- Multiple projects found: prompt user to pick
    local items = {}
    for _, sp in ipairs(subprojects) do
      table.insert(items, {
        label = string.format("%s (%s) - %s", sp.name, sp.tool:upper(), sp.root),
        tool = sp.tool,
        root = sp.root,
      })
    end

    vim.ui.select(items, {
      prompt = "Select JVM Project:",
      format_item = function(item)
        return item.label
      end,
    }, function(choice)
      if choice then
        callback(choice.tool, choice.root)
      end
    end)
  end

  -- Detect concrete test source roots under `cwd` (single- or multi-module
  -- layouts) so a "run all tests" action can target those directories
  -- instead of forcing neotest to discover the entire working tree.
  ---@param cwd string
  ---@return string[] roots
  local function detect_test_roots(cwd)
    local roots = {}
    local direct = {
      "src/test/java",
      "src/test/kotlin",
      "src/test/groovy",
      "src/test/scala",
      "src/integrationTest/java",
      "src/integrationTest/kotlin",
    }
    for _, rel in ipairs(direct) do
      local p = cwd .. "/" .. rel
      if vim.fn.isdirectory(p) == 1 then
        table.insert(roots, p)
      end
    end
    if #roots == 0 then
      -- Multi-module fallback: one level of sub-projects only (bounded).
      for _, pattern in ipairs({ "/*/src/test/java", "/*/src/test/kotlin" }) do
        for _, p in ipairs(vim.fn.glob(cwd .. pattern, false, true)) do
          if vim.fn.isdirectory(p) == 1 then
            table.insert(roots, p)
          end
        end
      end
    end
    return roots
  end

  -- 1. Build & Tasks (<leader>jb)
  map("n", "<leader>jbc", function()
    with_jvm_project(function(tool, root)
      if tool == "maven" then
        local base_cmd = get_build_cmd(get_mvn_cmd(root), M.offline_mode)
        term.run_term(base_cmd .. " clean compile", { title = "TetraVim Maven", cwd = root })
      elseif tool == "gradle" then
        local base_cmd = get_build_cmd(get_gradle_cmd(root), M.offline_mode)
        term.run_term(base_cmd .. " clean classes", { title = "TetraVim Gradle", cwd = root })
      end
    end)
  end, { desc = "Build: Clean Compile" })

  map("n", "<leader>jbg", function()
    with_jvm_project(function(tool, root)
      local base_cmd = get_gradle_cmd(root)
      local cmd_prefix = get_build_cmd(base_cmd, M.offline_mode)
      notify_info("Loading Gradle tasks...")

      vim.system(
        vim.list_extend(vim.split(base_cmd, " ", { trimempty = true }), { "tasks", "--all", "--console=plain" }),
        { text = true, cwd = root },
        vim.schedule_wrap(function(res)
          if res.code ~= 0 then
            notify_error("Failed to fetch Gradle tasks")
            return
          end
          local tasks = parse_gradle_tasks(res.stdout)
          if #tasks == 0 then
            notify_error("No Gradle tasks found")
            return
          end
          vim.ui.select(tasks, {
            prompt = "Select Gradle Task (" .. vim.fs.basename(root) .. "):",
            format_item = function(item)
              return cmd_prefix .. " " .. item
            end,
          }, function(choice)
            if choice then
              term.run_term(cmd_prefix .. " " .. choice, { title = "TetraVim Gradle", cwd = root })
            end
          end)
        end)
      )
    end, "gradle")
  end, { desc = "Gradle: Select & Run Task" })

  map("n", "<leader>jbm", function()
    with_jvm_project(function(tool, root)
      local cmd_prefix = get_build_cmd(get_mvn_cmd(root), M.offline_mode)
      vim.ui.select(MAVEN_GOALS, {
        prompt = "Select Maven Goal (" .. vim.fs.basename(root) .. "):",
        format_item = function(item)
          return cmd_prefix .. " " .. item
        end,
      }, function(choice)
        if choice then
          term.run_term(cmd_prefix .. " " .. choice, { title = "TetraVim Maven", cwd = root })
        end
      end)
    end, "maven")
  end, { desc = "Maven: Select & Run Goal" })

  map("n", "<leader>jbo", function()
    M.offline_mode = not M.offline_mode
    local status = M.offline_mode and "ENABLED" or "DISABLED"
    local flags = M.offline_mode and "(-o / --offline)" or ""
    vim.notify("Offline Mode: " .. status .. " " .. flags, vim.log.levels.INFO)
  end, { desc = "Toggle Offline Mode (-o / --offline)" })

  local function resync_dependencies()
    local sync_state = require("tetravim.util.build-sync-state")
    sync_state.reset()
    sync_state.run()
  end

  map("n", "<leader>jbS", resync_dependencies, { desc = "Resync Dependencies (Maven/Gradle)" })

  -- 2. Test Runner (<leader>jt)
  map("n", "<leader>jta", function()
    -- neotest carries adapters for Java (neotest-java) and Scala
    -- (neotest-scala). Drive the in-editor tree when every detected test root
    -- is one of those; a Kotlin-only project routes through the in-repo
    -- Gradle/Maven runner (tetravim.util.jvm_test); anything mixed or Groovy
    -- falls back to the build tool's `test` task, which covers every JVM
    -- language (and multi-module builds) in one pass.
    local roots = detect_test_roots(vim.fn.getcwd())
    local kinds = {}
    for _, r in ipairs(roots) do
      local kind = "other"
      if r:match("/java$") or r:match("/java/") then
        kind = "java"
      elseif r:match("/scala$") or r:match("/scala/") then
        kind = "scala"
      elseif r:match("/kotlin$") or r:match("/kotlin/") then
        kind = "kotlin"
      end
      kinds[kind] = true
    end

    local neotest_ok, neotest = pcall(require, "neotest")
    if #roots > 0 and not kinds.kotlin and not kinds.other and neotest_ok then
      for _, root in ipairs(roots) do
        pcall(function()
          neotest.run.run(root)
        end)
      end
      return
    end

    if #roots > 0 and kinds.kotlin and not kinds.java and not kinds.scala and not kinds.other then
      require("tetravim.util.jvm_test").run_all()
      return
    end

    with_jvm_project(function(tool, root)
      if tool == "maven" then
        local base_cmd = get_build_cmd(get_mvn_cmd(root), M.offline_mode)
        term.run_term(base_cmd .. " test", { title = "TetraVim Maven", cwd = root })
      elseif tool == "gradle" then
        local base_cmd = get_build_cmd(get_gradle_cmd(root), M.offline_mode)
        term.run_term(base_cmd .. " test", { title = "TetraVim Gradle", cwd = root })
      end
    end)
  end, { desc = "Run All Tests in Workspace" })

  map("n", "<leader>jtt", function()
    local ok, neotest = pcall(require, "neotest")
    if not ok then
      notify_error("neotest is not available")
      return
    end
    pcall(function()
      neotest.run.run()
    end)
  end, { desc = "Run Nearest Test Method" })

  map("n", "<leader>jtc", function()
    local file = vim.api.nvim_buf_get_name(0)
    if not file or file == "" or vim.bo.buftype ~= "" then
      notify.notify_warn("Current buffer is not a runnable file", "TetraVim Test")
      return
    end
    local ok, neotest = pcall(require, "neotest")
    if not ok then
      notify.notify_warn("neotest is not available", "TetraVim Test")
      return
    end
    pcall(function()
      neotest.run.run(file)
    end)
  end, { desc = "Run Current Test Class / File" })

  map("n", "<leader>jts", function()
    local ok, neotest = pcall(require, "neotest")
    if ok then
      pcall(function()
        neotest.summary.toggle()
      end)
    else
      notify.notify_warn("neotest is not available", "TetraVim Test")
    end
  end, { desc = "Toggle Test Summary Tree" })

  map("n", "<leader>jto", function()
    local ok, neotest = pcall(require, "neotest")
    if ok then
      pcall(function()
        neotest.output_panel.toggle()
      end)
    else
      notify.notify_warn("neotest is not available", "TetraVim Test")
    end
  end, { desc = "Toggle Test Output Panel" })

  map("n", "<leader>jtd", function()
    local ok, neotest = pcall(require, "neotest")
    if not ok then
      notify.notify_warn("neotest is not available", "TetraVim Test")
      return
    end
    local dap_ok, _ = pcall(require, "dap")
    if not dap_ok then
      notify.notify_warn("DAP debugger is not configured", "TetraVim Test")
      return
    end
    local call_ok, err = pcall(function()
      neotest.run.run({ strategy = "dap" })
    end)
    if not call_ok then
      notify.notify_warn("Failed to debug nearest test: " .. tostring(err), "TetraVim Test")
    end
  end, { desc = "Debug Nearest Test (DAP)" })

  map("n", "<leader>jtp", function()
    local ok, jdtls = pcall(require, "jdtls")
    if ok then
      jdtls.pick_test()
    else
      notify_error("jdtls is not loaded")
    end
  end, { desc = "JDTLS: Pick & Run Test" })

  -- Code Coverage (<leader>jc)
  map("n", "<leader>jcl", function()
    require("tetravim.util.coverage").load()
  end, { desc = "Load JaCoCo Coverage Report" })

  map("n", "<leader>jcx", function()
    -- Hide the overlays but keep the parsed report so <leader>jct can
    -- toggle it back without re-reading the JaCoCo XML.
    require("tetravim.util.coverage").clear(false)
  end, { desc = "Clear Coverage Overlays" })

  map("n", "<leader>jct", function()
    require("tetravim.util.coverage").toggle()
  end, { desc = "Toggle Coverage Display" })

  map("n", "<leader>jcs", function()
    require("tetravim.util.coverage").summary()
  end, { desc = "Show Coverage Summary" })

  -- 3. Run & Execute (<leader>jr)
  map("n", "<leader>jrs", function()
    with_jvm_project(function(tool, root)
      if tool == "maven" then
        local pom_path = vim.fn.findfile("pom.xml", root .. ";")
        if pom_path == "" then
          pom_path = vim.fn.findfile("pom.xml", vim.fn.expand("%:p:h") .. ";")
        end

        local is_quarkus = false
        if pom_path ~= "" then
          local ok, lines = pcall(vim.fn.readfile, pom_path)
          if ok and lines then
            is_quarkus = table.concat(lines, "\n"):match("quarkus%-maven%-plugin") ~= nil
          end
        end

        local base_cmd = get_build_cmd(get_mvn_cmd(root), M.offline_mode)
        local goal = is_quarkus and "quarkus:dev" or "spring-boot:run"
        term.run_term(base_cmd .. " " .. goal, { title = "TetraVim Maven", cwd = root })
      elseif tool == "gradle" then
        local gradle_file = vim.fn.findfile("build.gradle", root .. ";")
        local gradle_kts = vim.fn.findfile("build.gradle.kts", root .. ";")
        local g_path = gradle_file ~= "" and gradle_file or gradle_kts

        local is_quarkus = false
        if g_path ~= "" then
          local ok, lines = pcall(vim.fn.readfile, g_path)
          if ok and lines then
            is_quarkus = table.concat(lines, "\n"):match("quarkus") ~= nil
          end
        end

        local base_cmd = get_build_cmd(get_gradle_cmd(root), M.offline_mode)
        local task = is_quarkus and "quarkusDev" or "bootRun"
        term.run_term(base_cmd .. " " .. task, { title = "TetraVim Gradle", cwd = root })
      end
    end)
  end, { desc = "Run Spring Boot / Quarkus App" })

  map("n", "<leader>jrg", function()
    local file_path = vim.fn.expand("%:p")
    if not file_path or file_path == "" then
      notify_error("Current buffer is not a file")
      return
    end
    vim.cmd("update")
    term.run_term("groovy " .. vim.fn.shellescape(file_path), { title = "TetraVim JVM" })
  end, { desc = "Groovy: Run Current Script" })

  map("n", "<leader>jrd", function()
    require("tetravim.util.springboot-debug").launch_debug()
  end, { desc = "Debug: Launch Spring Boot (DAP)" })

  -- 4. Spring Boot & Frameworks (<leader>js)
  map("n", "<leader>jse", function()
    require("tetravim.util.spring-picker").pick_endpoint()
  end, { desc = "Spring: Select REST Endpoint" })

  map("n", "<leader>jsb", function()
    require("tetravim.util.spring-picker").pick_bean()
  end, { desc = "Spring: Select Bean Dependency" })

  map("n", "<leader>jsd", function()
    require("tetravim.util.spring-picker").detect_app()
  end, { desc = "Spring: Detect Boot App" })

  map("n", "<leader>jsm", function()
    -- Migrations/schema live in the Dadbod UI explorer (also on <leader>ad).
    local ok = pcall(vim.cmd, "DBUIToggle")
    if not ok then
      notify_error("vim-dadbod-ui is not available")
    end
  end, { desc = "Database Explorer (Dadbod)" })

  map("n", "<leader>jsq", function()
    require("tetravim.util.jvm_lsp_toggle").toggle()
  end, { desc = "Toggle Quarkus / MicroProfile LSP (~1 GiB JVM each)" })

  -- 5. Refactoring & JDTLS (<leader>jx)
  map("n", "<leader>jxo", optimize_imports_buffer, { desc = "Optimize Java/Kotlin Imports (JDTLS/LSP)" })

  map("n", "<leader>jxH", function()
    local clients = vim.lsp.get_clients({ name = "jdtls" })
    if #clients > 0 then
      vim.notify("JDTLS is active and connected to project", vim.log.levels.INFO)
    else
      vim.notify("JDTLS is not active for this buffer", vim.log.levels.WARN)
    end
  end, { desc = "JDTLS: Check Client Status" })

  -- 6. Profiling (<leader>jp)
  map("n", "<leader>jps", function()
    require("tetravim.util.profiling").start()
  end, { desc = "Profiler: Start" })

  map("n", "<leader>jpx", function()
    require("tetravim.util.profiling").stop()
  end, { desc = "Profiler: Stop" })

  map("n", "<leader>jpv", function()
    require("tetravim.util.profiling").view()
  end, { desc = "Profiler: View Flamegraph" })

  map("n", "<leader>jpp", function()
    require("tetravim.util.profiling").capture()
  end, { desc = "Profiler: Capture -> Interactive Call Tree" })

  -- 7. Dependencies (<leader>jd)
  map("n", "<leader>jdu", function()
    with_jvm_project(function(tool, root)
      if tool == "gradle" then
        local cmd = get_build_cmd(get_gradle_cmd(root), M.offline_mode)
        term.run_term(cmd .. " dependencyUpdates", { title = "TetraVim Gradle", cwd = root })
      else
        local cmd = get_build_cmd(get_mvn_cmd(root), M.offline_mode)
        term.run_term(cmd .. " versions:display-dependency-updates", { title = "TetraVim Maven", cwd = root })
      end
    end)
  end, { desc = "Check Dependency Versions" })

  map("n", "<leader>jds", resync_dependencies, { desc = "Maven/Gradle: Resync Dependencies" })

  -- 8. Environment & Diagnostics (<leader>ji)
  map("n", "<leader>jii", function()
    local clients = vim.lsp.get_clients()
    local client_names = {}
    for _, c in ipairs(clients) do
      table.insert(client_names, c.name)
    end
    local ver = vim.version()
    local msg = string.format(
      "TetraVim JVM Environment\nActive LSPs: %s\nNeovim: v%d.%d.%d",
      #client_names > 0 and table.concat(client_names, ", ") or "None",
      ver.major,
      ver.minor,
      ver.patch
    )
    vim.notify(msg, vim.log.levels.INFO)
  end, { desc = "JVM Environment: LSP Status" })

  map("n", "<leader>jid", "<cmd>Mason<cr>", { desc = "Mason Package Manager" })
  map("n", "<leader>jih", "<cmd>checkhealth tetravim<cr>", { desc = "TetraVim Health Check" })

  -- 9. New Project Wizard (<leader>jn)
  map("n", "<leader>jnn", function()
    require("tetravim.util.project-wizard").create_project()
  end, { desc = "New JVM Project Wizard" })

  map("n", "<leader>jns", function()
    require("tetravim.util.project-wizard").new_spring_boot()
  end, { desc = "New Spring Boot Project (Initializr)" })

  map("n", "<leader>jnm", function()
    require("tetravim.util.project-wizard").new_maven_project()
  end, { desc = "New Maven Project (Archetype)" })

  map("n", "<leader>jng", function()
    require("tetravim.util.project-wizard").new_gradle_project()
  end, { desc = "New Gradle Project (gradle init)" })

  -- Global user commands
  vim.api.nvim_create_user_command("TetraVimNewProject", function()
    require("tetravim.util.project-wizard").create_project()
  end, { desc = "Open TetraVim New JVM Project Wizard" })

  vim.api.nvim_create_user_command("JVMNewProject", function()
    require("tetravim.util.project-wizard").create_project()
  end, { desc = "Open TetraVim New JVM Project Wizard" })

  -- WhichKey group specs are registered once, by the aggregator
  -- (plugins/ui-whichkey.lua) via require("tetravim.util.jvm").whichkey_spec().
  -- This module deliberately does not register them itself, so there is a
  -- single registration path and no hand-synced duplicate list.
end

--- Locate Java 21 JDK installation path across common system locations and SDKMAN
---@return string|nil java21_home Path to Java 21 installation or nil if not found
function M.find_java21_home()
  local patterns = {
    "/usr/lib/jvm/java-21-openjdk*",
    "/usr/lib/jvm/java-21*",
    "/usr/lib/jvm/jdk-21*",
    vim.fn.expand("~/.sdkman/candidates/java/21*"),
    "/usr/lib/jvm/default-java",
  }
  for _, pat in ipairs(patterns) do
    local candidates = vim.fn.glob(pat, false, true)
    if #candidates > 0 and vim.fn.isdirectory(candidates[1]) == 1 then
      return candidates[1]
    end
  end
  return nil
end

--- Check if a given directory is a JVM project (Maven, Gradle, or SBT)
---@param root string|number|nil Directory to check (defaults to cwd)
---@return boolean
function M.is_jvm_project(root)
  if type(root) == "number" then
    return false
  end
  root = root or vim.fn.getcwd()
  if type(root) ~= "string" or root == "" then
    return false
  end
  return vim.fn.glob(root .. "/pom.xml") ~= ""
    or vim.fn.glob(root .. "/build.gradle") ~= ""
    or vim.fn.glob(root .. "/build.gradle.kts") ~= ""
    or vim.fn.glob(root .. "/build.sbt") ~= ""
end

return M
