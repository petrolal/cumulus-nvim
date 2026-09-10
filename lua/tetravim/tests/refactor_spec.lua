-- SPEC-2.1: Project-Wide Safe Rename (Java & Kotlin) -- static shape tests
--
-- Scoped to what plenary's busted harness can reliably verify: module shape,
-- pure-function classification logic, and the buffer-local keymap wiring in
-- ftplugin/java.lua / lsp-kotlin.lua. Like the repo's other *_spec.lua
-- files, this avoids driving a real jdtls/kotlin_language_server client --
-- that behavioral coverage (a live rename against a fixture project,
-- confirmed through the quickfix preview) needs a running LSP and is
-- verified manually per spec-2-1's Verification section. `scan_root_async`
-- itself IS exercised directly here (it only needs `rg`/`grep` + real files
-- on disk, no LSP), since it's the most bug-prone piece (duplicate-
-- occurrence and package-scoping fixes).

describe("Refactor (SPEC-2.1)", function()
  describe("tetravim.util.refactor", function()
    it("should expose project_rename and the internal rename pipeline", function()
      local refactor = require("tetravim.util.refactor")
      assert.is_table(refactor)
      assert.is_function(refactor.project_rename)
      assert.is_function(refactor.find_jvm_client)
      assert.is_function(refactor.workspace_edit_to_locations)
      assert.is_function(refactor.filter_overlapping_spring_items)
      assert.is_function(refactor.apply_spring_edits)
      assert.is_function(refactor.spring_items_to_qf)
      assert.is_number(refactor.RENAME_TIMEOUT_MS)
    end)

    it("should notify and return without erroring when no JVM LSP is attached", function()
      local refactor = require("tetravim.util.refactor")
      vim.cmd("enew")
      -- A fresh scratch buffer has no LSP clients attached at all.
      assert.is_nil(refactor.find_jvm_client(vim.api.nvim_get_current_buf()))
      assert.has_no.errors(function()
        refactor.project_rename("NewName")
      end)
    end)

    it("should reject a second project_rename while one is already in flight (shared action_lock.lua)", function()
      local refactor = require("tetravim.util.refactor")
      local action_lock = require("tetravim.util.action_lock")
      local notified = {}
      local orig_notify = vim.notify
      vim.notify = function(msg, level)
        table.insert(notified, { msg = msg, level = level })
      end

      action_lock.acquire()
      refactor.project_rename("Whatever")
      action_lock.release()

      vim.notify = orig_notify
      assert.are.equal(1, #notified)
      assert.are.equal(vim.log.levels.WARN, notified[1].level)
      assert.is_truthy(notified[1].msg:match("already in progress"))
    end)

    it(
      "action_lock.lua is SHARED with tetravim.util.extract -- an extract/inline action in flight must also reject a concurrent project_rename",
      function()
        local refactor = require("tetravim.util.refactor")
        local extract = require("tetravim.util.extract")
        local action_lock = require("tetravim.util.action_lock")

        assert.is_false(action_lock.is_busy())

        -- Simulate extract.lua holding the lock (e.g. a code-action request
        -- in flight) and confirm refactor.lua's project_rename sees the
        -- SAME lock as busy -- proving the two modules no longer keep
        -- independent M._busy flags that could race against each other.
        -- The lock is acquired synchronously inside do_action, before the
        -- (mocked, never-resolving) textDocument/codeAction request is even
        -- sent, so no vim.wait is needed to observe it. buf_request_all
        -- itself is mocked too (never invoking its handler) since a fake
        -- client table isn't a real vim.lsp.Client and would error deep
        -- inside the real LSP request machinery otherwise.
        local orig_get_clients = vim.lsp.get_clients
        local orig_buf_request_all = vim.lsp.buf_request_all
        vim.lsp.get_clients = function(_)
          return { { name = "jdtls", id = 1, offset_encoding = "utf-16" } }
        end
        vim.lsp.buf_request_all = function() end
        vim.cmd("enew")
        extract.extract_interface(false)
        vim.lsp.get_clients = orig_get_clients
        vim.lsp.buf_request_all = orig_buf_request_all
        assert.is_true(action_lock.is_busy())

        local notified = {}
        local orig_notify = vim.notify
        vim.notify = function(msg, level)
          table.insert(notified, { msg = msg, level = level })
        end

        -- The lock is now GENUINELY shared across modules -- if either
        -- assertion below fails, letting the error propagate straight out
        -- would skip the action_lock.release() further down and strand the
        -- lock busy for the REST of this busted run (every later test
        -- touching refactor.project_rename or any extract.* action would
        -- then spuriously fail too, masking the real failure). pcall the
        -- risky portion, always release, then re-raise so this test still
        -- correctly reports FAIL.
        local check_ok, check_err = pcall(function()
          refactor.project_rename("Whatever")
          assert.are.equal(1, #notified)
          assert.is_truthy(notified[1].msg:match("already in progress"))
        end)

        vim.notify = orig_notify
        action_lock.release()

        if not check_ok then
          error(check_err, 0)
        end
        assert.is_false(action_lock.is_busy())
      end
    )

    it(
      "M._on_rename_response should warn and skip the Spring/treesitter scan (LSP-only locations) when the JVM client reports no root_dir, and release the lock on both Apply and Cancel",
      function()
        local refactor = require("tetravim.util.refactor")
        local action_lock = require("tetravim.util.action_lock")
        local refactor_ts = require("tetravim.util.refactor_treesitter")

        -- Real temp file (not a fake nonexistent URI) so
        -- vim.lsp.util.apply_workspace_edit's real file/buffer machinery on
        -- the Apply path has something real to load and edit.
        local java_file = vim.fn.tempname() .. ".java"
        vim.fn.writefile({ "public class Foo {}" }, java_file)

        --- Runs one full project_rename pass against the no-root_dir fixture
        --- above, auto-answering the confirm prompt with `select_choice`
        --- ("Apply" or "Cancel"). Returns (notifications, scan_called).
        local function run_once(select_choice)
          vim.cmd("noautocmd edit " .. vim.fn.fnameescape(java_file))
          local bufnr = vim.api.nvim_get_current_buf()
          vim.api.nvim_win_set_cursor(0, { 1, 0 }) -- cursor on "public", not "Bar"

          local fake_client = {
            id = 5001,
            name = "jdtls",
            offset_encoding = "utf-16",
            config = {}, -- no root_dir
            request = function(_, _, _, handler)
              handler(nil, {
                changes = {
                  ["file://" .. java_file] = {
                    {
                      range = { start = { line = 0, character = 13 }, ["end"] = { line = 0, character = 16 } },
                      newText = "Bar",
                    },
                  },
                },
              })
              return true, 1
            end,
          }

          local orig_get_clients = vim.lsp.get_clients
          local orig_buf_request_all = vim.lsp.buf_request_all
          vim.lsp.get_clients = function(_)
            return { fake_client }
          end
          vim.lsp.buf_request_all = function(_, _, _, handler)
            handler({
              [fake_client.id] = {
                result = {
                  changes = {
                    ["file://" .. java_file] = {
                      {
                        range = { start = { line = 0, character = 13 }, ["end"] = { line = 0, character = 16 } },
                        newText = "Bar",
                      },
                    },
                  },
                },
              },
            })
          end

          local scan_called = false
          local orig_scan = refactor_ts.scan_root_async
          refactor_ts.scan_root_async = function(...)
            scan_called = true
            return orig_scan(...)
          end

          local notified = {}
          local orig_notify = vim.notify
          vim.notify = function(msg, level)
            table.insert(notified, { msg = msg, level = level })
          end

          local orig_select = vim.ui.select
          vim.ui.select = function(_, _, on_choice)
            on_choice(select_choice)
          end

          refactor.project_rename("Bar")
          vim.wait(2000, function()
            return not action_lock.is_busy()
          end, 20)

          vim.lsp.get_clients = orig_get_clients
          vim.lsp.buf_request_all = orig_buf_request_all
          refactor_ts.scan_root_async = orig_scan
          vim.notify = orig_notify
          vim.ui.select = orig_select

          return notified, scan_called
        end

        local notified_apply, scan_called_apply = run_once("Apply")
        assert.is_false(scan_called_apply, "scan_root_async must never be invoked when root_dir is missing")
        local saw_warn_apply = false
        for _, n in ipairs(notified_apply) do
          if n.level == vim.log.levels.WARN and n.msg:match("root_dir") and n.msg:match("jdtls") then
            saw_warn_apply = true
          end
        end
        assert.is_true(saw_warn_apply, "expected a WARN naming the client and mentioning root_dir")
        assert.is_false(action_lock.is_busy(), "lock must be released after Apply")

        local notified_cancel, scan_called_cancel = run_once("Cancel")
        assert.is_false(scan_called_cancel, "scan_root_async must never be invoked when root_dir is missing")
        local saw_warn_cancel = false
        for _, n in ipairs(notified_cancel) do
          if n.level == vim.log.levels.WARN and n.msg:match("root_dir") and n.msg:match("jdtls") then
            saw_warn_cancel = true
          end
        end
        assert.is_true(saw_warn_cancel, "expected a WARN naming the client and mentioning root_dir")
        assert.is_false(action_lock.is_busy(), "lock must be released after Cancel")

        os.remove(java_file)
      end
    )

    it("should flatten a WorkspaceEdit's `changes` into uri/range locations", function()
      local refactor = require("tetravim.util.refactor")
      local edit = {
        changes = {
          ["file:///a/Foo.java"] = {
            { range = { start = { line = 1, character = 0 }, ["end"] = { line = 1, character = 3 } } },
          },
        },
      }
      local locations = refactor.workspace_edit_to_locations(edit)
      assert.are.equal(1, #locations)
      assert.are.equal("file:///a/Foo.java", locations[1].uri)
      assert.are.equal(1, locations[1].range.start.line)
    end)

    it("should not drop a location under a generated/build directory", function()
      local refactor = require("tetravim.util.refactor")
      local edit = {
        changes = {
          ["file:///proj/target/generated-sources/Foo.java"] = {
            { range = { start = { line = 0, character = 0 }, ["end"] = { line = 0, character = 3 } } },
          },
          ["file:///proj/build/classes/java/main/Foo.java"] = {
            { range = { start = { line = 0, character = 0 }, ["end"] = { line = 0, character = 3 } } },
          },
        },
      }
      local locations = refactor.workspace_edit_to_locations(edit)
      assert.are.equal(2, #locations)
      local uris = { locations[1].uri, locations[2].uri }
      assert.is_truthy(vim.tbl_contains(uris, "file:///proj/target/generated-sources/Foo.java"))
      assert.is_truthy(vim.tbl_contains(uris, "file:///proj/build/classes/java/main/Foo.java"))
    end)

    it("should flatten a WorkspaceEdit's `documentChanges` (TextDocumentEdit) into locations", function()
      local refactor = require("tetravim.util.refactor")
      local edit = {
        documentChanges = {
          {
            textDocument = { uri = "file:///a/Foo.java", version = 1 },
            edits = {
              { range = { start = { line = 4, character = 2 }, ["end"] = { line = 4, character = 5 } } },
            },
          },
          -- Resource operations (rename/create/delete) must be ignored --
          -- file-move handling is explicitly out of scope for this spec.
          { kind = "rename", oldUri = "file:///a/Old.java", newUri = "file:///a/New.java" },
        },
      }
      local locations = refactor.workspace_edit_to_locations(edit)
      assert.are.equal(1, #locations)
      assert.are.equal(4, locations[1].range.start.line)
    end)

    it("filter_overlapping_spring_items should drop a Spring item overlapping an LSP-covered range", function()
      local refactor = require("tetravim.util.refactor")
      local lsp_items = {
        { filename = "/a/Foo.java", lnum = 5, col = 10, end_col = 20 },
      }
      local spring_items = {
        { file = "/a/Foo.java", lnum = 5, col = 12, end_col = 22, kind = "stereotype", text = "x" }, -- overlaps
        { file = "/a/Foo.java", lnum = 5, col = 25, end_col = 30, kind = "stereotype", text = "x" }, -- disjoint
        { file = "/a/Bar.xml", lnum = 5, col = 10, end_col = 20, kind = "xml_bean", text = "x" }, -- different file
      }
      local filtered = refactor.filter_overlapping_spring_items(lsp_items, spring_items)
      assert.are.equal(2, #filtered)
      for _, item in ipairs(filtered) do
        assert.is_not.same(12, item.col) -- the overlapping one must be gone
      end
    end)

    it("spring_items_to_qf should tag each item with a kind label and preserve position", function()
      local refactor = require("tetravim.util.refactor")
      local qf = refactor.spring_items_to_qf({
        {
          file = "/a/beans.xml",
          lnum = 2,
          col = 46,
          end_col = 56,
          kind = "xml_bean",
          text = '<bean class="...FooService"/>',
        },
      })
      assert.are.equal(1, #qf)
      assert.are.equal("/a/beans.xml", qf[1].filename)
      assert.are.equal(2, qf[1].lnum)
      assert.are.equal(46, qf[1].col)
      assert.is_truthy(qf[1].text:match("^%[Spring XML bean%]"))
    end)

    it(
      "apply_spring_edits should rename BOTH occurrences on a line with the symbol twice, without corruption",
      function()
        local refactor = require("tetravim.util.refactor")
        local ts = require("tetravim.util.refactor_treesitter")
        local file = vim.fn.tempname() .. ".java"
        vim.fn.writefile({
          "public class Consumer {",
          "  @Autowired",
          "  private FooService fooService = FooService.createDefault();",
          "}",
        }, file)

        local lines = vim.fn.readfile(file)
        local kind, occurrences = ts.classify_jvm_line(lines, 3, "FooService")
        assert.are.equal("autowired", kind)
        assert.are.equal(2, #occurrences)

        local items = {}
        for _, occ in ipairs(occurrences) do
          items[#items + 1] =
            { file = file, lnum = 3, col = occ.col, end_col = occ.end_col, kind = kind, text = lines[3] }
        end

        -- Pass old_name too: exercises the stale-span guard on its happy
        -- path (both spans still hold "FooService", so both apply).
        local applied, failed = refactor.apply_spring_edits(items, "BarServiceRenamedLonger", "FooService")
        assert.are.equal(2, applied)
        assert.are.equal(0, #failed)

        local bufnr = vim.fn.bufadd(file)
        vim.fn.bufload(bufnr)
        local result_line = vim.api.nvim_buf_get_lines(bufnr, 2, 3, false)[1]
        assert.are.equal(
          "  private BarServiceRenamedLonger fooService = BarServiceRenamedLonger.createDefault();",
          result_line
        )

        os.remove(file)
      end
    )

    it("apply_spring_edits should report a failed file rather than silently under-counting", function()
      local refactor = require("tetravim.util.refactor")
      local items = {
        {
          file = "/nonexistent/path/that/cannot/exist/Foo.xml",
          lnum = 1,
          col = 1,
          end_col = 4,
          kind = "xml_bean",
          text = "x",
        },
      }
      local applied, failed = refactor.apply_spring_edits(items, "New")
      assert.are.equal(0, applied)
      assert.are.equal(1, #failed)
    end)
  end)

  describe("tetravim.util.refactor_treesitter", function()
    it("should expose the scan/classification API", function()
      local ts = require("tetravim.util.refactor_treesitter")
      assert.is_table(ts)
      assert.is_function(ts.scan_root_async)
      assert.is_function(ts.raw_hits_async)
      assert.is_function(ts.classify_xml_line)
      assert.is_function(ts.classify_jvm_line)
      assert.is_function(ts.file_package)
      assert.is_function(ts.is_inside_xml_comment)
      assert.is_table(ts.STEREOTYPE_ANNOTATIONS)
    end)

    it('should classify a Spring XML <bean class="..."> entry referencing the symbol', function()
      local ts = require("tetravim.util.refactor_treesitter")
      local line = '  <bean id="fooService" class="com.example.FooService"/>'
      local occurrences = ts.classify_xml_line(line, "FooService")
      assert.are.equal(1, #occurrences)
      local col, end_col = occurrences[1].col, occurrences[1].end_col
      assert.are.equal("FooService", line:sub(col, end_col - 1))
      assert.are.equal("com.example", occurrences[1].package)
    end)

    it("should not classify an XML line that merely mentions the symbol outside a bean class attribute", function()
      local ts = require("tetravim.util.refactor_treesitter")
      local line = "  <!-- FooService is wired below -->"
      assert.is_nil(ts.classify_xml_line(line, "FooService"))
    end)

    it("should treat a bare simple-name (no package) bean class attribute as package-undeterminable", function()
      local ts = require("tetravim.util.refactor_treesitter")
      local line = '  <bean id="fooService" class="FooService"/>'
      local occurrences = ts.classify_xml_line(line, "FooService")
      assert.are.equal(1, #occurrences)
      assert.is_nil(occurrences[1].package)
    end)

    it("is_inside_xml_comment should detect a bean entry inside a single-line XML comment", function()
      local ts = require("tetravim.util.refactor_treesitter")
      local lines = { "<beans>", '<!-- <bean id="x" class="com.example.FooService"/> -->', "</beans>" }
      assert.is_true(ts.is_inside_xml_comment(lines, 2, 30))
    end)

    it("is_inside_xml_comment should not flag a live (non-commented) bean entry", function()
      local ts = require("tetravim.util.refactor_treesitter")
      local lines = { "<beans>", '<bean id="x" class="com.example.FooService"/>', "</beans>" }
      assert.is_false(ts.is_inside_xml_comment(lines, 2, 20))
    end)

    it("should classify an @Autowired field of the renamed type", function()
      local ts = require("tetravim.util.refactor_treesitter")
      local lines = {
        "public class Consumer {",
        "  @Autowired",
        "  private FooService fooService;",
        "}",
      }
      local kind, occurrences = ts.classify_jvm_line(lines, 3, "FooService")
      assert.are.equal("autowired", kind)
      assert.are.equal(1, #occurrences)
      assert.are.equal("FooService", lines[3]:sub(occurrences[1].col, occurrences[1].end_col - 1))
    end)

    it("should classify BOTH occurrences when the renamed type appears twice on one line", function()
      local ts = require("tetravim.util.refactor_treesitter")
      local lines = {
        "public class Consumer {",
        "  @Autowired",
        "  private FooService fooService = FooService.createDefault();",
        "}",
      }
      local kind, occurrences = ts.classify_jvm_line(lines, 3, "FooService")
      assert.are.equal("autowired", kind)
      assert.are.equal(2, #occurrences)
      assert.is_true(occurrences[1].end_col <= occurrences[2].col) -- non-overlapping, in order
      for _, occ in ipairs(occurrences) do
        assert.are.equal("FooService", lines[3]:sub(occ.col, occ.end_col - 1))
      end
    end)

    it("should classify a stereotype-annotated class declaration", function()
      local ts = require("tetravim.util.refactor_treesitter")
      local lines = {
        "package com.example;",
        "",
        "@Service",
        "public class FooService {",
        "}",
      }
      local kind, occurrences = ts.classify_jvm_line(lines, 4, "FooService")
      assert.are.equal("stereotype", kind)
      assert.are.equal(1, #occurrences)
    end)

    it("should not classify a field of the renamed type without @Autowired or a stereotype", function()
      local ts = require("tetravim.util.refactor_treesitter")
      local lines = {
        "public class Consumer {",
        "  private FooService fooService;",
        "}",
      }
      local kind = ts.classify_jvm_line(lines, 2, "FooService")
      assert.is_nil(kind)
    end)

    it("file_package should extract a Java/Kotlin package declaration", function()
      local ts = require("tetravim.util.refactor_treesitter")
      assert.are.equal("com.example", ts.file_package({ "package com.example;", "", "class Foo {}" }))
      assert.are.equal("com.example.sub", ts.file_package({ "package com.example.sub", "class Foo" }))
      assert.is_nil(ts.file_package({ "class Foo {}" }))
    end)

    it(
      "scan_root_async should package-scope Spring matches: renaming com.example.FooService must not touch com.other.FooService",
      function()
        local ts = require("tetravim.util.refactor_treesitter")
        local root = vim.fn.tempname()
        vim.fn.mkdir(root .. "/com/example", "p")
        vim.fn.mkdir(root .. "/com/other", "p")

        vim.fn.writefile({
          "package com.example;",
          "",
          "import org.springframework.beans.factory.annotation.Autowired;",
          "",
          "public class Consumer {",
          "  @Autowired",
          "  private FooService fooService;",
          "}",
        }, root .. "/com/example/Consumer.java")

        vim.fn.writefile({
          "package com.other;",
          "",
          "import org.springframework.beans.factory.annotation.Autowired;",
          "",
          "public class OtherConsumer {",
          "  @Autowired",
          "  private FooService fooService;",
          "}",
        }, root .. "/com/other/OtherConsumer.java")

        vim.fn.writefile({
          "<beans>",
          '    <bean id="fooService" class="com.example.FooService"/>',
          '    <bean id="otherFooService" class="com.other.FooService"/>',
          "</beans>",
        }, root .. "/beans.xml")

        local result = nil
        ts.scan_root_async(root, "FooService", "com.example", function(items)
          result = items
        end)

        vim.wait(10000, function()
          return result ~= nil
        end, 50)

        assert.is_not_nil(result, "scan_root_async did not complete within the wait window")
        assert.are.equal(2, #result)
        for _, item in ipairs(result) do
          assert.is_falsy(item.file:find("com/other", 1, true))
        end

        vim.fn.delete(root, "rf")
      end
    )
  end)

  describe("Buffer-local <leader>cr override wiring", function()
    -- SPEC-2.1 review (2026-09-01): the override moved OUT of each server's
    -- on_attach and into ftplugin/java.lua + ftplugin/kotlin.lua at top
    -- level, so it is installed for EVERY java/kotlin buffer regardless of
    -- whether a JDTLS/Kotlin client attached -- the I/O matrix "No JVM LSP
    -- attached" row needs project_rename's own notify to fire from the
    -- keymap, which can't happen if the keymap only exists once a client is
    -- present.
    local function assert_real_cr_mapping(bufnr)
      -- maparg(...).buffer is a 0/1 "is this buffer-local" flag, not a bufnr.
      local mapping = vim.fn.maparg("<leader>cr", "n", false, true)
      assert.is_table(mapping)
      assert.are.equal(1, mapping.buffer, "<leader>cr must be a BUFFER-LOCAL mapping")
      assert.is_function(mapping.callback)

      -- And it must be local to THIS buffer only: a fresh scratch buffer
      -- sees no buffer-local <leader>cr.
      local other = vim.api.nvim_create_buf(true, true)
      vim.api.nvim_buf_call(other, function()
        local m = vim.fn.maparg("<leader>cr", "n", false, true)
        assert.is_true(m.buffer ~= 1, "the override must not leak to unrelated buffers")
      end)
      vim.api.nvim_buf_delete(other, { force = true })

      local refactor = require("tetravim.util.refactor")
      local called = false
      local orig = refactor.project_rename
      refactor.project_rename = function()
        called = true
      end
      local ok = pcall(mapping.callback)
      refactor.project_rename = orig
      assert.is_true(ok and called, "the buffer-local <leader>cr mapping must call refactor.project_rename")
    end

    it(
      "ftplugin/java.lua installs a real buffer-local <leader>cr for every java buffer (no on_attach needed)",
      function()
        local old_require = _G.require
        _G.require = function(mod)
          if mod == "jdtls" then
            -- Neuter the launcher so sourcing the ftplugin doesn't try to
            -- start a real jdtls process; the <leader>cr map is bound before
            -- this require anyway.
            return { start_or_attach = function() end, setup = { find_root = function() end } }
          end
          return old_require(mod)
        end

        vim.cmd("enew")
        local bufnr = vim.api.nvim_get_current_buf()
        vim.bo[bufnr].filetype = "java"

        local f = loadfile("ftplugin/java.lua")
        assert.is_function(f)
        pcall(f)
        _G.require = old_require

        assert_real_cr_mapping(bufnr)
      end
    )

    it("ftplugin/kotlin.lua installs a real buffer-local <leader>cr for every kotlin buffer", function()
      vim.cmd("enew")
      local bufnr = vim.api.nvim_get_current_buf()
      vim.bo[bufnr].filetype = "kotlin"

      local f = loadfile("ftplugin/kotlin.lua")
      assert.is_function(f)
      f()

      assert_real_cr_mapping(bufnr)
    end)
  end)

  describe("project_rename() no-arg prompt path (the shape both keymaps ship)", function()
    -- Every other test passes an explicit new_name, so the entire
    -- `new_name == nil` block -- including its three action_lock.release()
    -- sites -- was previously uncovered. A leak there silently disables all
    -- rename + extract for the session.
    local function with_stubbed_prompt(input_value, body)
      local refactor = require("tetravim.util.refactor")
      local action_lock = require("tetravim.util.action_lock")
      action_lock.release() -- start clean regardless of prior test state

      local orig_get_clients = vim.lsp.get_clients
      local orig_ui_input = vim.ui.input
      local orig_expand = vim.fn.expand
      local orig_do_rename = refactor._do_rename
      local do_rename_called = false

      vim.lsp.get_clients = function(_)
        return { { name = "jdtls", id = 1, offset_encoding = "utf-16", config = {} } }
      end
      vim.fn.expand = function(what, ...)
        if what == "<cword>" then
          return "FooService"
        end
        return orig_expand(what, ...)
      end
      vim.ui.input = function(_, on_confirm)
        on_confirm(input_value)
      end
      refactor._do_rename = function()
        do_rename_called = true
      end

      vim.cmd("enew")
      local ok, err = pcall(refactor.project_rename) -- NO argument

      vim.lsp.get_clients = orig_get_clients
      vim.ui.input = orig_ui_input
      vim.fn.expand = orig_expand
      refactor._do_rename = orig_do_rename

      body(ok, err, do_rename_called, action_lock)
      action_lock.release()
    end

    it("releases the lock when the prompt is cancelled (nil)", function()
      with_stubbed_prompt(nil, function(ok, _, do_rename_called, action_lock)
        assert.is_true(ok)
        assert.is_false(do_rename_called)
        assert.is_false(action_lock.is_busy(), "cancelling the rename prompt must not strand the shared lock")
      end)
    end)

    it("releases the lock when the prompt returns only whitespace", function()
      with_stubbed_prompt("   ", function(ok, _, do_rename_called, action_lock)
        assert.is_true(ok)
        assert.is_false(do_rename_called)
        assert.is_false(action_lock.is_busy())
      end)
    end)

    it("releases the lock when the new name equals the old name", function()
      with_stubbed_prompt("FooService", function(ok, _, do_rename_called, action_lock)
        assert.is_true(ok)
        assert.is_false(do_rename_called)
        assert.is_false(action_lock.is_busy())
      end)
    end)

    it("releases the lock and rejects a non-identifier new name", function()
      with_stubbed_prompt("Foo Service!", function(ok, _, do_rename_called, action_lock)
        assert.is_true(ok)
        assert.is_false(do_rename_called)
        assert.is_false(action_lock.is_busy())
      end)
    end)

    it("proceeds to _do_rename (lock held for it) on a valid, trimmed new name", function()
      with_stubbed_prompt("  BarService  ", function(ok, _, do_rename_called)
        assert.is_true(ok)
        assert.is_true(do_rename_called, "a valid new name must hand off to _do_rename")
      end)
    end)
  end)

  describe("apply_spring_edits stale-span guard (SPEC-2.1 review 2026-09-01)", function()
    it("skips a span (and fails its file) when the live buffer text no longer matches old_name", function()
      local refactor = require("tetravim.util.refactor")
      local file = vim.fn.tempname() .. ".java"
      vim.fn.writefile({ "class Consumer {", "  private FooService a;", "}" }, file)

      -- Open the file and edit line 2 so the recorded [col,end_col) span no
      -- longer holds "FooService" -- simulating an already-open dirty buffer
      -- or an edit made in the :copen preview before Apply.
      local bufnr = vim.fn.bufadd(file)
      vim.fn.bufload(bufnr)
      vim.api.nvim_buf_set_lines(bufnr, 1, 2, false, { "  private XXXXXXXXXX a;" })

      -- Span recorded against the ON-DISK content: cols 11..21 = "FooService".
      local items = { { file = file, lnum = 2, col = 11, end_col = 21, kind = "autowired", text = "" } }
      local applied, failed = refactor.apply_spring_edits(items, "BarService", "FooService")

      assert.are.equal(0, applied)
      assert.are.equal(1, #failed)
      assert.are.equal(
        "  private XXXXXXXXXX a;",
        vim.api.nvim_buf_get_lines(bufnr, 1, 2, false)[1],
        "a stale span must be left untouched, never blind-spliced"
      )

      vim.api.nvim_buf_delete(bufnr, { force = true })
      os.remove(file)
    end)
  end)

  -- Migrated from scripts/validate-refactor.sh. Steps [1]/[3] (module shape,
  -- Cancel-leaves-files-untouched) are already covered above; what is ported
  -- here is the end-to-end fixture rename against a real root_dir (the mocked
  -- WorkspaceEdit merged with the real, un-mocked refactor_treesitter scan and
  -- both edit sets applied -- step [2]), the LSP-error collision abort
  -- (step [4]) and the rg->grep fallback (step [5]). All three only need the
  -- LSP seam mocked plus rg/grep + real files on disk, so they run fine in the
  -- plenary child.
  describe("project-wide rename end-to-end (mocked JDTLS seam)", function()
    local action_lock = require("tetravim.util.action_lock")

    local function make_fixture()
      local root = vim.fn.tempname()
      vim.fn.mkdir(root .. "/src/main/java/com/example", "p")
      vim.fn.mkdir(root .. "/src/main/java/com/other", "p")
      vim.fn.mkdir(root .. "/src/main/resources", "p")
      vim.fn.writefile({
        "package com.example;",
        "",
        "import org.springframework.stereotype.Service;",
        "",
        "@Service",
        "public class FooService {",
        "}",
      }, root .. "/src/main/java/com/example/FooService.java")
      vim.fn.writefile({
        "package com.example;",
        "",
        "import org.springframework.beans.factory.annotation.Autowired;",
        "",
        "public class Consumer {",
        "  @Autowired",
        "  private FooService fooService = FooService.createDefault();",
        "}",
      }, root .. "/src/main/java/com/example/Consumer.java")
      vim.fn.writefile({
        "package com.other;",
        "",
        "public class FooService {",
        "}",
      }, root .. "/src/main/java/com/other/FooService.java")
      vim.fn.writefile({
        "<beans>",
        '    <bean id="fooService" class="com.example.FooService"/>',
        '    <bean id="otherFooService" class="com.other.FooService"/>',
        '    <!-- <bean id="commentedOut" class="com.example.FooService"/> -->',
        "</beans>",
      }, root .. "/src/main/resources/beans.xml")
      return root
    end

    local function buf_content(file)
      local saved_ei = vim.o.eventignore
      vim.o.eventignore = "all"
      local bufnr = vim.fn.bufadd(file)
      vim.fn.bufload(bufnr)
      vim.o.eventignore = saved_ei
      return table.concat(vim.api.nvim_buf_get_lines(bufnr, 0, -1, false), "\n")
    end

    it("Apply renames the class + both same-line field occurrences + the live XML bean, and nothing else", function()
      local refactor = require("tetravim.util.refactor")
      local root = make_fixture()
      local java_file = root .. "/src/main/java/com/example/FooService.java"
      local consumer_file = root .. "/src/main/java/com/example/Consumer.java"
      local xml_file = root .. "/src/main/resources/beans.xml"
      local other_service_file = root .. "/src/main/java/com/other/FooService.java"

      -- refactor._do_rename fans the rename out through
      -- util/lsp_async.request_all_async, which calls client.request(...)
      -- directly (NOT vim.lsp.buf_request_all), so the mocked response lives
      -- on the fake client itself.
      local rename_edit = {
        changes = {
          ["file://" .. java_file] = {
            {
              range = { start = { line = 5, character = 13 }, ["end"] = { line = 5, character = 23 } },
              newText = "BarService",
            },
          },
        },
      }
      local fake_client = {
        id = 9001,
        name = "jdtls",
        offset_encoding = "utf-16",
        config = { root_dir = root },
        request = function(_, method, _, handler)
          if method ~= "textDocument/rename" then
            return false
          end
          handler(nil, rename_edit)
          return true, 1
        end,
        cancel_request = function() end,
      }
      local orig_get_clients = vim.lsp.get_clients
      local orig_select = vim.ui.select
      vim.lsp.get_clients = function(_)
        return { fake_client }
      end
      vim.ui.select = function(_, _, on_choice)
        on_choice("Apply")
      end

      vim.cmd("noautocmd edit " .. vim.fn.fnameescape(java_file))
      vim.api.nvim_win_set_cursor(0, { 6, 13 })
      refactor.project_rename("BarService")

      vim.wait(10000, function()
        return not action_lock.is_busy() and buf_content(java_file):find("BarService", 1, true) ~= nil
      end, 50)

      vim.lsp.get_clients = orig_get_clients
      vim.ui.select = orig_select

      local foo = buf_content(java_file)
      assert.is_truthy(foo:find("public class BarService", 1, true))
      assert.is_falsy(foo:find("BarServiceBarService", 1, true)) -- LSP/Spring overlap not double-spliced

      assert.is_truthy(
        buf_content(consumer_file):find("private BarService fooService = BarService.createDefault();", 1, true)
      )

      local xml = buf_content(xml_file)
      assert.is_truthy(xml:find('class="com.example.BarService"', 1, true))
      assert.is_truthy(xml:find('<!-- <bean id="commentedOut" class="com.example.FooService"/> -->', 1, true))
      assert.is_truthy(xml:find('class="com.other.FooService"', 1, true))
      assert.is_truthy(buf_content(other_service_file):find("public class FooService", 1, true))

      vim.fn.delete(root, "rf")
    end)

    it("a colliding rename (LSP error response) aborts before the quickfix preview and touches no file", function()
      local refactor = require("tetravim.util.refactor")
      local root = make_fixture()
      local java_file = root .. "/src/main/java/com/example/FooService.java"
      local before = table.concat(vim.fn.readfile(java_file), "\n")

      local fake_client = { id = 9003, name = "jdtls", offset_encoding = "utf-16", config = { root_dir = root } }
      local orig_get_clients = vim.lsp.get_clients
      local orig_buf_request_all = vim.lsp.buf_request_all
      local orig_select = vim.ui.select
      local orig_notify = vim.notify
      local select_called = false
      local saw_error = false
      vim.lsp.get_clients = function(_)
        return { fake_client }
      end
      vim.lsp.buf_request_all = function(_, _, _, handler)
        handler({ [fake_client.id] = { err = { message = "Element already exists: Consumer" } } })
      end
      vim.ui.select = function()
        select_called = true
      end
      vim.notify = function(_, level)
        if level == vim.log.levels.ERROR then
          saw_error = true
        end
      end

      vim.cmd("noautocmd edit " .. vim.fn.fnameescape(java_file))
      vim.api.nvim_win_set_cursor(0, { 6, 13 })
      refactor.project_rename("Consumer")
      vim.wait(2000, function()
        return not action_lock.is_busy()
      end, 20)

      vim.lsp.get_clients = orig_get_clients
      vim.lsp.buf_request_all = orig_buf_request_all
      vim.ui.select = orig_select
      vim.notify = orig_notify

      assert.is_false(select_called, "the quickfix confirm must never be shown for a colliding rename")
      assert.is_true(saw_error, "a visible ERROR naming the conflict is required")
      assert.are.equal(before, table.concat(vim.fn.readfile(java_file), "\n"))

      vim.fn.delete(root, "rf")
    end)

    it("scan_root_async still finds real Spring references via the grep fallback when rg is unavailable", function()
      local ts = require("tetravim.util.refactor_treesitter")
      local root = vim.fn.tempname()
      vim.fn.mkdir(root .. "/com/example", "p")
      vim.fn.writefile({
        "package com.example;",
        "",
        "import org.springframework.beans.factory.annotation.Autowired;",
        "",
        "public class Consumer {",
        "  @Autowired",
        "  private FooService fooService;",
        "}",
      }, root .. "/com/example/Consumer.java")

      local orig_system = vim.system
      vim.system = function(cmd, opts, callback)
        if cmd[1] == "rg" then
          error("rg forcibly disabled for this test (grep-fallback coverage)")
        end
        return orig_system(cmd, opts, callback)
      end

      local result = nil
      ts.scan_root_async(root, "FooService", "com.example", function(items)
        result = items
      end)
      vim.wait(10000, function()
        return result ~= nil
      end, 50)
      vim.system = orig_system

      assert.is_not_nil(result, "scan_root_async (grep fallback) did not complete within the wait window")
      assert.are.equal(1, #result)
      assert.are.equal("autowired", result[1].kind)

      vim.fn.delete(root, "rf")
    end)
  end)

  -- Migrated from scripts/validate-refactor.sh step [1/5]: the static guarantee
  -- that <leader>cr is bound at ftplugin top level (before on_attach), so the
  -- "no JVM LSP attached" row still gets project_rename's own notify. The
  -- dynamic wiring tests above prove the mapping exists and dispatches; this
  -- guards the ordering the dynamic test cannot see.
  it("ftplugin/java.lua binds <leader>cr before on_attach, and ftplugin/kotlin.lua exists + wires refactor", function()
    local java_src = assert(io.open("ftplugin/java.lua", "r")):read("*a")
    assert.is_truthy(java_src:match("tetravim%.util%.refactor"))
    local cr_set = java_src:find("<leader>cr", 1, true)
    local oa_pos = java_src:find("on_attach", 1, true)
    assert.is_truthy(cr_set, "ftplugin/java.lua must bind <leader>cr")
    assert.is_true(not oa_pos or cr_set < oa_pos, "<leader>cr must be bound before on_attach")

    local kotlin_fh = io.open("ftplugin/kotlin.lua", "r")
    assert.is_truthy(kotlin_fh, "ftplugin/kotlin.lua must exist")
    local kotlin_src = kotlin_fh:read("*a")
    assert.is_truthy(kotlin_src:match("tetravim%.util%.refactor"))
    assert.is_truthy(kotlin_src:match("<leader>cr"))
  end)
end)
