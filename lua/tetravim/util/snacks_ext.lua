-- TetraVim snacks.nvim runtime patches + state toggles.
--
-- Carved out of lua/tetravim/plugins/editor-snacks.lua `config()` so the spec
-- stays declarative. Every function here is meant to be called once, from that
-- spec's `config`, after `require("snacks").setup(opts)` has run (they lean on
-- the `Snacks` global and on `snacks.*` submodules being requireable).

local M = {}

--- Suppress false-positive healthcheck ERROR when the terminal does not support
--- the Kitty graphics protocol (Alacritty, GNOME Terminal, plain TTY, tmux) and
--- WARNs about missing optional Tree-sitter parsers without upstream grammars
--- (e.g. norg) -- downgrading both to INFO since they are purely optional.
function M.suppress_image_health()
  local ok_img, snacks_image = pcall(require, "snacks.image")
  if not (ok_img and type(snacks_image.health) == "function") then
    return
  end
  local orig_image_health = snacks_image.health
  snacks_image.health = function()
    local orig_error = Snacks.health.error
    local orig_warn = Snacks.health.warn
    Snacks.health.error = function(msg)
      if type(msg) == "string" and msg:find("kitty graphics protocol") then
        Snacks.health.info(msg .. " (optional -- supported: kitty, wezterm, ghostty)")
      else
        orig_error(msg)
      end
    end
    Snacks.health.warn = function(msg)
      if
        type(msg) == "string"
        and (msg:find("Missing Treesitter languages") or msg:find("missing treesitter parsers"))
      then
        Snacks.health.info(msg .. " (optional -- e.g. `norg` has no upstream nvim-treesitter parser)")
      else
        orig_warn(msg)
      end
    end
    orig_image_health()
    Snacks.health.error = orig_error
    Snacks.health.warn = orig_warn
  end
end

--- Guard the Snacks picker jump action against "Invalid cursor line: out of
--- range" (folke/snacks.nvim#2939) when the target position exceeds the buffer
--- line count -- clamps the requested cursor into the valid range and swallows
--- a still-failing set.
function M.guard_picker_jump()
  local ok_actions, actions = pcall(require, "snacks.picker.actions")
  if not (ok_actions and actions and actions.jump) then
    return
  end
  local orig_jump = actions.jump
  actions.jump = function(picker, item_arg, action)
    local orig_set_cursor = vim.api.nvim_win_set_cursor
    vim.api.nvim_win_set_cursor = function(win, pos)
      local buf = vim.api.nvim_win_is_valid(win) and vim.api.nvim_win_get_buf(win)
      if buf and vim.api.nvim_buf_is_valid(buf) then
        local line_count = vim.api.nvim_buf_line_count(buf)
        if line_count > 0 then
          pos[1] = math.max(1, math.min(pos[1], line_count))
          local lines = vim.api.nvim_buf_get_lines(buf, pos[1] - 1, pos[1], false)
          local line_len = lines[1] and #lines[1] or 0
          pos[2] = math.max(0, math.min(pos[2] or 0, line_len))
        end
      end
      local ok, err = pcall(orig_set_cursor, win, pos)
      if not ok then
        return nil
      end
    end
    local ok_j, res = pcall(orig_jump, picker, item_arg, action)
    vim.api.nvim_win_set_cursor = orig_set_cursor
    if not ok_j then
      error(res)
    end
    return res
  end
end

--- State toggles under <leader>u. Snacks.toggle gives each one a get/set-backed
--- on/off notification and, via which-key, a filled/empty icon that mirrors the
--- live state -- so these replace the hand-rolled vim.keymap.set + vim.notify
--- blocks that used to sit in core/keymaps.lua. The buffer-scoped pair reads the
--- *effective* state (buffer override, else global) and writes only vim.b; the
--- global pair writes vim.g and clears the buffer override so it stops
--- shadowing.
function M.register_state_toggles()
  Snacks.toggle
    .new({
      id = "tetravim_autoformat_buffer",
      name = "Autoformat (Buffer)",
      get = function()
        return require("tetravim.util.edit.format").enabled(0)
      end,
      set = function(state)
        vim.b.autoformat = state
      end,
    })
    :map("<leader>uf")
  Snacks.toggle
    .new({
      id = "tetravim_autoformat_global",
      name = "Autoformat (Global)",
      get = function()
        return vim.g.autoformat ~= false
      end,
      set = function(state)
        vim.g.autoformat = state
        vim.b.autoformat = nil
      end,
    })
    :map("<leader>uF")
  Snacks.toggle
    .new({
      id = "tetravim_autolint_buffer",
      name = "Autolint (Buffer)",
      get = function()
        return require("tetravim.util.edit.lint").enabled(0)
      end,
      set = function(state)
        vim.b.autolint = state
      end,
    })
    :map("<leader>ul")
  Snacks.toggle
    .new({
      id = "tetravim_autolint_global",
      name = "Autolint (Global)",
      get = function()
        return vim.g.autolint ~= false
      end,
      set = function(state)
        vim.g.autolint = state
        vim.b.autolint = nil
      end,
    })
    :map("<leader>uL")
  Snacks.toggle
    .new({
      id = "tetravim_transparency",
      name = "Transparency",
      get = function()
        return require("tetravim.util.transparency").enabled
      end,
      set = function(state)
        require("tetravim.util.transparency").set(state)
      end,
    })
    :map("<leader>ut")
  -- Inlay hints: reads the real vim.lsp.inlay_hint state, writes through
  -- util/lsp_attach so the choice sticks for buffers that attach a client
  -- later (via vim.g.tetravim_inlay_hints).
  Snacks.toggle
    .new({
      id = "tetravim_inlay_hints",
      name = "Inlay Hints",
      get = function()
        return vim.lsp.inlay_hint ~= nil and vim.lsp.inlay_hint.is_enabled({})
      end,
      set = function()
        require("tetravim.util.lsp.attach").toggle_inlay_hints()
      end,
    })
    :map("<leader>uh")
  -- Diagnostic virtual_lines: swap the terse one-line virtual text for
  -- the multi-line current-line rendering (core/diagnostics.lua).
  Snacks.toggle
    .new({
      id = "tetravim_virtual_lines",
      name = "Diagnostic Virtual Lines",
      get = function()
        return require("tetravim.core.diagnostics").virtual_lines_enabled
      end,
      set = function()
        require("tetravim.core.diagnostics").toggle_virtual_lines()
      end,
    })
    :map("<leader>uv")
end

return M
