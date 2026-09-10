-- TetraVim Advanced Git Conflict Resolution (JetBrains / VS Code merge-tool
-- parity) -- SPEC-4.1 + SPEC-4.1 review remediation
--
-- diffview.nvim is the SOLE 3-way merge tool and file-history engine -- never
-- a hand-written conflict-marker parser or a custom diff/window UI (spec's
-- "Never" boundary). Story 4.2 reuses this same diff surface for PR review.
--
-- This file only wires the plugin up. The pure-Lua git work-tree guard that
-- every entry point runs first lives in tetravim.util.git; every entry point
-- also resolves the CURRENT BUFFER's repo root (not Neovim's process cwd) so
-- a multi-project session opens diffview against the right repo. All new
-- global keymaps sit under <leader>gc; diffview's own in-view / file-panel
-- conflict picks are retired and rebound onto <leader>gx* (per region) and
-- <leader>gX* (whole file) so the git mnemonic hierarchy Epic 4 mandates
-- stays intact. Whole-file / delete-region picks sit behind a confirm.
-- Views render in diffview's own persistent tabpage -- never floats.

local function git()
  return require("tetravim.util.git")
end

--- Run the shared pure-Lua git guard; returns true when it is safe to open a
--- view.
local function guard()
  return git().guard()
end

--- Resolve the current buffer's repo root and return a `-C<root>` flag token
--- (fnameescaped) to scope a :Diffview* command to that repo rather than the
--- process cwd. Returns "" when no root resolves (guard() has already run, so
--- this is belt-and-suspenders -- diffview then falls back to its own logic).
local function scope_flag()
  local root = git().repo_root()
  if not root or root == "" then
    return ""
  end
  return "-C" .. vim.fn.fnameescape(root) .. " "
end

--- Bail (with a warning, never a raw diffview stacktrace -- frozen boundary)
--- when the current buffer is not a viable :DiffviewFileHistory target:
--- it needs a written, readable, tracked file in a repo that has commits.
local function history_target_ok()
  local ui = require("tetravim.util.ui")
  local abspath = vim.fn.expand("%:p")

  if vim.bo.buftype ~= "" or abspath == "" or vim.fn.filereadable(abspath) ~= 1 then
    ui.notify_warn(
      "File history needs a saved, readable file in the current buffer -- write it first, or open a tracked file."
    )
    return false
  end

  if vim.bo.modified then
    ui.notify_warn("This buffer has unwritten changes -- save it before exploring its history.")
    return false
  end

  local root = git().repo_root()
  if not root then
    -- guard() already reported the real condition; stay silent here.
    return false
  end

  if not git().has_commits(root) then
    ui.notify_warn("This repository has no commits yet -- make an initial commit before exploring history.")
    return false
  end

  -- One deliberate, timeout-bounded probe: an untracked file has no history.
  local ok, res = pcall(function()
    return vim
      .system({ "git", "-C", root, "ls-files", "--error-unmatch", "--", abspath }, { text = true, timeout = 2000 })
      :wait()
  end)
  if not ok or type(res) ~= "table" or res.code ~= 0 then
    ui.notify_warn("This file is not tracked by git -- commit it first to explore its history.")
    return false
  end

  return true
end

--- Run `cmd` only when a diffview view is actually open; otherwise a silent
--- no-op -- close/toggle are not entry points, so a reflexive press in a
--- non-repo dir gets silence, never an error toast or a raw stacktrace.
local function if_view_open(cmd)
  local ok, view = pcall(function()
    return require("diffview.lib").get_current_view()
  end)
  if ok and view then
    vim.cmd(cmd)
  end
end

