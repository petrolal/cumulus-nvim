-- TetraVim JVM Project Generator Wizard (Spring Initializr, Maven & Gradle)
--
-- Interactive project scaffolding inspired by IntelliJ IDEA's New Project wizard.
-- Supports:
--   1. Spring Boot (Maven/Gradle, Java/Kotlin, curated & custom dependencies via start.spring.io)
--   2. Standard Maven Project (via maven-archetype-quickstart / webapp)
--   3. Standard Gradle Project (via gradle init with Kotlin or Groovy DSL)
--   4. Interactive Terminal Scaffolding (via Snacks.terminal / termopen)

local ui = require("tetravim.util.ui")
local term = require("tetravim.util.term")

local M = {}

local catalog = require("tetravim.util.jvm.project_wizard.catalog")

--- Curated catalogs (Spring Boot deps & presets, Maven archetypes). Data tables
--- live in project_wizard/catalog.lua; re-exported as module fields so existing
--- call sites and specs keep reading `wizard.SPRING_DEPENDENCIES` &c.
M.SPRING_DEPENDENCIES = catalog.SPRING_DEPENDENCIES
M.SPRING_PRESETS = catalog.SPRING_PRESETS
M.MAVEN_ARCHETYPES = catalog.MAVEN_ARCHETYPES

--- Wrapper for vim.ui.select to ensure consistent prompt titles and snacks picker integration.
local function select_one(items, prompt_title, format_fn, callback)
  local ok, snacks = pcall(require, "snacks")
  if ok and snacks.picker and snacks.picker.select then
    snacks.picker.select(items, {
      prompt = prompt_title,
      format_item = format_fn or function(item)
        return tostring(item)
      end,
    }, function(choice)
      if choice then
        callback(choice)
      end
    end)
    return
  end

  vim.ui.select(items, {
    prompt = prompt_title,
    format_item = format_fn or function(item)
      return tostring(item)
    end,
  }, function(choice)
    if choice then
      callback(choice)
    end
  end)
end

--- Wrapper for vim.ui.input.
local function input_text(prompt_title, default_val, callback)
  vim.ui.input({
    prompt = prompt_title .. " ",
    default = default_val or "",
  }, function(input)
    if input and input ~= "" then
      callback(vim.trim(input))
    end
  end)
end

--- Find the best entry file to open after project generation.
---@param dir string Project root directory
---@return string File path
local function find_entry_file(dir)
  -- 1. Check for Spring Boot / main Java or Kotlin application
  local app_files = vim.fn.glob(dir .. "/src/main/java/**/*Application.java", false, true)
  if #app_files > 0 then
    return app_files[1]
  end
  local kt_app_files = vim.fn.glob(dir .. "/src/main/kotlin/**/*Application.kt", false, true)
  if #kt_app_files > 0 then
    return kt_app_files[1]
  end

  -- 2. Check for general App.java / App.kt
  local java_files = vim.fn.glob(dir .. "/src/main/java/**/*.java", false, true)
  if #java_files > 0 then
    return java_files[1]
  end
  local kt_files = vim.fn.glob(dir .. "/src/main/kotlin/**/*.kt", false, true)
  if #kt_files > 0 then
    return kt_files[1]
  end

  -- 3. Check for build scripts
  for _, fname in ipairs({ "pom.xml", "build.gradle.kts", "build.gradle" }) do
    local p = dir .. "/" .. fname
    if vim.fn.filereadable(p) == 1 then
      return p
    end
  end

  return dir
end

--- Post-generation setup: switches cwd, opens the entry file, and resyncs dependencies.
---@param target_dir string
---@param project_type string
local function open_and_init_project(target_dir, project_type)
  target_dir = vim.fn.fnamemodify(target_dir, ":p"):gsub("/$", "")
  vim.cmd("cd " .. vim.fn.fnameescape(target_dir))

  -- Ensure wrappers are executable if present (wrapper_cmd sets the exec bit as
  -- a side effect via a non-blocking vim.uv.fs_chmod).
  local build = require("tetravim.util.jvm.build")
  build.wrapper_cmd("maven", target_dir)
  build.wrapper_cmd("gradle", target_dir)

  -- Initialize Git repository if git is available and target_dir is not already in a git repo (IntelliJ style)
  if vim.fn.executable("git") == 1 then
    pcall(function()
      local check_git = vim
        .system({ "git", "-C", target_dir, "rev-parse", "--is-inside-work-tree" }, { text = true })
        :wait()
      if check_git.code ~= 0 then
        vim.system({ "git", "-C", target_dir, "init" }, { text = true }):wait()
        vim.system({ "git", "-C", target_dir, "add", "." }, { text = true }):wait()
        vim
          .system({ "git", "-C", target_dir, "commit", "-m", "chore: initial commit from project wizard" }, { text = true })
          :wait()
      end
    end)
  end

  local entry_file = find_entry_file(target_dir)
  if vim.fn.filereadable(entry_file) == 1 then
    vim.cmd("edit " .. vim.fn.fnameescape(entry_file))
  else
    pcall(function()
      local snacks = _G.Snacks or package.loaded["snacks"]
      if snacks and snacks.picker and snacks.picker.files then
        snacks.picker.files({ cwd = target_dir })
      end
    end)
  end

  ui.notify_info(string.format("✔ %s project created at %s", project_type, target_dir), "TetraVim Wizard")

  -- Trigger dependency sync if available
  local ok_sync, sync_state = pcall(require, "tetravim.util.jvm.build_sync_state")
  if ok_sync and type(sync_state.reset) == "function" and type(sync_state.run) == "function" then
    vim.defer_fn(function()
      sync_state.reset()
      sync_state.run()
    end, 500)
  end
