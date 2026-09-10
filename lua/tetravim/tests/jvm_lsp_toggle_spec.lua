-- lua/tetravim/tests/jvm_lsp_toggle_spec.lua
--
-- Covers tetravim.util.jvm.lsp_toggle -- the opt-in / RAM guard that keeps the
-- Quarkus + MicroProfile language servers (a ~1 GiB JVM each) from
-- auto-activating on top of jdtls. The busted child has no jars fetched, so
-- every activation path resolves to "blocked" without throwing.

local toggle = require("tetravim.util.jvm.lsp_toggle")

describe("tetravim.util.jvm.lsp_toggle", function()
  describe("available_ram_mb", function()
    it("returns a positive integer on Linux (or nil elsewhere)", function()
      local mb = toggle.available_ram_mb()
      if mb ~= nil then
        assert.is_true(mb > 0)
        assert.are.equal(mb, math.floor(mb))
      end
    end)
  end)

  describe("reason_blocked / should_autostart", function()
    it("is blocked on the jars when the bundles are not fetched", function()
      local fw = require("tetravim.util.jvm.frameworks")
      if not fw.quarkus_ready() then
        local reason = toggle.reason_blocked()
        assert.is_string(reason)
        assert.is_truthy(reason:match("jars not fetched"))
      end
    end)

    it("never auto-starts while it is blocked", function()
      if toggle.reason_blocked() ~= nil then
        assert.is_false(toggle.should_autostart())
      end
    end)

    it("should_autostart implies the opt-in flag is set", function()
      if toggle.should_autostart() then
        assert.is_true(toggle.is_enabled())
      end
    end)
  end)

  describe("toggle()", function()
    it("does not throw and does not opt in while blocked", function()
      if toggle.reason_blocked() == nil then
        return -- environment actually has the jars + RAM; skip
      end
      local was_enabled = toggle.is_enabled()
      assert.has_no.errors(function()
        toggle.toggle()
      end)
      -- A blocked enable must not leave the persisted flag behind.
      if not was_enabled then
        assert.is_false(toggle.is_enabled())
      end
    end)
  end)

  describe("rss_report", function()
    it("returns a list without throwing", function()
      local report = toggle.rss_report()
      assert.is_table(report)
      for _, entry in ipairs(report) do
        assert.is_string(entry.label)
        assert.is_number(entry.pid)
        assert.is_true(entry.rss_mb == nil or type(entry.rss_mb) == "number")
      end
    end)
  end)

  describe("activate()", function()
    it("returns false (no-op) when the jars are missing", function()
      local fw = require("tetravim.util.jvm.frameworks")
      if not (fw.quarkus_paths() and fw.microprofile_paths()) then
        assert.is_false(toggle.activate())
      end
    end)
  end)
end)