return {
  {
    "sindrets/diffview.nvim",
    dependencies = { "nvim-lua/plenary.nvim" },
    cmd = {
      "DiffviewOpen",
      "DiffviewClose",
      "DiffviewFileHistory",
      "DiffviewToggleFiles",
      "DiffviewFocusFiles",
    },
    -- Golden keymap set (SPEC-4.1 Design Notes). Every lhs is under <leader>gc.
    keys = {
      {
        "<leader>gco",
        function()
          if not guard() then
            return
          end
          -- Mid-merge: diffview auto-opens the 3-way merge tool. Clean tree:
          -- the working-tree diff (diffview's own empty state, no crash).
          -- `-C<root>` scopes it to the buffer's repo, not the process cwd.
          vim.cmd("DiffviewOpen " .. scope_flag())
        end,
        desc = "Conflict/compare: merge tool / working-tree diff",
      },
      {
        "<leader>gcq",
        function()
          if_view_open("DiffviewClose")
        end,
        desc = "Conflict/compare: close the diffview tabpage",
      },
      {
        "<leader>gch",
        function()
          if not guard() or not history_target_ok() then
            return
          end
          vim.cmd(("DiffviewFileHistory %s%s"):format(scope_flag(), vim.fn.fnameescape(vim.fn.expand("%:p"))))
        end,
        desc = "Conflict/compare: history for the current file",
      },
      {
        "<leader>gcH",
        function()
          if not guard() or not history_target_ok() then
            return
          end
          -- Read the selection bounds directly (the callback fires while still
          -- in visual mode, so the `'<`/`'>` marks aren't committed yet) and
          -- pass diffview an explicit line range plus an absolute file path.
          local l1, l2 = vim.fn.line("v"), vim.fn.line(".")
          if l1 > l2 then
            l1, l2 = l2, l1
          end
          vim.cmd(
            ("%d,%dDiffviewFileHistory %s%s"):format(l1, l2, scope_flag(), vim.fn.fnameescape(vim.fn.expand("%:p")))
          )
        end,
        mode = "x",
        desc = "Conflict/compare: history for the selected line range",
      },
      {
        "<leader>gcf",
        function()
          if_view_open("DiffviewToggleFiles")
        end,
        desc = "Conflict/compare: toggle the file panel",
      },
    },
    -- Function form: diffview.actions is only require()d after the plugin is
    -- loaded, so `require("tetravim.plugins.tools-diffview")` at spec-collection
    -- time (and the static spec test) never pulls in diffview itself.
    opts = function()
      local actions = require("diffview.actions")

      -- Wrap a destructive resolution action (whole-file pick, or delete the
      -- conflict region entirely) behind a yes/no confirm so a single
      -- keystroke can never silently discard a side.
      local function confirm_then(action, prompt)
        return function()
          if
            vim.g.tetravim_headless
            or #vim.api.nvim_list_uis() == 0
            or vim.fn.confirm(prompt, "&Yes\n&No", 2) == 1
          then
            action()
          end
        end
      end

      local WHOLE_FILE = {
        ["1"] = { "ours", "Resolve the WHOLE FILE to OURS? Every conflict region loses the other side." },
        ["2"] = { "base", "Resolve the WHOLE FILE to BASE? Every conflict region loses both sides' changes." },
        ["3"] = { "theirs", "Resolve the WHOLE FILE to THEIRS? Every conflict region loses our side." },
        ["a"] = { "all", "Keep ALL sides for EVERY conflict region in this file?" },
        ["0"] = { "none", "Delete EVERY conflict region in this file (keep neither side)?" },
      }

      -- Retire diffview's default conflict picks (not under the git mnemonic)
      -- and rebind them: <leader>gx* per region, <leader>gX* whole file.
      -- Shared between the `view` and `file_panel` keymap tables.
      local function conflict_binds(include_per_region)
        local binds = {}

        -- Disable every default pick that escapes <leader>gx* / <leader>gX*.
        for _, lhs in ipairs({
          "<leader>co",
          "<leader>ct",
          "<leader>cb",
          "<leader>ca",
          "<leader>cO",
          "<leader>cT",
          "<leader>cB",
          "<leader>cA",
          "dx",
          "dX",
        }) do
          table.insert(binds, { "n", lhs, false })
        end

        if include_per_region then
          -- Per-region picks: ours/base/theirs/all are non-destructive-silent
          -- (they act on one visible region), so no confirm. `none` deletes
          -- the region -> confirm.
          table.insert(
            binds,
            { "n", "<leader>gx1", actions.conflict_choose("ours"), { desc = "Conflict: choose OURS (region)" } }
          )
          table.insert(
            binds,
            { "n", "<leader>gx2", actions.conflict_choose("base"), { desc = "Conflict: choose BASE (region)" } }
          )
          table.insert(
            binds,
            { "n", "<leader>gx3", actions.conflict_choose("theirs"), { desc = "Conflict: choose THEIRS (region)" } }
          )
          table.insert(
            binds,
            { "n", "<leader>gxa", actions.conflict_choose("all"), { desc = "Conflict: choose ALL (region)" } }
          )
          table.insert(binds, {
            "n",
            "<leader>gx0",
            confirm_then(actions.conflict_choose("none"), "Delete this conflict region entirely (keep neither side)?"),
            { desc = "Conflict: delete region (confirm)" },
          })
        end

        -- Whole-file picks: every one rewrites all regions at once -> confirm.
        for _, key in ipairs({ "1", "2", "3", "a", "0" }) do
          local side, prompt = WHOLE_FILE[key][1], WHOLE_FILE[key][2]
          table.insert(binds, {
            "n",
            "<leader>gX" .. key,
            confirm_then(actions.conflict_choose_all(side), prompt),
            { desc = "Conflict: " .. side:upper() .. " for the whole file (confirm)" },
          })
        end

        return binds
      end

      local view_keymaps = conflict_binds(true)
      -- diffview defaults -- keep next/prev conflict navigation in the view.
      table.insert(view_keymaps, { "n", "]x", actions.next_conflict, { desc = "Next conflict" } })
      table.insert(view_keymaps, { "n", "[x", actions.prev_conflict, { desc = "Prev conflict" } })

      return {
        -- diff4_mixed: OURS | BASE | THEIRS with a distinct always-visible
        -- BASE pane -- matches AC 1 / the I/O matrix ("OURS / BASE / THEIRS")
        -- without any custom window code. (Frozen boundary: stays diff4_mixed.)
        view = {
          merge_tool = {
            layout = "diff4_mixed",
            disable_diagnostics = true,
          },
        },
        keymaps = {
          view = view_keymaps,
          -- File-panel picks resolve WHOLE files; only <leader>gX* (confirmed)
          -- may do that from the panel -- the raw cO/cT/cB/cA/dX defaults are
          -- retired (SPEC-4.1 review: silent one-keystroke destructive action).
          file_panel = conflict_binds(false),
        },
      }
    end,
    config = function(_, opts)
      require("diffview").setup(opts)

      -- Register the <leader>gx / <leader>gX which-key groups BUFFER-LOCALLY,
      -- for diffview buffers only (following lang-keymaps.lua's buffer = true
      -- pattern) -- they are meaningless outside a merge view, and <leader>gc
      -- stays the only global git-conflict group.
      local grp = vim.api.nvim_create_augroup("TetraVimDiffviewWhichKey", { clear = true })
      local function register_groups()
        local ok, wk = pcall(require, "which-key")
        if not ok then
          return
        end
        wk.add({
          { "<leader>gx", group = "conflict: pick side (region)", icon = "󰃻 ", buffer = 0 },
          { "<leader>gX", group = "conflict: pick side (whole file)", icon = "󰃻 ", buffer = 0 },
        })
      end
      vim.api.nvim_create_autocmd("User", {
        group = grp,
        pattern = { "DiffviewViewOpened", "DiffviewViewEnter" },
        callback = register_groups,
      })
      vim.api.nvim_create_autocmd("FileType", {
        group = grp,
        pattern = { "DiffviewFiles", "DiffviewFileHistory" },
        callback = register_groups,
      })
    end,
  },
}
