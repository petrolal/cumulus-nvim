local M = {}

local refactor = require("tetravim.util.refactor")
local action_lock = require("tetravim.util.action_lock")

M.ACTION_TIMEOUT_MS = 10000

local function notify_err(msg)
  vim.notify(msg, vim.log.levels.ERROR, { title = "TetraVim Extract" })
end

local function notify_warn(msg)
  vim.notify(msg, vim.log.levels.WARN, { title = "TetraVim Extract" })
end

local function notify_info(msg)
  vim.notify(msg, vim.log.levels.INFO, { title = "TetraVim Extract" })
end

--- Proceed with a single, already-disambiguated code action: apply it
--- directly if it carries a WorkspaceEdit, resolve it first via
--- codeAction/resolve if it only carries a command, or fail cleanly if
--- neither is possible.
local function proceed_with_action(bufnr, jvm_client, action_name, target_action)
  -- We need a WorkspaceEdit. If it has an edit, use it.
  if target_action.edit then
    M._show_preview(target_action.edit, jvm_client, action_name)
  elseif target_action.command then
    -- It has a command but no edit. We need to resolve it or it's not supported for dry-run.
    local caps = jvm_client.server_capabilities or {}
    local resolve_provider = type(caps.codeActionProvider) == "table" and caps.codeActionProvider.resolveProvider

    if resolve_provider then
      local resolve_responded = false
      local resolve_timer = vim.defer_fn(function()
        if resolve_responded then
          return
        end
        resolve_responded = true
        notify_err(action_name .. " resolve timed out waiting for '" .. jvm_client.name .. "'")
        action_lock.release()
      end, M.ACTION_TIMEOUT_MS)

      vim.lsp.buf_request_all(bufnr, "codeAction/resolve", target_action, function(resolve_responses)
        if resolve_responded then
          return
        end
        resolve_responded = true
        -- Response landed -- cancel the watchdog instead of leaving it
        -- pending for the full ACTION_TIMEOUT_MS.
        if resolve_timer and not resolve_timer:is_closing() then
          resolve_timer:stop()
          resolve_timer:close()
        end
        vim.schedule(function()
          local res = resolve_responses[jvm_client.id]
          if res and res.result and res.result.edit then
            M._show_preview(res.result.edit, jvm_client, action_name)
          else
            -- vim.lsp.buf_request_all per-client results carry `.err`, not `.error`.
            local rerr = res and (res.err or res.error)
            local err_msg = rerr and rerr.message or "no edit returned"
            notify_err(action_name .. ": server returned a command without an edit, and resolve failed: " .. err_msg)
            action_lock.release()
          end
        end)
      end)
    else
      notify_err(
        action_name
          .. ": server returned a command without an edit, and does not support codeAction/resolve. Dry-run preview is impossible."
      )
      action_lock.release()
    end
  else
    notify_warn("Code action for " .. action_name .. " returned no edit and no command.")
    action_lock.release()
  end
end

