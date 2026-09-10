-- Embedded Database Explorer (SPEC-3.1) -- credential auto-discovery tests.
--
-- Migrated from scripts/validate-db.sh: the db.lua module shape, the
-- tools-dadbod.lua plugin-spec wiring (treesitter ensure_installed, init()'s
-- vim.g.dbs assignment + its error path, the DirChanged re-discovery
-- autocrat) and the entire discover_datasources() parsing / precedence /
-- placeholder / malformed-block matrix now live here.
--
-- What stays in the shell script needs the `cmp` plugin, absent from the
-- plenary busted subprocess: the vim-dadbod-completion cmp-source
-- registration (fresh / re-fired / already-open sql buffers, merge-not-
-- replace).

describe("tetravim embedded DB explorer (SPEC-3.1)", function()
  local db = require("tetravim.util.db")

  local function read(path)
    local fh = assert(io.open(path, "r"))
    local body = fh:read("*a")
    fh:close()
    return body
  end

  local tmp
  local orig_cwd

  local function write(rel, lines)
    local path = tmp .. "/" .. rel
    vim.fn.mkdir(vim.fn.fnamemodify(path, ":h"), "p")
    vim.fn.writefile(lines, path)
    return path
  end

  before_each(function()
    orig_cwd = vim.fn.getcwd()
    tmp = vim.fn.tempname()
    vim.fn.mkdir(tmp, "p")

    write("props-only/src/main/resources/application.properties", {
      "server.port=8080",
      "spring.datasource.url=jdbc:postgresql://localhost:5432/mydb",
      "spring.datasource.username=root",
      "spring.datasource.password=secret",
    })

    write("yml-only/src/main/resources/application.yml", {
      "server:",
      "  port: 8080",
      "spring:",
      "  datasource:",
      "    url: jdbc:mysql://localhost:3306/otherdb",
      "    username: admin",
      "    password: hunter2",
    })

    write("yaml-only/src/main/resources/application.yaml", {
      "spring:",
      "  datasource:",
      "    url: jdbc:mariadb://localhost:3307/yamldb",
      "    username: sa",
      "    password: sapass",
    })

    write("both/src/main/resources/application.properties", {
      "spring.datasource.url=jdbc:postgresql://props-host:5432/propsdb",
      "spring.datasource.username=propsuser",
      "spring.datasource.password=propspass",
    })
    write("both/src/main/resources/application.yml", {
      "spring:",
      "  datasource:",
      "    url: jdbc:mysql://yml-host:3306/ymldb",
      "    username: ymluser",
      "    password: ymlpass",
    })

    write("none/src/main/resources/application.properties", {
      "server.port=8080",
      "spring.application.name=none-demo",
    })

    write("malformed/src/main/resources/application.properties", {
      "spring.datasource.url=jdbc:postgresql://localhost:5432/incomplete",
    })

    write("reserved-chars/src/main/resources/application.properties", {
      "spring.datasource.url=jdbc:postgresql://localhost:5432/mydb",
      "spring.datasource.username=user@corp",
      "spring.datasource.password=p@ss:word/1",
    })

    write("placeholder-with-default/src/main/resources/application.yaml", {
      "spring:",
      "  datasource:",
      "    url: ${SPRING_DATASOURCE_URL:jdbc:postgresql://localhost:5432/ahun_duty}",
      "    username: ${SPRING_DATASOURCE_USERNAME:postgres}",
      "    password: ${SPRING_DATASOURCE_PASSWORD:postgres}",
    })

    write("placeholder-unresolved/src/main/resources/application.yaml", {
      "spring:",
      "  datasource:",
      "    url: ${SPRING_DATASOURCE_URL}",
      "    username: ${SPRING_DATASOURCE_USERNAME}",
      "    password: ${SPRING_DATASOURCE_PASSWORD}",
    })

    write("dotenv-resolved/src/main/resources/application.yaml", {
      "spring:",
      "  datasource:",
      "    url: ${SPRING_DATASOURCE_URL}",
      "    username: ${SPRING_DATASOURCE_USERNAME}",
      "    password: ${SPRING_DATASOURCE_PASSWORD}",
    })
    write("dotenv-resolved/.env", {
      "# comment and blank line should be ignored",
      "",
      "export SPRING_DATASOURCE_URL=jdbc:postgresql://localhost:5432/ahun_members_service",
      "SPRING_DATASOURCE_USERNAME=ahun",
      'SPRING_DATASOURCE_PASSWORD="ahun"',
    })

    write("yaml-empty-password/src/main/resources/application.yml", {
      "spring:",
      "  datasource:",
      "    url: jdbc:postgresql://localhost:5432/db",
      "    username: postgres",
      '    password: ""',
    })

    write("properties-colon-sep/src/main/resources/application.properties", {
      "spring.datasource.url: jdbc:postgresql://localhost:5432/db",
      "spring.datasource.username postgres",
      "spring.datasource.password: secret",
    })

    write("empty-env-var/src/main/resources/application.properties", {
      "spring.datasource.url=jdbc:postgresql://localhost:5432/db",
      "spring.datasource.username=postgres",
      "spring.datasource.password=${BMAD_REVIEW_EMPTY_PW}",
    })

    write("jdbc-has-credentials/src/main/resources/application.properties", {
      "spring.datasource.url=jdbc:postgresql://admin:adminpw@localhost:5432/db",
      "spring.datasource.username=postgres",
      "spring.datasource.password=secret",
    })

    write("nested-placeholder/src/main/resources/application.properties", {
      "spring.datasource.url=jdbc:postgresql://localhost:5432/db",
      "spring.datasource.username=postgres",
      "spring.datasource.password=${OUTER:${INNER}}",
    })

    local deep = "max-depth"
    for i = 1, 10 do
      deep = deep .. "/d" .. i
    end
    write(deep .. "/application.properties", {
      "spring.datasource.url=jdbc:postgresql://localhost:5432/db",
      "spring.datasource.username=postgres",
      "spring.datasource.password=secret",
    })

    write("unterminated-placeholder/src/main/resources/application.properties", {
      "spring.datasource.url=jdbc:postgresql://localhost:5432/db",
      "spring.datasource.username=postgres",
      "spring.datasource.password=${TRUNCATED",
    })

    write("nameless-placeholder/src/main/resources/application.properties", {
      "spring.datasource.url=jdbc:postgresql://localhost:5432/db",
      "spring.datasource.username=postgres",
      "spring.datasource.password=${}",
    })
    write("nameless-placeholder-with-default/src/main/resources/application.properties", {
      "spring.datasource.url=jdbc:postgresql://localhost:5432/db",
      "spring.datasource.username=postgres",
      "spring.datasource.password=${:default}",
    })

    write("dotenv-empty-wins/src/main/resources/application.yaml", {
      "spring:",
      "  datasource:",
      "    url: jdbc:postgresql://localhost:5432/db",
      "    username: postgres",
      "    password: ${DOTENV_EMPTY_PW:somedefault}",
    })
    write("dotenv-empty-wins/.env", { "DOTENV_EMPTY_PW=" })

    write("dirchanged-a/src/main/resources/application.properties", {
      "spring.datasource.url=jdbc:postgresql://localhost:5432/dirchanged_a",
      "spring.datasource.username=usera",
      "spring.datasource.password=passa",
    })
    write("dirchanged-b/src/main/resources/application.properties", {
      "spring.datasource.url=jdbc:postgresql://localhost:5432/dirchanged_b",
      "spring.datasource.username=userb",
      "spring.datasource.password=passb",
    })
    write("dirchanged-none/src/main/resources/application.properties", { "server.port=8080" })

    write("empty-default-placeholder/src/main/resources/application.yaml", {
      "spring:",
      "  datasource:",
      "    url: jdbc:postgresql://localhost:5432/emptydef",
      "    username: postgres",
      "    password: ${CR_20260901_UNSET_PW:}",
    })

    write("test-resources-excluded/src/main/resources/application.properties", {
      "spring.datasource.url=jdbc:postgresql://localhost:5432/prod_db",
      "spring.datasource.username=produser",
      "spring.datasource.password=prodpass",
    })
    write("test-resources-excluded/src/test/resources/application.properties", {
      "spring.datasource.url=jdbc:h2:mem:testdb",
      "spring.datasource.username=sa",
      "spring.datasource.password=",
    })

    write("multi-module/mod-a/src/main/resources/application.properties", {
      "spring.datasource.url=jdbc:postgresql://localhost:5432/mod_a",
      "spring.datasource.username=usera",
      "spring.datasource.password=passa",
    })
    write("multi-module/mod-b/src/main/resources/application.properties", {
      "spring.datasource.url=jdbc:postgresql://localhost:5432/mod_b",
      "spring.datasource.username=userb",
      "spring.datasource.password=passb",
    })

    write("props-keyless-yml-valid/src/main/resources/application.properties", { "server.port=9090" })
    write("props-keyless-yml-valid/src/main/resources/application.yml", {
      "spring:",
      "  datasource:",
      "    url: jdbc:mysql://localhost:3306/fellthrough",
      "    username: ymluser",
      "    password: ymlpass",
    })
  end)

  after_each(function()
    vim.fn.chdir(orig_cwd)
    pcall(vim.fn.delete, tmp, "rf")
  end)

  local function capture_notify(fn)
    local notified = {}
    local orig = vim.notify
    vim.notify = function(msg, level)
      table.insert(notified, { msg = msg, level = level })
    end
    local ok, result = pcall(fn)
    vim.notify = orig
    assert(ok, result)
    return result, notified
  end

  local function has_warn(notified, pat)
    for _, n in ipairs(notified) do
      if n.level == vim.log.levels.WARN and (not pat or tostring(n.msg):match(pat)) then
        return true
      end
    end
    return false
  end

  describe("module + plugin-spec wiring", function()
    it(
      "db.lua exposes discover_datasources; tools-dadbod.lua wires the cmp source, vim.g.dbs and treesitter",
      function()
        assert.is_function(db.discover_datasources)

        local src = read("lua/tetravim/plugins/tools-dadbod.lua")
        assert.is_truthy(src:match("vim%-dadbod%-completion"))
        assert.is_truthy(src:match("tetravim%.util%.db"))
        assert.is_truthy(src:match("vim%.g%.dbs"))
        assert.is_truthy(src:match('"sql"'))
        assert.is_truthy(src:match("FileType"))
      end
    )

    it('folds "sql" into nvim-treesitter ensure_installed via the spec opts function', function()
      local spec = require("tetravim.plugins.tools-dadbod")
      assert.are.equal("nvim-treesitter/nvim-treesitter", spec[2][1])
      assert.is_function(spec[2].opts)

      local opts = { ensure_installed = { "lua", "vim" } }
      spec[2].opts(nil, opts)
      assert.is_true(vim.tbl_contains(opts.ensure_installed, "sql"))
    end)

    it("init() sets vim.g.dbs to exactly what discover_datasources() returns for the cwd", function()
      vim.fn.chdir(tmp .. "/props-only")
      local expected = db.discover_datasources(vim.fn.getcwd())
      assert.are.equal(1, #expected)

      vim.g.dbs = nil
      local spec = require("tetravim.plugins.tools-dadbod")
      assert.is_function(spec[1].init)
      spec[1].init()

      assert.is_not_nil(vim.g.dbs)
      assert.is_true(vim.deep_equal(vim.g.dbs, expected))
      vim.g.dbs = nil
    end)

    it("init() surfaces a WARN (and leaves vim.g.dbs unset) when discovery errors", function()
      local orig_loaded = package.loaded["tetravim.util.db"]
      package.loaded["tetravim.util.db"] = {
        discover_datasources = function()
          error("simulated discovery bug")
        end,
      }

      vim.g.dbs = nil
      local _, notified = capture_notify(function()
        require("tetravim.plugins.tools-dadbod")[1].init()
      end)

      package.loaded["tetravim.util.db"] = orig_loaded

      assert.is_nil(vim.g.dbs)
      assert.is_true(has_warn(notified))
    end)

    it(
      "DirChanged re-runs discovery on a global cd only, and clears vim.g.dbs for a zero-datasource project",
      function()
        local spec = require("tetravim.plugins.tools-dadbod")
        spec[1].config()

        vim.g.dbs = nil
        vim.fn.chdir(tmp .. "/dirchanged-a")
        local expected_a = db.discover_datasources(vim.fn.getcwd())
        assert.are.equal(1, #expected_a)
        assert.is_true(vim.deep_equal(vim.g.dbs, expected_a))

        vim.fn.chdir(tmp .. "/dirchanged-b")
        local expected_b = db.discover_datasources(vim.fn.getcwd())
        assert.is_true(vim.deep_equal(vim.g.dbs, expected_b))
        assert.is_false(vim.deep_equal(vim.g.dbs, expected_a))

        vim.fn.chdir(tmp .. "/dirchanged-none")
        assert.is_nil(vim.g.dbs)

        -- window-local :lcd must NOT re-run discovery (kept last: lcd is sticky)
        local before_lcd = vim.g.dbs
        vim.cmd("lcd " .. vim.fn.fnameescape(tmp .. "/dirchanged-a"))
        assert.is_true(vim.deep_equal(vim.g.dbs, before_lcd))
      end
    )
  end)

  describe("discover_datasources parsing / precedence", function()
    it("application.properties -> one dadbod connection URL", function()
      local dbs = db.discover_datasources(tmp .. "/props-only")
      assert.are.equal(1, #dbs)
      assert.are.equal("props-only", dbs[1].name)
      assert.are.equal("postgresql://root:secret@localhost:5432/mydb", dbs[1].url)
    end)

    it("application.yml and application.yaml each parse a nested spring.datasource block", function()
      local yml = db.discover_datasources(tmp .. "/yml-only")
      assert.are.equal(1, #yml)
      assert.are.equal("yml-only", yml[1].name)
      assert.are.equal("mysql://admin:hunter2@localhost:3306/otherdb", yml[1].url)

      local yaml = db.discover_datasources(tmp .. "/yaml-only")
      assert.are.equal(1, #yaml)
      assert.are.equal("mariadb://sa:sapass@localhost:3307/yamldb", yaml[1].url)
    end)

    it("application.properties wins outright when both it and application.yml are present", function()
      local dbs = db.discover_datasources(tmp .. "/both")
      assert.are.equal(1, #dbs)
      assert.are.equal("postgresql://propsuser:propspass@props-host:5432/propsdb", dbs[1].url)
      assert.is_nil(dbs[1].url:find("yml-host", 1, true))
    end)

    it("no spring.datasource.* keys anywhere -> empty table, not an error", function()
      local dbs = db.discover_datasources(tmp .. "/none")
      assert.is_table(dbs)
      assert.are.equal(0, #dbs)
    end)

    it("a partial/malformed datasource block (url only) is skipped with a warning", function()
      local dbs, notified = capture_notify(function()
        return db.discover_datasources(tmp .. "/malformed")
      end)
      assert.are.equal(0, #dbs)
      assert.is_true(has_warn(notified))
    end)

    it("credentials with URL-reserved characters are percent-encoded", function()
      local dbs = db.discover_datasources(tmp .. "/reserved-chars")
      assert.are.equal(1, #dbs)
      assert.are.equal("postgresql://user%40corp:p%40ss%3Aword%2F1@localhost:5432/mydb", dbs[1].url)
    end)

    it("a keyless .properties falls through to a valid .yml in the same root", function()
      local dbs = db.discover_datasources(tmp .. "/props-keyless-yml-valid")
      assert.are.equal(1, #dbs)
      assert.is_truthy(dbs[1].url:match("@localhost:3306/fellthrough$"))
    end)

    it("src/test/resources config is excluded from discovery", function()
      local dbs = db.discover_datasources(tmp .. "/test-resources-excluded")
      assert.are.equal(1, #dbs)
      assert.is_truthy(dbs[1].url:match("/prod_db"))
      assert.is_nil(dbs[1].url:match("h2:mem"))
    end)

    it("a multi-module root yields one distinct, path-qualified entry per module", function()
      local dbs = db.discover_datasources(tmp .. "/multi-module")
      assert.are.equal(2, #dbs)
      assert.are_not.equal(dbs[1].name, dbs[2].name)
      assert.is_truthy(dbs[1].name:match("%("))
      assert.is_truthy(dbs[2].name:match("%("))
    end)
  end)

  describe("discover_datasources placeholder / env resolution", function()
    it("${VAR:default} resolves via env-var-wins-over-default, JDBC-shaped defaults intact", function()
      local root = tmp .. "/placeholder-with-default"

      local dbs = db.discover_datasources(root)
      assert.are.equal(1, #dbs)
      assert.are.equal("postgresql://postgres:postgres@localhost:5432/ahun_duty", dbs[1].url)

      vim.env.SPRING_DATASOURCE_USERNAME = "envwins"
      local dbs2 = db.discover_datasources(root)
      vim.env.SPRING_DATASOURCE_USERNAME = nil
      assert.are.equal("postgresql://envwins:postgres@localhost:5432/ahun_duty", dbs2[1].url)
    end)

    it("${VAR} with no default and no env var is skipped with a warning naming the variable", function()
      local dbs, notified = capture_notify(function()
        return db.discover_datasources(tmp .. "/placeholder-unresolved")
      end)
      assert.are.equal(0, #dbs)
      assert.is_true(has_warn(notified, "SPRING_DATASOURCE_URL"))
    end)

    it("${VAR} placeholders resolve via a project-root .env file; a real env var still wins", function()
      local root = tmp .. "/dotenv-resolved"

      local dbs = db.discover_datasources(root)
      assert.are.equal(1, #dbs)
      assert.are.equal("postgresql://ahun:ahun@localhost:5432/ahun_members_service", dbs[1].url)

      vim.env.SPRING_DATASOURCE_USERNAME = "realenvwins"
      local dbs2 = db.discover_datasources(root)
      vim.env.SPRING_DATASOURCE_USERNAME = nil
      assert.are.equal("postgresql://realenvwins:ahun@localhost:5432/ahun_members_service", dbs2[1].url)
    end)

    it("an explicit YAML empty-string scalar is a real empty password, not missing", function()
      local dbs = db.discover_datasources(tmp .. "/yaml-empty-password")
      assert.are.equal(1, #dbs)
      assert.are.equal("postgresql://postgres:@localhost:5432/db", dbs[1].url)
    end)

    it(".properties accepts ':' (and bare whitespace) as the key/value separator", function()
      local dbs = db.discover_datasources(tmp .. "/properties-colon-sep")
      assert.are.equal(1, #dbs)
      assert.are.equal("postgresql://postgres:secret@localhost:5432/db", dbs[1].url)
    end)

    it("an env var explicitly set to empty resolves as empty, not unset", function()
      vim.fn.setenv("BMAD_REVIEW_EMPTY_PW", "")
      local dbs = db.discover_datasources(tmp .. "/empty-env-var")
      vim.fn.setenv("BMAD_REVIEW_EMPTY_PW", vim.NIL)
      assert.are.equal(1, #dbs)
      assert.are.equal("postgresql://postgres:@localhost:5432/db", dbs[1].url)
    end)

    it("a JDBC URL that already carries credentials is skipped with a warning, never double-spliced", function()
      local dbs, notified = capture_notify(function()
        return db.discover_datasources(tmp .. "/jdbc-has-credentials")
      end)
      assert.are.equal(0, #dbs)
      assert.is_true(has_warn(notified))
    end)

    it("a nested ${OUTER:${INNER}} default is reported unresolved naming OUTER, never corrupted", function()
      local dbs, notified = capture_notify(function()
        return db.discover_datasources(tmp .. "/nested-placeholder")
      end)
      assert.are.equal(0, #dbs)
      local mentions_outer = false
      for _, n in ipairs(notified) do
        if tostring(n.msg):match("OUTER") then
          mentions_outer = true
        end
      end
      assert.is_true(mentions_outer)
    end)

    it("hitting the MAX_DEPTH scan limit warns that coverage may be incomplete", function()
      local dbs, notified = capture_notify(function()
        return db.discover_datasources(tmp .. "/max-depth")
      end)
      assert.are.equal(0, #dbs)
      local warned_depth = false
      for _, n in ipairs(notified) do
        if tostring(n.msg):match("depth limit") then
          warned_depth = true
        end
      end
      assert.is_true(warned_depth)
    end)

    it("an unterminated ${VAR placeholder is reported unresolved, never thrown from", function()
      local call_ok, dbs = pcall(db.discover_datasources, tmp .. "/unterminated-placeholder")
      assert.is_true(call_ok)
      assert.are.equal(0, #dbs)
    end)

    it("a nameless ${} / ${:default} placeholder does not throw and is reported unresolved", function()
      for _, fixture in ipairs({ "nameless-placeholder", "nameless-placeholder-with-default" }) do
        local dbs, notified = capture_notify(function()
          local call_ok, result = pcall(db.discover_datasources, tmp .. "/" .. fixture)
          assert(call_ok, fixture .. ": threw: " .. tostring(result))
          return result
        end)
        assert.are.equal(0, #dbs, fixture)
        assert.is_true(has_warn(notified), fixture)
      end
    end)

    it("an explicitly-empty .env value wins over a placeholder's own default", function()
      local dbs = db.discover_datasources(tmp .. "/dotenv-empty-wins")
      assert.are.equal(1, #dbs)
      assert.are.equal("postgresql://postgres:@localhost:5432/db", dbs[1].url)
    end)

    it("${VAR:} (explicit empty default) resolves to an empty string and builds a connection", function()
      local dbs = db.discover_datasources(tmp .. "/empty-default-placeholder")
      assert.are.equal(1, #dbs)
      assert.is_truthy(dbs[1].url:match("://postgres:@localhost:5432/emptydef"))
    end)
  end)
end)
