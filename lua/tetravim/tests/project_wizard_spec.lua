-- Tests for TetraVim Project Generator Wizard (tetravim.util.jvm.project_wizard)

describe("tetravim.util.jvm.project_wizard", function()
  local wizard = require("tetravim.util.jvm.project_wizard")

  it("exposes expected public wizard API functions", function()
    assert.is_function(wizard.create_project)
    assert.is_function(wizard.new_spring_boot)
    assert.is_function(wizard.new_maven_project)
    assert.is_function(wizard.new_gradle_project)
    assert.is_function(wizard.interactive_terminal)
    assert.is_function(wizard.generate_spring)
    assert.is_function(wizard.generate_maven)
    assert.is_function(wizard.generate_gradle)
    assert.is_function(wizard.get_maven_central_archetypes)
    assert.is_function(wizard.search_maven_central)
    assert.is_function(wizard.get_spring_initializr_dependencies)
    assert.is_function(wizard.get_spring_boot_versions)
  end)

  it("provides curated Spring Boot dependencies catalog", function()
    assert.is_table(wizard.SPRING_DEPENDENCIES)
    assert.is_true(#wizard.SPRING_DEPENDENCIES > 10)
    for _, dep in ipairs(wizard.SPRING_DEPENDENCIES) do
      assert.is_string(dep.id)
      assert.is_string(dep.name)
      assert.is_string(dep.desc)
    end
  end)

  it("provides curated Spring Boot presets", function()
    assert.is_table(wizard.SPRING_PRESETS)
    assert.is_true(#wizard.SPRING_PRESETS >= 5)
    for _, preset in ipairs(wizard.SPRING_PRESETS) do
      assert.is_string(preset.name)
    end
  end)

  it("provides curated Maven archetypes catalog", function()
    assert.is_table(wizard.MAVEN_ARCHETYPES)
    assert.is_true(#wizard.MAVEN_ARCHETYPES >= 5)
    for _, arch in ipairs(wizard.MAVEN_ARCHETYPES) do
      assert.is_string(arch.name)
      assert.is_string(arch.desc)
    end
  end)

  it("fetches and parses Maven Central archetype catalog", function()
    local done = false
    local count = 0
    wizard.get_maven_central_archetypes(function(items, err)
      done = true
      count = #items
      assert.is_nil(err)
      assert.is_true(#items > 1000)
    end)
    vim.wait(5000, function()
      return done
    end)
    assert.is_true(done)
    assert.is_true(count > 1000)
  end)

  it("fetches and parses Spring Initializr dependencies", function()
    local done = false
    local count = 0
    wizard.get_spring_initializr_dependencies(function(deps, err)
      done = true
      count = #deps
      assert.is_nil(err)
      assert.is_true(#deps >= 20)
    end)
    vim.wait(5000, function()
      return done
    end)
    assert.is_true(done)
    assert.is_true(count >= 20)
  end)

  it("fetches and parses Spring Boot versions", function()
    local done = false
    local versions_count = 0
    wizard.get_spring_boot_versions(function(versions)
      done = true
      versions_count = #versions
      assert.is_true(#versions >= 1)
      assert.is_string(versions[1].name)
    end)
    vim.wait(5000, function()
      return done
    end)
    assert.is_true(done)
    assert.is_true(versions_count >= 1)
  end)

  it("refuses to generate Spring Boot project into a non-empty directory", function()
    local temp_dir = vim.fn.tempname()
    vim.fn.mkdir(temp_dir, "p")
    local dummy_file = temp_dir .. "/dummy.txt"
    vim.fn.writefile({ "test" }, dummy_file)

    local called = false
    local success_result = nil
    local err_msg = nil

    wizard.generate_spring({
      type = "maven-project",
      language = "java",
      groupId = "com.example",
      artifactId = "demo",
      javaVersion = "21",
      dependencies = { "web" },
      targetDir = temp_dir,
    }, function(success, target_dir, err)
      called = true
      success_result = success
      err_msg = err
    end)

    assert.is_true(called)
    assert.is_false(success_result)
    assert.is_true(err_msg:find("not empty") ~= nil)

    vim.fn.delete(temp_dir, "rf")
  end)

  it("registers <leader>jn keymaps and user commands", function()
    local jvm = require("tetravim.util.jvm.jvm")
    jvm.setup_keymaps()

    -- Verify user commands exist
    local cmds = vim.api.nvim_get_commands({})
    assert.is_not_nil(cmds["TetraVimNewProject"])
    assert.is_not_nil(cmds["JVMNewProject"])

    -- Verify WhichKey spec includes <leader>jn
    local spec = jvm.whichkey_spec()
    local found_jn = false
    for _, item in ipairs(spec) do
      if item[1] == "<leader>jn" then
        found_jn = true
        assert.are.equal("new project", item.group)
        break
      end
    end
    assert.is_true(found_jn)
  end)
end)
