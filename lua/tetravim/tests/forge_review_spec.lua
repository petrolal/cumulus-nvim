local assert = require("luassert")

describe("Code Reviews Plugin Configuration", function()
  it("registers <leader>gr keymaps in tools-review spec", function()
    local spec = require("tetravim.plugins.tools-review")
    assert.is_table(spec)
    assert.is_table(spec[1])
    assert.are.equal("sindrets/diffview.nvim", spec[1][1])

    local keys = spec[1].keys
    assert.is_table(keys)

    local found_p = false
    local found_c = false
    local found_C = false

    for _, keymap in ipairs(keys) do
      if keymap[1] == "<leader>grp" then
        found_p = true
      end
      if keymap[1] == "<leader>grc" then
        found_c = true
      end
      if keymap[1] == "<leader>grC" then
        found_C = true
      end
    end

    assert.is_true(found_p, "<leader>grp not found")
    assert.is_true(found_c, "<leader>grc not found")
    assert.is_true(found_C, "<leader>grC not found")
  end)

  it("registers <leader>gr group in ui-whichkey spec", function()
    local wk_spec = require("tetravim.plugins.ui-whichkey")
    assert.is_table(wk_spec)

    local opts_func = wk_spec[1].opts
    assert.is_function(opts_func)

    package.loaded["tetravim.core.lang-keymaps"] = {
      whichkey_spec = function()
        return {}
      end,
    }
    package.loaded["tetravim.util.jvm"] = {
      whichkey_spec = function()
        return {}
      end,
    }

    local mock_opts = { spec = {} }
    local result = opts_func(nil, mock_opts)

    local found = false
    for _, item in ipairs(result.spec) do
      if item[1] == "<leader>gr" and item.group == "git review" then
        found = true
        break
      end
    end
    assert.is_true(found, "<leader>gr group not found in which-key spec")
  end)
end)

-- Migrated from scripts/validate-4-2.sh (steps [2/3] and [3/3]). The diffview
-- runtime walk in scripts/validate-4-1.sh cannot move here (no plugins in the
-- plenary busted subprocess); this covers the pure util/forge dispatch instead.
describe("util/forge shell dispatch (pure, all IO mocked)", function()
  local saved = {}
  local function save(tbl, key)
    saved[#saved + 1] = { tbl, key, tbl[key] }
  end

  before_each(function()
    saved = {}
    package.loaded["tetravim.util.forge"] = nil
  end)

  after_each(function()
    for i = #saved, 1, -1 do
      saved[i][1][saved[i][2]] = saved[i][3]
    end
    package.loaded["tetravim.util.forge"] = nil
    package.loaded["snacks"] = nil
  end)

  it("drives gh pr list / checkout / comment / view without spawning real processes", function()
    local system_calls = {}
    save(vim, "system")
    vim.system = function(cmd, _opts, cb)
      table.insert(system_calls, cmd)
      if cb then
        if cmd[1] == "git" and cmd[2] == "fetch" then
          cb({ code = 0, stdout = "" })
        else
          cb({ code = 0, stdout = "#123 mock\tmock-ref\tmock-base\n" })
        end
      end
      return { wait = function()
        return { code = 0, stdout = "github" }
      end }
    end
    save(vim, "schedule_wrap")
    vim.schedule_wrap = function(cb)
      return cb
    end

    package.loaded["snacks"] = {
      picker = {
        select = function(items, _opts, cb)
          if items and #items > 0 then
            cb(items[1])
          else
            cb({ number = "123", ref = "mock-ref", base = "mock-base" })
          end
        end,
      },
    }
    package.loaded["tetravim.util.ui"] = {
      notify_info = function() end,
      notify_err = function() end,
      notify_warn = function() end,
    }

    local git = require("tetravim.util.git")
    save(git, "guard")
    save(git, "repo_root")
    git.guard = function()
      return true
    end
    git.repo_root = function()
      return "/mock"
    end

    save(vim, "cmd")
    vim.cmd = function() end
    save(vim.api, "nvim_buf_get_lines")
    save(vim.api, "nvim_buf_set_lines")
    save(vim.api, "nvim_win_set_cursor")
    save(vim.api, "nvim_buf_set_name")
    save(vim.api, "nvim_buf_delete")
    vim.api.nvim_buf_get_lines = function()
      return { "<!-- Enter comment. Save (:w) to submit. -->", "Test comment body" }
    end
    vim.api.nvim_buf_set_lines = function() end
    vim.api.nvim_win_set_cursor = function() end
    vim.api.nvim_buf_set_name = function() end
    vim.api.nvim_buf_delete = function() end

    local forge = require("tetravim.util.forge")
    forge.list_and_review_prs()
    forge.checkout_pr()
    forge.add_comment()
    vim.api.nvim_exec_autocmds("BufWriteCmd", { buffer = vim.api.nvim_get_current_buf() })

    local seen = { list = false, checkout = false, comment = false, view = false }
    for _, cmd in ipairs(system_calls) do
      local c = table.concat(cmd, " ")
      if c:match("gh pr list") then
        seen.list = true
      end
      if c:match("gh pr checkout 123") then
        seen.checkout = true
      end
      if c:match("gh pr comment 123 %-%-body Test comment body") then
        seen.comment = true
      end
      if c:match("gh pr view 123") then
        seen.view = true
      end
    end
    assert.is_true(seen.list, "missing gh pr list")
    assert.is_true(seen.checkout, "missing gh pr checkout")
    assert.is_true(seen.comment, "missing gh pr comment")
    assert.is_true(seen.view, "missing gh pr view")
  end)

  it("tetravim.health.check() runs without error", function()
    assert.has_no.errors(function()
      require("tetravim.health").check()
    end)
  end)
end)