end

local PREFS_FILE = vim.fn.stdpath("data") .. "/tetravim/project_wizard_prefs.json"

--- Load saved wizard preferences (remember last-used settings like IntelliJ).
---@return { groupId: string, javaVersion: string, language: string, type: string }
local function load_prefs()
  if vim.fn.filereadable(PREFS_FILE) == 1 then
    local ok, lines = pcall(vim.fn.readfile, PREFS_FILE)
    if ok and lines and #lines > 0 then
      local decode_ok, prefs = pcall(vim.json.decode, table.concat(lines, "\n"))
      if decode_ok and type(prefs) == "table" then
        return prefs
      end
    end
  end
  return {
    groupId = "com.example",
    javaVersion = "21",
    language = "java",
    type = "maven-project",
  }
end

--- Save wizard preferences.
---@param new_prefs table
local function save_prefs(new_prefs)
  pcall(function()
    local dir = vim.fn.fnamemodify(PREFS_FILE, ":h")
    vim.fn.mkdir(dir, "p")
    local current = load_prefs()
    local merged = vim.tbl_deep_extend("force", current, new_prefs or {})
    vim.fn.writefile(vim.split(vim.json.encode(merged), "\n"), PREFS_FILE)
  end)
end

--- Generate Spring Boot project from parameters.
---@param opts { type: string, language: string, bootVersion?: string, groupId: string, artifactId: string, name?: string, packageName?: string, javaVersion: string, packaging?: string, dependencies: string[], targetDir: string }
---@param callback? fun(success: boolean, target_dir: string, err?: string)
function M.generate_spring(opts, callback)
  local curl_bin = vim.fn.executable("curl") == 1
  local unzip_bin = vim.fn.executable("unzip") == 1

  if not curl_bin then
    local err = "'curl' is required to download Spring Initializr projects."
    ui.notify_err(err, "TetraVim Wizard")
    if callback then
      callback(false, opts.targetDir, err)
    end
    return
  end

  if not unzip_bin then
    local err = "'unzip' is required to unpack Spring Initializr projects."
    ui.notify_err(err, "TetraVim Wizard")
    if callback then
      callback(false, opts.targetDir, err)
    end
    return
  end

  local target_dir = vim.fn.fnamemodify(opts.targetDir, ":p"):gsub("/$", "")
  if vim.fn.isdirectory(target_dir) == 1 then
    local contents = vim.fn.glob(target_dir .. "/*", false, true)
    if #contents > 0 then
      local err = "Target directory is not empty: " .. target_dir
      ui.notify_err(err, "TetraVim Wizard")
      if callback then
        callback(false, target_dir, err)
      end
      return
    end
  else
    vim.fn.mkdir(target_dir, "p")
  end

  local clean_boot_ver = opts.bootVersion and opts.bootVersion:gsub("%.RELEASE$", "") or ""
  local deps_str = table.concat(opts.dependencies or {}, ",")
  local base_url = "https://start.spring.io/starter.zip"
  local query_params = {
    type = opts.type or "maven-project",
    language = opts.language or "java",
    bootVersion = clean_boot_ver ~= "" and clean_boot_ver or nil,
    groupId = opts.groupId or "com.example",
    artifactId = opts.artifactId or "demo",
    name = opts.name or opts.artifactId or "demo",
    packageName = opts.packageName or ((opts.groupId or "com.example") .. "." .. (opts.artifactId or "demo")),
    packaging = opts.packaging or "jar",
    javaVersion = opts.javaVersion or "21",
    dependencies = deps_str ~= "" and deps_str or nil,
  }

  local url_parts = {}
  for k, v in pairs(query_params) do
    if v and v ~= "" then
      table.insert(url_parts, string.format("%s=%s", k, vim.uri_encode(v)))
    end
  end
  local full_url = base_url .. "?" .. table.concat(url_parts, "&")
  local tmp_zip = vim.fn.tempname() .. ".zip"

  ui.notify_info("Downloading Spring Boot template from start.spring.io...", "TetraVim Wizard")

  vim.system(
    { "curl", "-sSL", "-A", "TetraVim-Neovim", "-o", tmp_zip, full_url },
    { text = true },
    vim.schedule_wrap(function(curl_res)
      if curl_res.code ~= 0 or vim.fn.filereadable(tmp_zip) == 0 or vim.fn.getfsize(tmp_zip) < 100 then
        pcall(vim.fn.delete, tmp_zip)
        local err = "Failed to download project from Spring Initializr: " .. (curl_res.stderr or "Network error")
        ui.notify_err(err, "TetraVim Wizard")
        if callback then
          callback(false, target_dir, err)
        end
        return
      end

      -- Verify file is a valid ZIP archive (magic number 'PK')
      local f = io.open(tmp_zip, "rb")
      local header = ""
      local body = ""
      if f then
        header = f:read(4) or ""
        f:seek("set", 0)
        body = f:read(1024) or ""
        f:close()
      end

      if header:sub(1, 2) ~= "PK" then
        pcall(vim.fn.delete, tmp_zip)
        local err = "Invalid archive received from start.spring.io"
        local decode_ok, err_obj = pcall(vim.json.decode, body)
        if decode_ok and type(err_obj) == "table" and (err_obj.message or err_obj.error) then
          err = "Spring Initializr error: " .. (err_obj.message or err_obj.error)
        elseif body ~= "" then
          err = "Spring Initializr error: " .. body:gsub("%s+", " "):sub(1, 150)
        end
        ui.notify_err(err, "TetraVim Wizard")
        if callback then
          callback(false, target_dir, err)
        end
        return
      end

      -- Unzip into target directory
      vim.system(
        { "unzip", "-q", "-o", tmp_zip, "-d", target_dir },
        { text = true },
        vim.schedule_wrap(function(unzip_res)
          pcall(vim.fn.delete, tmp_zip)
          if unzip_res.code ~= 0 then
            local err = "Failed to unzip project: " .. (unzip_res.stderr or "Extraction error")
            ui.notify_err(err, "TetraVim Wizard")
            if callback then
              callback(false, target_dir, err)
            end
            return
          end

          open_and_init_project(
            target_dir,
            "Spring Boot (" .. (opts.type:match("maven") and "Maven" or "Gradle") .. ")"
          )
          if callback then
            callback(true, target_dir)
          end
        end)
      )
    end)
  )