local function handle_action_response(bufnr, jvm_client, action_name, responses, kind_prefix, title_substring)
  local resp = responses[jvm_client.id]
  if not resp or resp.err then
    local detail = resp and resp.err and resp.err.message or "no response from language server"
    notify_err(action_name .. " aborted: " .. detail)
    action_lock.release()
    return
  end

  local actions = resp.result
  if not actions or #actions == 0 then
    notify_warn("No applicable " .. action_name .. " code action available here")
    action_lock.release()
    return
  end

  -- Collect EVERY matching action rather than just the first -- a real
  -- JDTLS/Kotlin LS response can legitimately return more than one action
  -- under the same kind/title (e.g. more than one enclosing scope offers
  -- "Extract to method"). Silently picking the first one is ambiguous
  -- and can extract/inline the wrong scope; the user must choose.
  local matches = {}
  for _, action in ipairs(actions) do
    local kind_match = action.kind and vim.startswith(action.kind, kind_prefix)
    local title_match = not title_substring or (action.title and string.find(action.title, title_substring, 1, true))
    if kind_match and title_match then
      matches[#matches + 1] = action
    end
  end

  if #matches == 0 then
    notify_warn("No applicable " .. action_name .. " code action available here")
    action_lock.release()
    return
  end

  if #matches == 1 then
    proceed_with_action(bufnr, jvm_client, action_name, matches[1])
    return
  end

  local titles = {}
  for _, action in ipairs(matches) do
    titles[#titles + 1] = action.title or "(untitled action)"
  end
  -- pcall guards against vim.ui.select itself throwing synchronously (e.g.
  -- no UI provider registered) -- without this, the lock would be stuck
  -- held forever with no callback ever firing to release it.
  local select_ok, select_err = pcall(vim.ui.select, titles, {
    prompt = string.format("Multiple '%s' actions available -- choose one:", action_name),
  }, function(_, idx)
    if not idx then
      notify_info(action_name .. " cancelled -- no action selected")
      action_lock.release()
      return
    end
    proceed_with_action(bufnr, jvm_client, action_name, matches[idx])
  end)
  if not select_ok then
    action_lock.release()
    notify_err(action_name .. ": vim.ui.select failed: " .. tostring(select_err))
  end
end

--- Describe a WorkspaceEdit's create/rename/delete resource operations as
--- quickfix-shaped rows. refactor.workspace_edit_to_locations drops these
--- (SPEC-2.1 keeps file-move out of scope), but Extract Interface's whole
--- point is a NEW interface file -- the dry-run preview must show it, and
--- an edit that is ONLY a CreateFile must not read as "no changes returned".
local function resource_op_rows(workspace_edit)
  local rows = {}
  local dc = workspace_edit and workspace_edit.documentChanges
  if type(dc) ~= "table" then
    return rows
  end
  local function fname(uri)
    local ok, f = pcall(vim.uri_to_fname, uri)
    return ok and f or uri
  end
  for _, change in ipairs(dc) do
    if change.kind == "create" then
      rows[#rows + 1] = { filename = fname(change.uri), lnum = 1, col = 1, text = "[new file] " .. fname(change.uri) }
    elseif change.kind == "rename" then
      rows[#rows + 1] = {
        filename = fname(change.newUri),
        lnum = 1,
        col = 1,
        text = "[rename] " .. fname(change.oldUri) .. " -> " .. fname(change.newUri),
      }
    elseif change.kind == "delete" then
      rows[#rows + 1] = { filename = fname(change.uri), lnum = 1, col = 1, text = "[delete] " .. fname(change.uri) }
    end
  end
  return rows
end

function M._show_preview(workspace_edit, jvm_client, action_name)
  local locations = refactor.workspace_edit_to_locations(workspace_edit) or {}
  local qf_items = vim.lsp.util.locations_to_items(locations, jvm_client.offset_encoding)
  vim.list_extend(qf_items, resource_op_rows(workspace_edit))

  if #qf_items == 0 then
    notify_warn(action_name .. ": no changes returned")
    action_lock.release()
    return
  end

  vim.fn.setqflist({}, " ", {
    title = string.format("%s (%d location%s)", action_name, #qf_items, #qf_items == 1 and "" or "s"),
    items = qf_items,
  })
  vim.cmd("copen")

  -- pcall guards against vim.ui.select itself throwing synchronously (e.g.
  -- no UI provider registered) -- without this, the lock would be stuck
  -- held forever with no callback ever firing to release it.
  local select_ok, select_err = pcall(vim.ui.select, { "Apply", "Cancel" }, {
    prompt = string.format("Apply %s to %d location(s)?", action_name, #qf_items),
  }, function(choice)
    if choice ~= "Apply" then
      notify_info(action_name .. " cancelled -- no changes applied")
      action_lock.release()
      return
    end

    local lsp_ok, lsp_err = pcall(vim.lsp.util.apply_workspace_edit, workspace_edit, jvm_client.offset_encoding)
    if not lsp_ok then
      notify_err(action_name .. ": failed to apply the LSP workspace edit (" .. tostring(lsp_err) .. ")")
      action_lock.release()
      return
    end

    notify_info(string.format("Applied %s across %d location(s)", action_name, #qf_items))
    action_lock.release()
  end)
  if not select_ok then
    action_lock.release()
    notify_err(action_name .. ": vim.ui.select failed: " .. tostring(select_err))
  end
end

local function do_action(action_name, kind_prefix, title_substring, is_visual)
  if action_lock.is_busy() then
    notify_warn("An action is already in progress -- please wait for it to finish")
    return
  end

  local bufnr = vim.api.nvim_get_current_buf()
  local win = vim.api.nvim_get_current_win()

  local jvm_client = refactor.find_jvm_client(bufnr)
  if not jvm_client then
    notify_warn("No " .. action_name .. " available for this buffer (no JDTLS/Kotlin LS client attached)")
    return
  end

  action_lock.acquire()

  -- Everything from here to the buf_request_all registration runs
  -- synchronously; a throw in make_range_params / the visual-mark block /
  -- character_offset / vim.diagnostic.get would otherwise strand the shared
  -- action_lock (disabling every extract AND project-rename for the
  -- session). pcall it and release on any failure.
  local setup_ok, setup_err = pcall(function()
    local params = vim.lsp.util.make_range_params(win, jvm_client.offset_encoding)

    -- If in visual mode, make_range_params only uses cursor position, so we
    -- override it with '< and '>. The marks are BYTE columns; splicing them
    -- straight into an LSP `character` field is wrong for any line containing
    -- multi-byte UTF-8 text before the selection (the LSP position would land
    -- on the wrong character, or an invalid one mid-codepoint) -- convert via
    -- vim.lsp.util.character_offset, per the client's own offset_encoding.
    if is_visual then
      -- Force Neovim to exit visual mode so that '< and '> marks are updated to the current selection
      vim.api.nvim_feedkeys(vim.api.nvim_replace_termcodes("<Esc>", true, false, true), "x", false)
      local start_pos = vim.api.nvim_buf_get_mark(bufnr, "<")
      local end_pos = vim.api.nvim_buf_get_mark(bufnr, ">")
      if start_pos[1] > 0 and end_pos[1] > 0 then
        local start_row, start_byte_col = start_pos[1] - 1, start_pos[2]
        local end_row, end_byte_col = end_pos[1] - 1, end_pos[2]

        -- A linewise (V) selection sets the '> column to MAXCOL
        -- (2147483647); clamp both marks to their line's real byte length
        -- so character_offset never gets an out-of-range column.
        local function clamp(row, col)
          local line = vim.api.nvim_buf_get_lines(bufnr, row, row + 1, false)[1] or ""
          return math.max(0, math.min(col, #line))
        end
        start_byte_col = clamp(start_row, start_byte_col)
        end_byte_col = clamp(end_row, end_byte_col)

        local start_char = start_byte_col > 0
            and vim.lsp.util.character_offset(bufnr, start_row, start_byte_col, jvm_client.offset_encoding)
          or 0
        local end_char = end_byte_col > 0
            and vim.lsp.util.character_offset(bufnr, end_row, end_byte_col, jvm_client.offset_encoding)
          or 0
        -- The visual '> mark is inclusive of its last byte; LSP ranges are
        -- end-exclusive, so nudge by one character to include it -- matching
        -- vim.lsp.util.make_given_range_params's own convention for the same
        -- "'selection' ~= 'exclusive'" case.
        if vim.o.selection ~= "exclusive" then
          end_char = end_char + 1
        end

        params.range = {
          start = { line = start_row, character = start_char },
          ["end"] = { line = end_row, character = end_char },
        }
      end
    end

    params.context = {
      diagnostics = vim.diagnostic.get(bufnr, { lnum = params.range.start.line }),
      only = { kind_prefix },
    }

    local responded = false
    local action_timer = vim.defer_fn(function()
      if responded then
        return
      end
      responded = true
      action_lock.release()
      notify_err(
        action_name
          .. " timed out waiting for '"
          .. jvm_client.name
          .. "' to respond ("
          .. (M.ACTION_TIMEOUT_MS / 1000)
          .. "s) -- no changes applied"
      )
    end, M.ACTION_TIMEOUT_MS)

    vim.lsp.buf_request_all(bufnr, "textDocument/codeAction", params, function(responses)
      if responded then
        return
      end
      responded = true
      if action_timer and not action_timer:is_closing() then
        action_timer:stop()
        action_timer:close()
      end
      vim.schedule(function()
        local hok, herr =
          pcall(handle_action_response, bufnr, jvm_client, action_name, responses, kind_prefix, title_substring)
        if not hok then
          action_lock.release()
          notify_err(action_name .. ": " .. tostring(herr))
        end
      end)
    end)
  end)

  if not setup_ok then
    action_lock.release()
    notify_err(action_name .. ": failed to start (" .. tostring(setup_err) .. ")")
  end
end

function M.extract_interface(is_visual)
  do_action("Extract interface", "refactor.extract.interface", nil, is_visual)
end

function M.inline(is_visual)
  do_action("Inline", "refactor.inline", nil, is_visual)
end

function M.extract_method(is_visual)
  do_action("Extract method", "refactor.extract", "Extract to method", is_visual)
end

function M.extract_variable(is_visual)
  do_action("Extract variable", "refactor.extract", "Extract to local variable", is_visual)
end

function M.extract_constant(is_visual)
  do_action("Extract constant", "refactor.extract", "Extract to constant", is_visual)
end

--- Register buffer-local intelligent extraction keymaps (<leader>ce, <leader>ci, <leader>cm, <leader>cv, <leader>cc)
---@param bufnr integer Buffer number to attach keymaps to
---@param lang_label string Language label for descriptions, e.g. "Java" or "Kotlin"
function M.setup_keymaps(bufnr, lang_label)
  lang_label = lang_label or "Java"
  local function map(mode, lhs, fn, desc)
    vim.keymap.set(mode, lhs, fn, { buffer = bufnr, desc = desc .. " (" .. lang_label .. ")" })
  end

  map("n", "<leader>ce", function()
    require("tetravim.util.extract").extract_interface()
  end, "Extract Interface")
  map("v", "<leader>ce", function()
    require("tetravim.util.extract").extract_interface(true)
  end, "Extract Interface")

  map("n", "<leader>ci", function()
    require("tetravim.util.extract").inline()
  end, "Inline")
  map("v", "<leader>ci", function()
    require("tetravim.util.extract").inline(true)
  end, "Inline")

  map("n", "<leader>cm", function()
    require("tetravim.util.extract").extract_method()
  end, "Extract Method")
  map("v", "<leader>cm", function()
    require("tetravim.util.extract").extract_method(true)
  end, "Extract Method")

  map("n", "<leader>cv", function()
    require("tetravim.util.extract").extract_variable()
  end, "Extract Variable")
  map("v", "<leader>cv", function()
    require("tetravim.util.extract").extract_variable(true)
  end, "Extract Variable")

  map("n", "<leader>cc", function()
    require("tetravim.util.extract").extract_constant()
  end, "Extract Constant")
  map("v", "<leader>cc", function()
    require("tetravim.util.extract").extract_constant(true)
  end, "Extract Constant")

  -- Annotate these buffer-local keys in the <leader>c ("code/lsp") which-key
  -- popup with the Refactor-band icon. They float to the top of the popup via
  -- which-key's built-in "local" sorter (buffer-local keys before global).
  pcall(function()
    require("which-key").add({
      { "<leader>ce", buffer = bufnr, icon = "󰆧 " },
      { "<leader>cm", buffer = bufnr, icon = "󰆧 " },
      { "<leader>cv", buffer = bufnr, icon = "󰆧 " },
      { "<leader>ci", buffer = bufnr, icon = "󰆧 " },
      { "<leader>cc", buffer = bufnr, icon = "󰆧 " },
    })
  end)
end

return M
