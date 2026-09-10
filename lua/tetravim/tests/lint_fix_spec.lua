-- Unit tests for tetravim.util.edit.lint.fix_now / buffer_fix_argv (Epic 6).
--
-- `fix_now` is the buffer-scoped twin of `project_run("fix")` wired to
-- `<leader>xlf`: it rewrites the current buffer's file in place with the
-- language's own formatter. `vim.system` is always monkeypatched -- no real
-- binary is ever spawned.

describe("tetravim.util.edit.lint buffer autofix", function()
  local lint = require("tetravim.util.edit.lint")

  local notified
  local orig_notify, orig_system, orig_executable
  local system_calls
  local tmpfile

  before_each(function()
    notified = {}
    system_calls = {}

    orig_notify = vim.notify
    vim.notify = function(msg, level)
      table.insert(notified, { msg = tostring(msg), level = level })
    end

    orig_system = vim.system
    vim.system = function(cmd, opts, _cb)
      table.insert(system_calls, { cmd = cmd, opts = opts })
      return { wait = function() end }
    end

    orig_executable = vim.fn.executable
    vim.fn.executable = function(_name)
      return 1
    end

    tmpfile = vim.fn.tempname() .. ".java"
    local fd = assert(io.open(tmpfile, "w"))
    fd:write("class A {}\n")
    fd:close()
  end)

  after_each(function()
    vim.notify = orig_notify
    vim.system = orig_system
    vim.fn.executable = orig_executable
    if tmpfile then
      os.remove(tmpfile)
    end
    for _, b in ipairs(vim.api.nvim_list_bufs()) do
      if vim.api.nvim_buf_is_valid(b) and vim.api.nvim_buf_get_name(b):match("%.java$") then
        pcall(vim.api.nvim_buf_delete, b, { force = true })
      end
    end
  end)

  local function last_of(level)
    for i = #notified, 1, -1 do
      if notified[i].level == level then
        return notified[i].msg
      end
    end
    return nil
  end

  local function open_saved(path, ft)
    local buf = vim.api.nvim_create_buf(true, false)
    vim.api.nvim_buf_set_name(buf, path)
    vim.api.nvim_buf_call(buf, function()
      vim.cmd("edit!")
    end)
    vim.bo[buf].filetype = ft
    vim.bo[buf].modified = false
    vim.api.nvim_set_current_buf(buf)
    return buf
  end

  describe("buffer_fix_argv", function()
    it("covers the four JVM-stack filetypes with the file appended last", function()
      for _, ft in ipairs({ "kotlin", "java", "scala", "groovy" }) do
        assert.are.equal("function", type(lint.buffer_fix_argv[ft]))
        local argv = lint.buffer_fix_argv[ft]("/x/File.ext")
        assert.are.equal("/x/File.ext", argv[#argv])
      end
      assert.are.same({ "google-java-format", "--replace", "/x/A.java" }, lint.buffer_fix_argv.java("/x/A.java"))
      assert.are.same({ "ktlint", "--format", "/x/A.kt" }, lint.buffer_fix_argv.kotlin("/x/A.kt"))
    end)
  end)

  describe("fix_now", function()
    it("warns and spawns nothing for a filetype with no autofix tool", function()
      local buf = open_saved(tmpfile, "text")
      lint.fix_now(buf)
      assert.are.equal(0, #system_calls)
      assert.is_truthy(last_of(vim.log.levels.WARN):match("No buffer autofix tool"))
    end)

    it("refuses a buffer not backed by a file on disk", function()
      local buf = vim.api.nvim_create_buf(true, false)
      vim.bo[buf].filetype = "java"
      vim.api.nvim_set_current_buf(buf)
      lint.fix_now(buf)
      assert.are.equal(0, #system_calls)
      assert.is_truthy(last_of(vim.log.levels.ERROR):match("not backed by a file"))
    end)

    it("refuses a modified buffer -- the fixer rewrites the file on disk", function()
      local buf = open_saved(tmpfile, "java")
      vim.bo[buf].modified = true
      lint.fix_now(buf)
      assert.are.equal(0, #system_calls)
      assert.is_truthy(last_of(vim.log.levels.WARN):match("save the buffer first"))
    end)

    it("warns when the formatter binary is not installed", function()
      vim.fn.executable = function()
        return 0
      end
      local buf = open_saved(tmpfile, "java")
      lint.fix_now(buf)
      assert.are.equal(0, #system_calls)
      assert.is_truthy(last_of(vim.log.levels.WARN):match("is not installed"))
    end)

    it("spawns the language formatter against the saved file path", function()
      local buf = open_saved(tmpfile, "java")
      lint.fix_now(buf)
      assert.are.equal(1, #system_calls)
      assert.are.same({ "google-java-format", "--replace", tmpfile }, system_calls[1].cmd)
    end)
  end)
end)