end

--- Fetch all Spring Initializr dependencies dynamically from start.spring.io (like IntelliJ / VSCode).
--- Caches them in stdpath("cache")/tetravim/spring-dependencies.json.
---@param callback fun(deps: table[], err?: string)
function M.get_spring_initializr_dependencies(callback)
  local cache_dir = vim.fn.stdpath("cache") .. "/tetravim"
  local cache_file = cache_dir .. "/spring-dependencies.json"

  -- 1. Check local cache
  if vim.fn.filereadable(cache_file) == 1 then
    local ok, content = pcall(vim.fn.readfile, cache_file)
    if ok and content and #content > 0 then
      local decode_ok, items = pcall(vim.json.decode, table.concat(content, "\n"))
      if decode_ok and type(items) == "table" and #items > 0 then
        callback(items)
        return
      end
    end
  end

  if vim.fn.executable("curl") == 0 then
    callback(M.SPRING_DEPENDENCIES)
    return
  end

  vim.fn.mkdir(cache_dir, "p")

  -- 2. Fetch from start.spring.io/metadata/client asynchronously
  vim.system(
    {
      "curl",
      "-sSL",
      "-A",
      "TetraVim-Neovim",
      "-H",
      "Accept: application/json",
      "https://start.spring.io/metadata/client",
    },
    { text = true },
    vim.schedule_wrap(function(res)
      if res.code ~= 0 or not res.stdout or #res.stdout < 500 then
        callback(M.SPRING_DEPENDENCIES)
        return
      end

      local ok, data = pcall(vim.json.decode, res.stdout)
      if not ok or not data or not data.dependencies or not data.dependencies.values then
        callback(M.SPRING_DEPENDENCIES)
        return
      end

      local all_deps = {}
      for _, cat in ipairs(data.dependencies.values) do
        local cat_name = cat.name or "General"
        for _, item in ipairs(cat.values or {}) do
          local desc = (item.description or ""):gsub("%s+", " "):gsub("^%s*", ""):gsub("%s*$", "")
          table.insert(all_deps, {
            id = item.id,
            name = item.name or item.id,
            category = cat_name,
            desc = desc,
          })
        end
      end

      -- Sort by category then name
      table.sort(all_deps, function(a, b)
        if a.category == b.category then
          return a.name:lower() < b.name:lower()
        end
        return a.category:lower() < b.category:lower()
      end)

      -- 3. Cache to disk
      pcall(function()
        local json_str = vim.json.encode(all_deps)
        vim.fn.writefile(vim.split(json_str, "\n"), cache_file)
      end)

      callback(all_deps)
    end)
  )
end

