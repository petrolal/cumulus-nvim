-- TetraVim Language-Scoped Keymaps (Story 34.1)
--
-- Problem: every LSP/build-tool keymap used to live flat under the global
-- <leader>c "code/build/lsp" which-key group (Maven, Gradle, Terraform,
-- Ansible, Docker...). That meant opening <leader>c while editing a Python
-- file still showed Maven/Gradle build commands that only make sense for
-- Java/Kotlin -- the groups all merged together regardless of what you were
-- actually editing.
--
-- Fix: each language stack registers its keymaps here as BUFFER-LOCAL
-- mappings (vim.keymap.set(..., { buffer = <bufnr> })), applied only via a
-- FileType autocmd for the filetypes that stack owns. which-key mirrors
-- real keymaps, so a buffer-local mapping only ever shows up in the
-- <leader>c popup while you're editing a matching buffer -- switch to an
-- unrelated filetype and the group disappears on its own, no manual
-- show/hide bookkeeping required.
local M = {}

local ui = require("tetravim.util.ui")

-- Each entry: { filetypes = {...}, group = "<leader>cX", label = "...", icon = "...",
--               keys = { { lhs, rhs, desc }, ... } }
local stacks = {}

function M.register(stack)
  table.insert(stacks, stack)
end

local augroup = vim.api.nvim_create_augroup("tetravim_lang_keymaps", { clear = true })

function M.setup()
  local sync_state = require("tetravim.util.build_sync_state")

  local function apply(buf)
    if #stacks == 0 or not vim.api.nvim_buf_is_valid(buf) or vim.bo[buf].buftype ~= "" then
      return
    end
    local ft = vim.bo[buf].filetype

    for _, stack in ipairs(stacks) do
      -- Stacks marked ready_gate (java/kotlin/maven build & refactor)
      -- stay hidden until the one-time Maven/Gradle dependency sync
      -- finishes -- see lua/tetravim/util/build_sync_state.lua.
      if not (stack.ready_gate and not sync_state.ready) then
        local matches_ft = false
        if stack.filetypes then
          for _, pattern_ft in ipairs(stack.filetypes) do
            if pattern_ft == ft then
              matches_ft = true
              break
            end
          end
        end

        local matches_cond = false
        -- When a stack requires BOTH filetypes and condition (the AND-gate
        -- above), evaluating condition is wasted work whenever matches_ft is
        -- already false -- visible can never become true either way, and
        -- condition here means a pom.xml/build.gradle filesystem search on
        -- every FileType/BufEnter for every buffer, not just java/kotlin ones.
        local needs_condition = not (stack.filetypes and stack.condition and not matches_ft)
        if needs_condition and stack.condition and type(stack.condition) == "function" then
          local ok, res = pcall(stack.condition, buf)
          if ok and res then
            matches_cond = true
          elseif not ok then
            -- apply() re-runs on every FileType/BufEnter for every buffer, so
            -- a condition that fails persistently would otherwise spam a
            -- fresh toast per invocation. Give it a stable per-stack id so
            -- repeats replace the previous toast instead of stacking.
            ui.notify_warn(
              "TetraVim: lang_keymaps condition for " .. tostring(stack.group) .. " failed: " .. tostring(res),
              nil,
              { id = "tetravim_lang_keymaps_condition_" .. tostring(stack.group) }
            )
          end
        end

        -- A stack that declares BOTH filetypes and a condition needs both to
        -- hold (e.g. <leader>cj/<leader>cx: java/kotlin/groovy/xml filetype
        -- AND an actual pom.xml/build.gradle in the project) -- otherwise
        -- the condition is dead weight, since matches_ft alone would already
        -- satisfy an OR. A stack declaring only one of the two keeps today's
        -- behavior (the missing side is always false, so this reduces to OR).
        local visible
        if stack.filetypes and stack.condition then
          visible = matches_ft and matches_cond
        else
          visible = matches_ft or matches_cond
        end

        if visible then
          for _, k in ipairs(stack.keys or {}) do
            if not vim.api.nvim_buf_is_valid(buf) then
              break
            end
            local mode = k.mode or "n"
            local ok, err = pcall(vim.keymap.set, mode, k[1], k[2], { buffer = buf, desc = k[3] })
            if not ok then
              ui.notify_warn(
                "TetraVim: failed to set keymap " .. k[1] .. " for buffer " .. tostring(buf) .. ": " .. tostring(err),
                nil,
                { id = "tetravim_lang_keymaps_set_" .. tostring(buf) .. "_" .. k[1] }
              )
            end
          end
        end
      end
    end
  end

  -- apply() is idempotent but not free -- for a stack that declares a
  -- condition it runs a pom.xml/build.gradle filesystem search. FileType is
  -- the event that actually changes which stacks a buffer owns; BufEnter
  -- fires on every tab switch. Skip the BufEnter re-run when the buffer's
  -- filetype has not changed since we last applied to it. The post-sync
  -- re-application for gated stacks goes through sync_state.on_ready below,
  -- not this autocmd, so gating still resolves without a filetype change.
  vim.api.nvim_create_autocmd({ "FileType", "BufEnter" }, {
    group = augroup,
    callback = function(args)
      local ft = vim.bo[args.buf].filetype
      if args.event == "BufEnter" and vim.b[args.buf].tetravim_lang_keymaps_ft == ft then
        return
      end
      apply(args.buf)
      vim.b[args.buf].tetravim_lang_keymaps_ft = ft
    end,
  })

  for _, buf in ipairs(vim.api.nvim_list_bufs()) do
    apply(buf)
  end

  -- Once sync finishes, re-apply to every already-open buffer so gated
  -- keymaps show up immediately -- no need to leave/re-enter the buffer.
  -- Also explicitly clear which-key's per-buffer keymap cache: it only
  -- invalidates on LspAttach/BufReadPost/BufEnter/RecordingEnter, none of
  -- which fire just because we called vim.keymap.set() out of band here,
  -- so without this the popup could still show the pre-sync state.
  sync_state.on_ready(function()
    for _, buf in ipairs(vim.api.nvim_list_bufs()) do
      apply(buf)
    end
    local ok, wk_buf = pcall(require, "which-key.buf")
    if ok then
      wk_buf.clear()
    end
  end)
end

-- Which-key group specs for all registered stacks, so the popup shows a
-- proper label/icon for e.g. <leader>cj instead of an unnamed prefix. These
-- are buffer = true entries: which-key only displays them while the current
-- buffer actually owns matching buffer-local keymaps under that prefix.
function M.whichkey_spec()
  local spec = {}
  for _, stack in ipairs(stacks) do
    table.insert(spec, {
      stack.group,
      group = stack.label,
      icon = stack.icon,
    })
    if stack.subgroups then
      for _, sub in ipairs(stack.subgroups) do
        table.insert(spec, {
          sub.group,
          group = sub.label,
          icon = sub.icon,
        })
      end
    end
  end
  return spec
end

return M
