-- SPEC-2.2: Intelligent Extraction -- static shape tests

describe("Extract (SPEC-2.2)", function()
  describe("tetravim.util.edit.extract", function()
    it("should expose extract_interface and inline", function()
      local extract = require("tetravim.util.edit.extract")
      assert.is_table(extract)
      assert.is_function(extract.extract_interface)
      assert.is_function(extract.inline)
      assert.is_function(extract.extract_method)
      assert.is_function(extract.extract_variable)
      assert.is_function(extract.extract_constant)
      assert.is_number(extract.ACTION_TIMEOUT_MS)
    end)

    it("should reject a second action while one is already in flight (shared action_lock.lua)", function()
      local extract = require("tetravim.util.edit.extract")
      local action_lock = require("tetravim.util.action_lock")
      local notified = {}
      local orig_notify = vim.notify
      vim.notify = function(msg, level)
        table.insert(notified, { msg = msg, level = level })
      end

      action_lock.acquire()
      extract.extract_interface()
      action_lock.release()

      vim.notify = orig_notify
      assert.are.equal(1, #notified)
      assert.are.equal(vim.log.levels.WARN, notified[1].level)
      assert.is_truthy(notified[1].msg:match("already in progress"))
    end)
  end)

  describe("Buffer-local <leader>ce and <leader>ci override wiring", function()
    it(
      "ftplugin/java.lua should install REAL buffer-local extraction mappings (ce/ci/cm/cv/cc) that dispatch into tetravim.util.edit.extract",
      function()
        -- Dynamic, mirroring refactor_spec.lua's <leader>cr wiring test:
        -- load the REAL ftplugin/java.lua, capture the on_attach it hands
        -- to jdtls.start_or_attach (mocked so no real jdtls process is
        -- needed), invoke it against a scratch buffer, and assert the
        -- resulting keymaps are REAL, callable mappings -- not just source
        -- text matching a string pattern, which would pass even if the
        -- keymap were dead code never actually reached at runtime.
        local old_require = _G.require
        local captured_on_attach = nil
        _G.require = function(mod)
          if mod == "jdtls" then
            return {
              -- ftplugin/java.lua calls jdtls.setup.find_root(...) at
              -- module-load time (as a root_dir fallback) BEFORE
              -- start_or_attach is ever invoked -- the mock needs this
              -- too, or loading the file errors before on_attach is even
              -- captured.
              setup = {
                find_root = function()
                  return vim.fn.getcwd()
                end,
              },
              -- on_attach calls jdtls.setup_dap(...) unconditionally (not
              -- pcall-guarded) -- stub it as a no-op so invoking the
              -- captured on_attach below doesn't crash before reaching the
              -- extraction keymaps this test actually cares about.
              setup_dap = function() end,
              start_or_attach = function(config)
                captured_on_attach = config.on_attach
              end,
            }
          end
          return old_require(mod)
        end

        vim.cmd("enew")
        local bufnr = vim.api.nvim_get_current_buf()
        vim.bo[bufnr].filetype = "java"

        local f = loadfile("ftplugin/java.lua")
        if f then
          f()
        end
        _G.require = old_require

        if not captured_on_attach then
          pending("Could not capture on_attach")
          return
        end

        captured_on_attach({ name = "jdtls" }, bufnr)

        local extract = require("tetravim.util.edit.extract")
        local calls = {}
        local function stub(name)
          return function(...)
            calls[name] = { ... }
          end
        end
        local orig = {
          extract_interface = extract.extract_interface,
          inline = extract.inline,
          extract_method = extract.extract_method,
          extract_variable = extract.extract_variable,
          extract_constant = extract.extract_constant,
        }
        extract.extract_interface = stub("extract_interface")
        extract.inline = stub("inline")
        extract.extract_method = stub("extract_method")
        extract.extract_variable = stub("extract_variable")
        extract.extract_constant = stub("extract_constant")

        local function assert_mapping_calls(lhs, mode, key, expect_visual_arg)
          local mapping = vim.fn.maparg(lhs, mode, false, true)
          assert.is_not_nil(mapping.buffer, "Mapping " .. lhs .. " not found in mode " .. mode)
          -- maparg(...).buffer is a 0/1 "is buffer-local" flag, not a bufnr.
          assert.are.equal(1, mapping.buffer)
          assert.is_function(mapping.callback)
          calls[key] = nil
          mapping.callback()
          assert.is_not_nil(calls[key], lhs .. " (" .. mode .. ") did not call tetravim.util.edit.extract." .. key)
          if expect_visual_arg then
            assert.is_true(calls[key][1], lhs .. " (" .. mode .. ") must pass is_visual=true")
          end
        end

        assert_mapping_calls("<leader>ce", "n", "extract_interface")
        assert_mapping_calls("<leader>ce", "v", "extract_interface", true)
        assert_mapping_calls("<leader>ci", "n", "inline")
        assert_mapping_calls("<leader>ci", "v", "inline", true)
        assert_mapping_calls("<leader>cm", "n", "extract_method")
        assert_mapping_calls("<leader>cm", "v", "extract_method", true)
        assert_mapping_calls("<leader>cv", "n", "extract_variable")
        assert_mapping_calls("<leader>cv", "v", "extract_variable", true)
        assert_mapping_calls("<leader>cc", "n", "extract_constant")
        assert_mapping_calls("<leader>cc", "v", "extract_constant", true)

        extract.extract_interface = orig.extract_interface
        extract.inline = orig.inline
        extract.extract_method = orig.extract_method
        extract.extract_variable = orig.extract_variable
        extract.extract_constant = orig.extract_constant
      end
    )

    it(
      "lsp-kotlin.lua's on_attach should install REAL buffer-local mappings that dispatch into tetravim.util.edit.extract",
      function()
        local lsp_kotlin = require("tetravim.plugins.lsp-kotlin")
        local on_attach = lsp_kotlin[2].opts.servers.kotlin_language_server.on_attach
        assert.is_function(on_attach)

        vim.cmd("enew")
        local bufnr = vim.api.nvim_get_current_buf()
        local stub_client = {
          server_capabilities = {},
          config = { root_dir = vim.fn.getcwd() },
        }
        on_attach(stub_client, bufnr)

        -- Same dispatch/visual-arg coverage the Java test runs -- a mis-wired
        -- Kotlin mapping (wrong action, or normal-mode behavior on a visual
        -- selection) must not slip through as "some buffer-local mapping exists".
        local extract = require("tetravim.util.edit.extract")
        local calls = {}
        local orig = {}
        for _, name in ipairs({
          "extract_interface",
          "inline",
          "extract_method",
          "extract_variable",
          "extract_constant",
        }) do
          orig[name] = extract[name]
          extract[name] = function(...)
            calls[name] = { ... }
          end
        end

        local function assert_mapping_calls(lhs, mode, key, expect_visual_arg)
          local mapping = vim.fn.maparg(lhs, mode, false, true)
          assert.is_not_nil(mapping.buffer, "Mapping " .. lhs .. " not found in mode " .. mode)
          assert.are.equal(1, mapping.buffer)
          assert.is_function(mapping.callback)
          calls[key] = nil
          mapping.callback()
          assert.is_not_nil(calls[key], lhs .. " (" .. mode .. ") did not call tetravim.util.edit.extract." .. key)
          if expect_visual_arg then
            assert.is_true(calls[key][1], lhs .. " (" .. mode .. ") must pass is_visual=true")
          end
        end

        local ok, err = pcall(function()
          assert_mapping_calls("<leader>ce", "n", "extract_interface")
          assert_mapping_calls("<leader>ce", "v", "extract_interface", true)
          assert_mapping_calls("<leader>ci", "n", "inline")
          assert_mapping_calls("<leader>ci", "v", "inline", true)
          assert_mapping_calls("<leader>cm", "n", "extract_method")
          assert_mapping_calls("<leader>cm", "v", "extract_method", true)
          assert_mapping_calls("<leader>cv", "n", "extract_variable")
          assert_mapping_calls("<leader>cv", "v", "extract_variable", true)
          assert_mapping_calls("<leader>cc", "n", "extract_constant")
          assert_mapping_calls("<leader>cc", "v", "extract_constant", true)
        end)

        for name, fn in pairs(orig) do
          extract[name] = fn
        end
        require("tetravim.util.action_lock").release()
        if not ok then
          error(err, 0)
        end
      end
    )
  end)

  -- Migrated from scripts/validate-extract.sh steps [1]-[7]. The static shape +
  -- ftplugin/lsp-kotlin wiring (step [1]) is already covered above; ported here
  -- are the behavioural code-action flows, which only need the
  -- vim.lsp.get_clients / vim.lsp.buf_request_all seam mocked (no real jdtls) so
  -- they run in the plenary child. The real textDocument/codeAction round-trip
  -- and the :copen preview contents stay manual per spec-2-2's Verification.
  describe("code-action flows (mocked JDTLS seam)", function()
    local action_lock = require("tetravim.util.action_lock")

    local function make_fixture()
      local root = vim.fn.tempname()
      vim.fn.mkdir(root, "p")
      local java_file = root .. "/Foo.java"
      vim.fn.writefile({
        "package com.example;",
        "",
        "public class Foo {",
        "    public void bar() {",
        "        int x = 42;",
        "        System.out.println(x);",
        "    }",
        "}",
      }, java_file)
      return java_file
    end

    local function file_content(java_file)
      local saved_ei = vim.o.eventignore
      vim.o.eventignore = "all"
      local bufnr = vim.fn.bufadd(java_file)
      vim.fn.bufload(bufnr)
      vim.o.eventignore = saved_ei
      return table.concat(vim.api.nvim_buf_get_lines(bufnr, 0, -1, false), "\n")
    end

    local function code_action_result(java_file, new_text, title)
      return {
        {
          title = title or "Extract to method",
          kind = "refactor.extract",
          edit = {
            changes = {
              ["file://" .. java_file] = {
                {
                  range = { start = { line = 4, character = 8 }, ["end"] = { line = 5, character = 30 } },
                  newText = new_text,
                },
              },
            },
          },
        },
      }
    end

    before_each(function()
      action_lock.release()
    end)

    after_each(function()
      action_lock.release()
    end)

    it("single matching action -> Apply splices the mocked WorkspaceEdit into the real file, lock released", function()
      local extract = require("tetravim.util.edit.extract")
      local java_file = make_fixture()
      local fake_client = { id = 9101, name = "jdtls", offset_encoding = "utf-16", server_capabilities = {} }
      local orig_get_clients, orig_bra, orig_select = vim.lsp.get_clients, vim.lsp.buf_request_all, vim.ui.select
      vim.lsp.get_clients = function(_)
        return { fake_client }
      end
      vim.lsp.buf_request_all = function(_, method, _, handler)
        assert.are.equal("textDocument/codeAction", method)
        handler({ [fake_client.id] = { result = code_action_result(java_file, "extracted();") } })
      end
      vim.ui.select = function(_, _, on_choice)
        on_choice("Apply")
      end

      vim.cmd("noautocmd edit " .. vim.fn.fnameescape(java_file))
      extract.extract_method()
      vim.wait(5000, function()
        return not action_lock.is_busy()
      end, 50)

      vim.lsp.get_clients, vim.lsp.buf_request_all, vim.ui.select = orig_get_clients, orig_bra, orig_select

      assert.is_truthy(file_content(java_file):find("extracted();", 1, true))
      assert.is_false(action_lock.is_busy())
      vim.fn.delete(vim.fn.fnamemodify(java_file, ":h"), "rf")
    end)

    it("cancelling at the confirm prompt leaves the file byte-for-byte unmodified and releases the lock", function()
      local extract = require("tetravim.util.edit.extract")
      local java_file = make_fixture()
      local before = table.concat(vim.fn.readfile(java_file), "\n")
      local fake_client = { id = 9102, name = "jdtls", offset_encoding = "utf-16", server_capabilities = {} }
      local orig_get_clients, orig_bra, orig_select = vim.lsp.get_clients, vim.lsp.buf_request_all, vim.ui.select
      vim.lsp.get_clients = function(_)
        return { fake_client }
      end
      vim.lsp.buf_request_all = function(_, _, _, handler)
        handler({ [fake_client.id] = { result = code_action_result(java_file, "ShouldNotApply();") } })
      end
      vim.ui.select = function(_, _, on_choice)
        on_choice("Cancel")
      end

      vim.cmd("noautocmd edit " .. vim.fn.fnameescape(java_file))
      extract.extract_method()
      vim.wait(5000, function()
        return not action_lock.is_busy()
      end, 50)

      vim.lsp.get_clients, vim.lsp.buf_request_all, vim.ui.select = orig_get_clients, orig_bra, orig_select

      assert.are.equal(before, table.concat(vim.fn.readfile(java_file), "\n"))
      assert.is_false(action_lock.is_busy())
      vim.fn.delete(vim.fn.fnamemodify(java_file, ":h"), "rf")
    end)

    it("ambiguous multi-action -> disambiguation prompt BEFORE preview; only the chosen edit is applied", function()
      local extract = require("tetravim.util.edit.extract")
      local java_file = make_fixture()
      local fake_client = { id = 9103, name = "jdtls", offset_encoding = "utf-16", server_capabilities = {} }
      local orig_get_clients, orig_bra, orig_select = vim.lsp.get_clients, vim.lsp.buf_request_all, vim.ui.select
      vim.lsp.get_clients = function(_)
        return { fake_client }
      end
      vim.lsp.buf_request_all = function(_, _, _, handler)
        handler({
          [fake_client.id] = {
            result = {
              code_action_result(java_file, "wrongChoice();", "Extract to method (outer block)")[1],
              code_action_result(java_file, "correctChoice();", "Extract to method (inner statement)")[1],
            },
          },
        })
      end
      local select_calls = 0
      vim.ui.select = function(items, _, on_choice)
        select_calls = select_calls + 1
        if select_calls == 1 then
          assert.are.equal(2, #items)
          on_choice(items[2], 2)
        else
          on_choice("Apply")
        end
      end

      vim.cmd("noautocmd edit " .. vim.fn.fnameescape(java_file))
      extract.extract_method()
      vim.wait(5000, function()
        return not action_lock.is_busy()
      end, 50)

      vim.lsp.get_clients, vim.lsp.buf_request_all, vim.ui.select = orig_get_clients, orig_bra, orig_select

      assert.are.equal(2, select_calls, "expected disambiguation THEN confirm")
      local content = file_content(java_file)
      assert.is_truthy(content:find("correctChoice();", 1, true))
      assert.is_falsy(content:find("wrongChoice();", 1, true))
      vim.fn.delete(vim.fn.fnamemodify(java_file, ":h"), "rf")
    end)

    it("cancelling the disambiguation prompt applies nothing, releases the lock, and notifies", function()
      local extract = require("tetravim.util.edit.extract")
      local java_file = make_fixture()
      local before = table.concat(vim.fn.readfile(java_file), "\n")
      local fake_client = { id = 9104, name = "jdtls", offset_encoding = "utf-16", server_capabilities = {} }
      local orig_get_clients, orig_bra, orig_select, orig_notify =
        vim.lsp.get_clients, vim.lsp.buf_request_all, vim.ui.select, vim.notify
      vim.lsp.get_clients = function(_)
        return { fake_client }
      end
      vim.lsp.buf_request_all = function(_, _, _, handler)
        handler({
          [fake_client.id] = {
            result = {
              { title = "Extract to method (a)", kind = "refactor.extract", edit = { changes = {} } },
              { title = "Extract to method (b)", kind = "refactor.extract", edit = { changes = {} } },
            },
          },
        })
      end
      local confirm_reached = false
      vim.ui.select = function(items, _, on_choice)
        if #items == 2 and items[1]:match("Extract to method") then
          on_choice(nil, nil)
        else
          confirm_reached = true
          on_choice("Apply")
        end
      end
      local notified = {}
      vim.notify = function(msg)
        table.insert(notified, msg)
      end

      vim.cmd("noautocmd edit " .. vim.fn.fnameescape(java_file))
      extract.extract_method()
      vim.wait(5000, function()
        return not action_lock.is_busy()
      end, 50)

      vim.lsp.get_clients, vim.lsp.buf_request_all, vim.ui.select, vim.notify =
        orig_get_clients, orig_bra, orig_select, orig_notify

      assert.is_false(confirm_reached, "the confirm prompt must never be reached when disambiguation is cancelled")
      assert.is_false(action_lock.is_busy())
      assert.are.equal(before, table.concat(vim.fn.readfile(java_file), "\n"))
      local saw_cancel = false
      for _, m in ipairs(notified) do
        if tostring(m):match("cancelled") then
          saw_cancel = true
        end
      end
      assert.is_true(saw_cancel, "expected a cancellation notification")
      vim.fn.delete(vim.fn.fnamemodify(java_file, ":h"), "rf")
    end)

    it("no applicable code action -> WARN, no crash, lock released", function()
      local extract = require("tetravim.util.edit.extract")
      local java_file = make_fixture()
      local fake_client = { id = 9105, name = "jdtls", offset_encoding = "utf-16", server_capabilities = {} }
      local orig_get_clients, orig_bra, orig_notify = vim.lsp.get_clients, vim.lsp.buf_request_all, vim.notify
      vim.lsp.get_clients = function(_)
        return { fake_client }
      end
      vim.lsp.buf_request_all = function(_, _, _, handler)
        handler({ [fake_client.id] = { result = {} } })
      end
      local notified = {}
      vim.notify = function(msg, level)
        table.insert(notified, { msg = msg, level = level })
      end

      vim.cmd("noautocmd edit " .. vim.fn.fnameescape(java_file))
      extract.extract_method()
      vim.wait(5000, function()
        return not action_lock.is_busy()
      end, 50)

      vim.lsp.get_clients, vim.lsp.buf_request_all, vim.notify = orig_get_clients, orig_bra, orig_notify

      assert.is_false(action_lock.is_busy())
      local saw_warn = false
      for _, n in ipairs(notified) do
        if n.level == vim.log.levels.WARN and tostring(n.msg):match("No applicable") then
          saw_warn = true
        end
      end
      assert.is_true(saw_warn, "expected a WARN for no applicable code action")
      vim.fn.delete(vim.fn.fnamemodify(java_file, ":h"), "rf")
    end)

    it("visual-mode byte columns are converted to LSP utf-16 CHARACTER offsets, not passed through raw", function()
      local extract = require("tetravim.util.edit.extract")
      vim.cmd("enew")
      local bufnr = vim.api.nvim_get_current_buf()
      -- "é" is 1 UTF-16 code unit but 2 UTF-8 bytes -- a raw byte-column
      -- pass-through would be off by one for anything after it.
      local line = 'System.out.println("héllo");'
      vim.api.nvim_buf_set_lines(bufnr, 0, 1, false, { line })
      local _, e_end = line:find("é")
      local after_e_byte_col = e_end
      local end_byte_col = #line - 2

      vim.api.nvim_buf_set_mark(bufnr, "<", 1, after_e_byte_col, {})
      vim.api.nvim_buf_set_mark(bufnr, ">", 1, end_byte_col, {})

      local fake_client = { id = 9106, name = "jdtls", offset_encoding = "utf-16", server_capabilities = {} }
      local orig_get_clients, orig_bra = vim.lsp.get_clients, vim.lsp.buf_request_all
      vim.lsp.get_clients = function(_)
        return { fake_client }
      end
      local captured_range
      vim.lsp.buf_request_all = function(_, _, params, _)
        captured_range = params.range
        -- leave the request "pending" -- this test only inspects outgoing params
      end

      extract.extract_variable(true)

      vim.lsp.get_clients, vim.lsp.buf_request_all = orig_get_clients, orig_bra
      require("tetravim.util.action_lock").release()

      assert.is_truthy(captured_range, "do_action never reached vim.lsp.buf_request_all")
      local expected_start = vim.lsp.util.character_offset(bufnr, 0, after_e_byte_col, "utf-16")
      local expected_end_raw = vim.lsp.util.character_offset(bufnr, 0, end_byte_col, "utf-16")
      assert.is_true(expected_end_raw < end_byte_col, "fixture did not exercise a byte-vs-utf16 divergence")
      local expected_end = expected_end_raw
      if vim.o.selection ~= "exclusive" then
        expected_end = expected_end + 1
      end
      assert.are.equal(expected_start, captured_range.start.character)
      assert.are.equal(expected_end, captured_range["end"].character)
    end)
  end)

  -- Migrated from scripts/validate-extract.sh step [1/7]: the action_lock
  -- surface the extraction + rename modules share.
  it("util/action_lock exposes is_busy / acquire / release", function()
    local action_lock = require("tetravim.util.action_lock")
    assert.is_function(action_lock.is_busy)
    assert.is_function(action_lock.acquire)
    assert.is_function(action_lock.release)
  end)
end)