--- Fetch available Spring Boot versions dynamically from start.spring.io.
---@param callback fun(versions: table[])
function M.get_spring_boot_versions(callback)
  local fallback = {
    { id = "", name = "Default (Recommended - Latest Stable)", is_default = true },
  }

  if vim.fn.executable("curl") == 0 then
    callback(fallback)
    return
  end

  vim.system(
    {
      "curl",
      "-sSL",
      "-A",
      "TetraVim-Neovim",
      "-H",
      "Accept: application/json",
      "https://start.spring.io/metadata/client",
    },
    { text = true },
    vim.schedule_wrap(function(res)
      if res.code ~= 0 or not res.stdout or #res.stdout < 500 then
        callback(fallback)
        return
      end

      local ok, data = pcall(vim.json.decode, res.stdout)
      if not ok or not data or not data.bootVersion or not data.bootVersion.values then
        callback(fallback)
        return
      end

      local default_id = data.bootVersion["default"] or ""
      local versions = {
        { id = "", name = "Default (Recommended - Latest Stable)", is_default = true },
      }
      for _, item in ipairs(data.bootVersion.values) do
        local clean_id = item.id:gsub("%.RELEASE$", "")
        local is_def = item.id == default_id
        local label = item.name or clean_id
        if is_def then
          label = label .. " (Current GA)"
        end
        table.insert(versions, {
          id = clean_id,
          name = label,
          is_default = is_def,
        })
      end

      callback(#versions > 0 and versions or fallback)
    end)
  )
end

--- Interactive Custom Dependency Picker with toggle checkmarks (VSCode / IntelliJ flow).
---@param selected_deps table<string, boolean>
---@param on_done fun(deps: string[])
local function pick_custom_dependencies(selected_deps, on_done)
  M.get_spring_initializr_dependencies(function(all_deps)
    local ok, snacks = pcall(require, "snacks")
    if ok and snacks.picker and snacks.picker.pick then
      local items = {}
      for _, dep in ipairs(all_deps) do
        table.insert(items, {
          text = string.format("%s %s %s %s", dep.name, dep.id, dep.category or "", dep.desc or ""),
          name = dep.name,
          id = dep.id,
          category = dep.category or "General",
          desc = dep.desc or "",
        })
      end

      snacks.picker.pick({
        title = "Spring Boot Dependencies (<Tab> check/uncheck, <CR> confirm)",
        items = items,
        format = function(item, picker)
          local sel = picker:selected()
          local is_selected = selected_deps[item.id]
          if not is_selected and sel and #sel > 0 then
            for _, s in ipairs(sel) do
              if s.id == item.id then
                is_selected = true
                break
              end
            end
          end
          local check = is_selected and "✔ " or "  "
          local cat_tag = item.category and string.format("[%s]", item.category) or ""
          return {
            { check, is_selected and "SnacksPickerSelected" or "Comment" },
            { string.format("%-28s ", item.name), is_selected and "Bold" or "Normal" },
            { string.format("%-16s ", cat_tag), "SnacksPickerDimmed" },
            { item.desc or "", "Comment" },
          }
        end,
        win = {
          input = {
            keys = {
              ["<Tab>"] = { "select_and_next", mode = { "i", "n" } },
              ["<S-Tab>"] = { "select_and_prev", mode = { "i", "n" } },
            },
          },
        },
        confirm = function(picker, item)
          local sel = picker:selected()
          if #sel > 0 then
            for _, s in ipairs(sel) do
              selected_deps[s.id] = true
            end
          elseif item and item.id then
            selected_deps[item.id] = true
          end
          picker:close()

          local result = {}
          for id, active in pairs(selected_deps) do
            if active then
              table.insert(result, id)
            end
          end
          table.sort(result)
          on_done(result)
        end,
      })
      return
    end

    local function show_menu()
      local selected_count = 0
      for _, active in pairs(selected_deps) do
        if active then
          selected_count = selected_count + 1
        end
      end

      local items = {
        {
          id = "__DONE__",
          display = string.format("✅ [ DONE - Confirm & Generate Project (%d selected) ]", selected_count),
        },
      }

      if selected_count > 0 then
        table.insert(items, {
          id = "__CLEAR__",
          display = "🗑️  [ Clear All Selected Dependencies ]",
        })
      end

      for _, dep in ipairs(all_deps) do
        local check = selected_deps[dep.id] and "[x]" or "[ ]"
        local cat_tag = dep.category and string.format("[%s]", dep.category) or ""
        local desc_part = (dep.desc and dep.desc ~= "") and (" │ " .. dep.desc) or ""
        local display = string.format("%s %-28s %-16s%s", check, dep.name, cat_tag, desc_part)
        table.insert(items, {
          id = dep.id,
          name = dep.name,
          category = dep.category,
          display = display,
        })
      end

      select_one(
        items,
        string.format("Spring Dependencies (%d chosen) - Select to toggle [x], then choose DONE:", selected_count),
        function(item)
          return item.display
        end,
        function(choice)
          if choice.id == "__DONE__" then
            local result = {}
            for id, active in pairs(selected_deps) do
              if active then
                table.insert(result, id)
              end
            end
            table.sort(result)
            on_done(result)
          elseif choice.id == "__CLEAR__" then
            for k in pairs(selected_deps) do
              selected_deps[k] = nil
            end
            show_menu()
          else
            selected_deps[choice.id] = not selected_deps[choice.id]
            show_menu()
          end
        end
      )
    end

    show_menu()
  end)
end

--- Spring Boot Interactive Wizard with sticky defaults and IntelliJ/VSCode parity.
function M.new_spring_boot()
  local prefs = load_prefs()
  local project_types = {
    { type = "maven-project", lang = "java", label = "Maven Project (Java)" },
    { type = "gradle-project-kotlin", lang = "java", label = "Gradle - Kotlin DSL (Java)" },
    { type = "gradle-project", lang = "java", label = "Gradle - Groovy DSL (Java)" },
    { type = "maven-project", lang = "kotlin", label = "Maven Project (Kotlin)" },
    { type = "gradle-project-kotlin", lang = "kotlin", label = "Gradle - Kotlin DSL (Kotlin)" },
  }

  select_one(project_types, "Step 1/6: Build System & Language", function(item)
    local is_prev = (item.type == prefs.type and item.lang == prefs.language) and " (Recent)" or ""
    return item.label .. is_prev
  end, function(chosen_type)
    M.get_spring_boot_versions(function(boot_versions)
      select_one(boot_versions, "Step 2/6: Spring Boot Version", function(bv)
        return bv.name
      end, function(chosen_boot_ver)
        input_text("Step 3/6: Group ID", prefs.groupId or "com.example", function(group_id)
          input_text("Step 4/6: Artifact ID / Project Name", "demo", function(artifact_id)
            local java_versions = { "21", "17", "25" }
            select_one(java_versions, "Step 5/6: Java Version", function(ver)
              local is_prev = (ver == prefs.javaVersion) and " (Recent)" or ""
              return "Java " .. ver .. (ver == "21" and " (LTS - Recommended)" or "") .. is_prev
            end, function(java_ver)
              select_one(M.SPRING_PRESETS, "Step 6/6: Dependencies", function(preset)
                return preset.name
              end, function(chosen_preset)
                local function on_deps_ready(final_deps)
                  -- Smart auto-derivation of package name and destination directory
                  local safe_pkg_suffix = artifact_id:gsub("[^%w_]", "_"):lower()
                  local auto_package = group_id .. "." .. safe_pkg_suffix
                  local default_target = vim.fn.getcwd() .. "/" .. artifact_id

                  input_text("Target Directory", default_target, function(target_dir)
                    -- Remember user preferences for next time (IntelliJ sticky settings)
                    save_prefs({
                      groupId = group_id,
                      javaVersion = java_ver,
                      language = chosen_type.lang,
                      type = chosen_type.type,
                    })

                    M.generate_spring({
                      type = chosen_type.type,
                      language = chosen_type.lang,
                      bootVersion = chosen_boot_ver.id,
                      groupId = group_id,
                      artifactId = artifact_id,
                      name = artifact_id,
                      packageName = auto_package,
                      javaVersion = java_ver,
                      dependencies = final_deps,
                      targetDir = target_dir,
                    })
                  end)
                end

                if chosen_preset.deps == "manual" then
                  input_text(
                    "Enter comma-separated dependency IDs (e.g. web,data-jpa,lombok,postgresql)",
                    "web,lombok",
                    function(input)
                      local deps = {}
                      for part in input:gmatch("[^,%s]+") do
                        table.insert(deps, part)
                      end
                      on_deps_ready(deps)
                    end
                  )
                elseif chosen_preset.deps == nil then
                  pick_custom_dependencies({}, on_deps_ready)
                else
                  on_deps_ready(chosen_preset.deps)
                end
              end)
            end)
          end)
        end)
      end)
    end)
  end)
end

--- Generate Standard Maven Project via maven-archetype.
---@param opts { archetype: string, groupId: string, artifactId: string, version?: string, packageName?: string, targetDir: string }
---@param callback? fun(success: boolean, target_dir: string, err?: string)
function M.generate_maven(opts, callback)
  if vim.fn.executable("mvn") == 0 then
    local err = "'mvn' (Apache Maven) is not found on $PATH."
    ui.notify_err(err, "TetraVim Wizard")
    if callback then
      callback(false, opts.targetDir, err)
    end
    return
  end

  local parent_dir = vim.fn.fnamemodify(opts.targetDir, ":h")
  local artifact_id = opts.artifactId
  local target_dir = parent_dir .. "/" .. artifact_id

  if vim.fn.isdirectory(target_dir) == 1 then
    local err = "Target directory already exists: " .. target_dir
    ui.notify_err(err, "TetraVim Wizard")
    if callback then
      callback(false, target_dir, err)
    end
    return
  end

  vim.fn.mkdir(parent_dir, "p")

  local archetype_group = opts.archetypeGroupId or "org.apache.maven.archetypes"
  local archetype = opts.archetype or opts.archetypeArtifactId or "maven-archetype-quickstart"
  local archetype_version = opts.archetypeVersion or "RELEASE"

  local cmd = {
    "mvn",
    "-B",
    "archetype:generate",
    "-DarchetypeGroupId=" .. archetype_group,
    "-DarchetypeArtifactId=" .. archetype,
    "-DarchetypeVersion=" .. archetype_version,
    "-DgroupId=" .. (opts.groupId or "com.example"),
    "-DartifactId=" .. artifact_id,
    "-Dversion=" .. (opts.version or "1.0.0-SNAPSHOT"),
    "-Dpackage=" .. (opts.packageName or opts.groupId or "com.example"),
    "-DinteractiveMode=false",
  }

  ui.notify_info("Scaffolding Maven project via " .. archetype .. "...", "TetraVim Wizard")

  vim.system(
    cmd,
    { text = true, cwd = parent_dir },
    vim.schedule_wrap(function(res)
      if res.code ~= 0 or vim.fn.isdirectory(target_dir) == 0 then
        local err = "Maven archetype generation failed: " .. (res.stderr or res.stdout or "Error")
        ui.notify_err(err, "TetraVim Wizard")
        if callback then
          callback(false, target_dir, err)
        end
        return
      end

      -- Modernize pom.xml to Java 21 if it was generated with legacy Java 7/8 properties
      local pom_file = target_dir .. "/pom.xml"
      if vim.fn.filereadable(pom_file) == 1 then
        local ok, lines = pcall(vim.fn.readfile, pom_file)
        if ok and lines then
          local content = table.concat(lines, "\n")
          content = content:gsub(
            "<maven%.compiler%.source>[^<]+</maven%.compiler%.source>",
            "<maven.compiler.source>21</maven.compiler.source>"
          )
          content = content:gsub(
            "<maven%.compiler%.target>[^<]+</maven%.compiler%.target>",
            "<maven.compiler.target>21</maven.compiler.target>"
          )
          pcall(vim.fn.writefile, vim.split(content, "\n"), pom_file)
        end
      end

      open_and_init_project(target_dir, "Maven (" .. archetype .. ")")
      if callback then
        callback(true, target_dir)
      end
    end)
  )
end

--- Fetch and cache the Maven Central archetype catalog.
--- Parses unique archetypes and caches them in stdpath("cache")/tetravim/archetype-catalog.json.
---@param callback fun(items: table[], err?: string)
function M.get_maven_central_archetypes(callback)
  local cache_dir = vim.fn.stdpath("cache") .. "/tetravim"
  local cache_file = cache_dir .. "/archetype-catalog.json"

  -- 1. Check if cached catalog already exists
  if vim.fn.filereadable(cache_file) == 1 then
    local ok, content = pcall(vim.fn.readfile, cache_file)
    if ok and content and #content > 0 then
      local decode_ok, items = pcall(vim.json.decode, table.concat(content, "\n"))
      if decode_ok and type(items) == "table" and #items > 0 then
        callback(items)
        return
      end
    end
  end

  if vim.fn.executable("curl") == 0 then
    local err = "'curl' is required to fetch the Maven Central catalog."
    ui.notify_err(err, "TetraVim Wizard")
    callback({}, err)
    return
  end

  ui.notify_info("Downloading Maven Central archetype catalog (3,700+ archetypes)...", "TetraVim Wizard")
  vim.fn.mkdir(cache_dir, "p")

  -- 2. Fetch compressed XML asynchronously
  vim.system(
    { "curl", "-sSL", "--compressed", "https://repo.maven.apache.org/maven2/archetype-catalog.xml" },
    { text = true },
    vim.schedule_wrap(function(res)
      if res.code ~= 0 or not res.stdout or #res.stdout < 1000 then
        local err = "Failed to download Maven Central archetype catalog: " .. (res.stderr or "Network error")
        ui.notify_err(err, "TetraVim Wizard")
        callback({}, err)
        return
      end

      -- 3. Parse XML in Lua and de-duplicate
      local archetypes = {}
      local seen = {}
      for block in res.stdout:gmatch("<archetype>(.-)</archetype>") do
        local gid = block:match("<groupId>%s*(.-)%s*</groupId>")
        local aid = block:match("<artifactId>%s*(.-)%s*</artifactId>")
        local ver = block:match("<version>%s*(.-)%s*</version>")
        local desc = block:match("<description>%s*(.-)%s*</description>") or ""
        if gid and aid and ver then
          local key = gid .. ":" .. aid
          if not seen[key] then
            seen[key] = true
            desc = desc:gsub("%s+", " "):gsub("^%s*", ""):gsub("%s*$", "")
            table.insert(archetypes, {
              groupId = gid,
              artifactId = aid,
              version = ver,
              desc = desc,
            })
          end
        end
      end

      -- Sort alphabetically by artifactId
      table.sort(archetypes, function(a, b)
        return a.artifactId:lower() < b.artifactId:lower()
      end)

      -- 4. Cache JSON to disk for instant subsequent loads (~3ms)
      pcall(function()
        local json_str = vim.json.encode(archetypes)
        vim.fn.writefile(vim.split(json_str, "\n"), cache_file)
      end)

      ui.notify_info(string.format("Loaded %d Maven Central archetypes.", #archetypes), "TetraVim Wizard")
      callback(archetypes)
    end)
  )
end

--- Open a beautiful searchable picker for all Maven Central archetypes.
---@param on_select fun(chosen: { groupId: string, artifactId: string, version: string, desc: string })
function M.search_maven_central(on_select)
  M.get_maven_central_archetypes(function(items, err)
    if err or #items == 0 then
      return
    end

    select_one(items, string.format("Maven Central Archetypes (%d available - type to filter):", #items), function(item)
      local desc_part = (item.desc and item.desc ~= "") and (" │ " .. item.desc) or ""
      return string.format("📦 %-32s (%s:%s)%s", item.artifactId, item.groupId, item.version, desc_part)
    end, function(chosen)
      on_select(chosen)
    end)
  end)
end

--- Maven Project Interactive Wizard with Archetype selection.
function M.new_maven_project()
  local prefs = load_prefs()
  select_one(M.MAVEN_ARCHETYPES, "Step 1/4: Select Maven Archetype", function(a)
    if a.custom then
      return string.format("%s%-32s │ %s", a.icon or "✨ ", a.name, a.desc)
    end
    return string.format("%s%-32s │ %s", a.icon or "📦 ", a.name, a.desc)
  end, function(chosen_arch)
    local function proceed_with_archetype(arch_group, arch_artifact, arch_ver)
      input_text("Step 2/4: Group ID", prefs.groupId or "com.example", function(group_id)
        input_text("Step 3/4: Artifact ID / Project Name", "my-app", function(artifact_id)
          local default_pkg = group_id .. "." .. artifact_id:gsub("[^%w_]", "_"):lower()
          input_text("Step 4/4: Package Name", default_pkg, function(pkg_name)
            local default_target = vim.fn.getcwd() .. "/" .. artifact_id
            input_text("Target Directory", default_target, function(target_dir)
              save_prefs({ groupId = group_id })
              M.generate_maven({
                archetypeGroupId = arch_group,
                archetype = arch_artifact,
                archetypeVersion = arch_ver,
                groupId = group_id,
                artifactId = artifact_id,
                packageName = pkg_name,
                targetDir = target_dir,
              })
            end)
          end)
        end)
      end)
    end

    if chosen_arch.search_central then
      M.search_maven_central(function(chosen_central)
        proceed_with_archetype(chosen_central.groupId, chosen_central.artifactId, chosen_central.version)
      end)
    elseif chosen_arch.custom then
      input_text("Archetype Group ID", "org.apache.maven.archetypes", function(custom_group)
        input_text("Archetype Artifact ID", "maven-archetype-quickstart", function(custom_artifact)
          input_text("Archetype Version", "RELEASE", function(custom_ver)
            proceed_with_archetype(custom_group, custom_artifact, custom_ver)
          end)
        end)
      end)
    else
      proceed_with_archetype(chosen_arch.groupId, chosen_arch.artifactId, chosen_arch.version)
    end
  end)
end

--- Generate Standard Gradle Project via gradle init.
---@param opts { type: string, dsl: string, testFramework?: string, projectName: string, packageName: string, targetDir: string }
---@param callback? fun(success: boolean, target_dir: string, err?: string)
function M.generate_gradle(opts, callback)
  if vim.fn.executable("gradle") == 0 then
    local err = "'gradle' is not found on $PATH."
    ui.notify_err(err, "TetraVim Wizard")
    if callback then
      callback(false, opts.targetDir, err)
    end
    return
  end

  local target_dir = vim.fn.fnamemodify(opts.targetDir, ":p"):gsub("/$", "")
  if vim.fn.isdirectory(target_dir) == 1 then
    local contents = vim.fn.glob(target_dir .. "/*", false, true)
    if #contents > 0 then
      local err = "Target directory is not empty: " .. target_dir
      ui.notify_err(err, "TetraVim Wizard")
      if callback then
        callback(false, target_dir, err)
      end
      return
    end
  else
    vim.fn.mkdir(target_dir, "p")
  end

  local cmd = {
    "gradle",
    "init",
    "--type",
    opts.type or "java-application",
    "--dsl",
    opts.dsl or "kotlin",
    "--test-framework",
    opts.testFramework or "junit-jupiter",
    "--project-name",
    opts.projectName,
    "--package",
    opts.packageName,
    "--no-incubating",
  }

  ui.notify_info(
    "Scaffolding Gradle project with " .. (opts.dsl == "kotlin" and "Kotlin DSL" or "Groovy DSL") .. "...",
    "TetraVim Wizard"
  )

  vim.system(
    cmd,
    { text = true, cwd = target_dir },
    vim.schedule_wrap(function(res)
      if res.code ~= 0 then
        local err = "Gradle init failed: " .. (res.stderr or res.stdout or "Error")
        ui.notify_err(err, "TetraVim Wizard")
        if callback then
          callback(false, target_dir, err)
        end
        return
      end

      open_and_init_project(target_dir, "Gradle (" .. (opts.dsl == "kotlin" and "Kotlin DSL" or "Groovy DSL") .. ")")
      if callback then
        callback(true, target_dir)
      end
    end)
  )
end

--- Gradle Project Interactive Wizard.
function M.new_gradle_project()
  local prefs = load_prefs()
  local project_types = {
    { type = "java-application", dsl = "kotlin", label = "Java Application (Kotlin DSL - build.gradle.kts)" },
    { type = "java-application", dsl = "groovy", label = "Java Application (Groovy DSL - build.gradle)" },
    { type = "kotlin-application", dsl = "kotlin", label = "Kotlin Application (Kotlin DSL - build.gradle.kts)" },
    { type = "java-library", dsl = "kotlin", label = "Java Library (Kotlin DSL - build.gradle.kts)" },
    { type = "java-library", dsl = "groovy", label = "Java Library (Groovy DSL - build.gradle)" },
  }

  select_one(project_types, "Step 1/3: Project Type & DSL", function(item)
    return item.label
  end, function(chosen)
    input_text("Step 2/3: Project Name", "my-gradle-app", function(project_name)
      local default_pkg = prefs.groupId or "com.example"
      input_text("Step 3/3: Package Name", default_pkg, function(pkg_name)
        local default_target = vim.fn.getcwd() .. "/" .. project_name
        input_text("Target Directory", default_target, function(target_dir)
          save_prefs({ groupId = pkg_name })
          M.generate_gradle({
            type = chosen.type,
            dsl = chosen.dsl,
            projectName = project_name,
            packageName = pkg_name,
            targetDir = target_dir,
          })
        end)
      end)
    end)
  end)
end

--- Interactive terminal generator for users who want the raw interactive prompt.
---@param tool "gradle"|"maven"
function M.interactive_terminal(tool)
  if tool == "gradle" then
    if vim.fn.executable("gradle") == 0 then
      ui.notify_err("'gradle' is not found on $PATH.", "TetraVim Wizard")
      return
    end
    input_text("Enter directory to initialize Gradle project in", vim.fn.getcwd(), function(target_dir)
      vim.fn.mkdir(target_dir, "p")
      term.run_term("gradle init", { cwd = target_dir, title = "Gradle Init" })
    end)
  elseif tool == "maven" then
    if vim.fn.executable("mvn") == 0 then
      ui.notify_err("'mvn' is not found on $PATH.", "TetraVim Wizard")
      return
    end
    input_text("Enter directory to initialize Maven project in", vim.fn.getcwd(), function(target_dir)
      vim.fn.mkdir(target_dir, "p")
      term.run_term("mvn archetype:generate", { cwd = target_dir, title = "Maven Archetype" })
    end)
  end
end

--- Main entry point for New Project Wizard (like IntelliJ's New Project dialog).
function M.create_project()
  local options = {
    {
      action = "spring",
      icon = "󱎘 ",
      label = "Spring Boot (start.spring.io)",
      desc = "Maven/Gradle, Java/Kotlin, curated dependencies, production-ready",
    },
    {
      action = "maven",
      icon = "📦 ",
      label = "Standard Maven Project",
      desc = "Java application or webapp using Maven Archetype",
    },
    {
      action = "gradle",
      icon = "🐘 ",
      label = "Standard Gradle Project",
      desc = "Java/Kotlin application or library with Kotlin/Groovy DSL",
    },
    {
      action = "terminal_gradle",
      icon = " ",
      label = "Interactive Gradle Init (Terminal)",
      desc = "Run official 'gradle init' interactive session in terminal",
    },
    {
      action = "terminal_maven",
      icon = " ",
      label = "Interactive Maven Archetype (Terminal)",
      desc = "Run official 'mvn archetype:generate' in terminal",
    },
  }

  select_one(options, "✨ New JVM Project Wizard (like IntelliJ IDEA):", function(item)
    return string.format("%s%-32s │ %s", item.icon, item.label, item.desc)
  end, function(choice)
    if choice.action == "spring" then
      M.new_spring_boot()
    elseif choice.action == "maven" then
      M.new_maven_project()
    elseif choice.action == "gradle" then
      M.new_gradle_project()
    elseif choice.action == "terminal_gradle" then
      M.interactive_terminal("gradle")
    elseif choice.action == "terminal_maven" then
      M.interactive_terminal("maven")
    end
  end)
end

return M
