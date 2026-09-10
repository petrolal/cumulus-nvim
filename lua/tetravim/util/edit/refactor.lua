-- TetraVim Refactor: Project-Wide Safe Rename (SPEC-2.1)
--
-- Java/Kotlin rename today is a bare vim.lsp.buf.rename() (see the global
-- <leader>cr in core/keymaps.lua) -- it applies immediately, with no
-- cross-file preview and no awareness of Spring XML/annotation bean
-- references the LSP can't see. This module replaces that flow, buffer-
-- locally, for buffers with a JDTLS or Kotlin LS client attached:
--
--   1. Request textDocument/rename via vim.lsp.buf_request_all WITHOUT the
--      default handler, so nothing is applied yet (with a timeout guard --
--      see RENAME_TIMEOUT_MS -- so a non-responding server doesn't hang the
--      flow silently forever).
--   2. Merge in Tree-sitter/text-assisted Spring reference matches from
--      refactor_treesitter.lua (XML <bean class="...">, @Autowired fields,
--      stereotype-annotated classes), dropping any that overlap a location
--      the LSP's own WorkspaceEdit already covers (filter_overlapping_
--      spring_items) so nothing gets double-applied.
--   3. Populate the quickfix list as a dry-run preview (:copen) -- no
--      floating window, per this spec's Design Notes.
--   4. Confirm via vim.ui.select({'Apply', 'Cancel'}, ...); only 'Apply'
--      writes anything, via vim.lsp.util.apply_workspace_edit for the LSP
--      part and direct, column-precise line edits for the Spring part.
--      Both apply steps are failure-tracked so the final notification
--      accurately reflects a partial failure rather than always claiming
--      full success.
--
-- Everything here is async (vim.system/vim.schedule, matching the
-- convention in sync_runner.lua) and nothing is ever applied without an
-- explicit confirm. Only one rename can be in flight at a time (shared with
-- extract.lua via action_lock.lua) -- a second <leader>cr while one is
-- still running is rejected with a notify, rather than allowed to produce
-- overlapping previews. File-move handling is out of scope (deferred
-- separately); Scala/Metals/sbt are never touched.

local M = {}

local action_lock = require("tetravim.util.action_lock")

local ui = require("tetravim.util.ui")

--- How long to wait for a textDocument/rename response before giving up
--- and notifying the user, rather than leaving the flow silently hanging
--- forever if the server never replies.
M.RENAME_TIMEOUT_MS = 10000

local JVM_CLIENT_NAMES = {
  jdtls = true,
  kotlin_lsp = true,
  kotlin_language_server = true,
}

local function notify_err(msg)
  ui.notify_err(msg, "TetraVim Refactor")
end

local function notify_warn(msg)
  ui.notify_warn(msg, "TetraVim Refactor")
end

local function notify_info(msg)
  ui.notify_info(msg, "TetraVim Refactor")
end

--- A rename target must be a bare Java/Kotlin identifier -- no whitespace,
--- dots, or a leading digit -- or apply_spring_edits would splice the raw
--- string straight into `class <name>` across every location.
---@param name string
---@return boolean
local function valid_identifier(name)
  return name:match("^[%a_][%w_]*$") ~= nil
end

--- Find the JDTLS/Kotlin LS client attached to `bufnr`, if any.
---@param bufnr integer
---@return vim.lsp.Client|nil
function M.find_jvm_client(bufnr)
  local clients = vim.lsp.get_clients({ bufnr = bufnr })
  for _, client in ipairs(clients) do
    if JVM_CLIENT_NAMES[client.name] then
      return client
    end
  end
  return nil
end

--- Build a flat list of { uri, range } from a WorkspaceEdit's `changes`
--- and/or `documentChanges` (TextDocumentEdit entries only -- resource
--- operations such as file create/rename/delete are intentionally ignored;
--- file-move handling is out of scope for this spec).
---@param workspace_edit table
---@return table[]
function M.workspace_edit_to_locations(workspace_edit)
  local locations = {}
  if workspace_edit.changes then
    for uri, edits in pairs(workspace_edit.changes) do
      for _, edit in ipairs(edits) do
        locations[#locations + 1] = { uri = uri, range = edit.range }
      end
    end
  end
  if workspace_edit.documentChanges then
    for _, change in ipairs(workspace_edit.documentChanges) do
      if change.edits and change.textDocument then
        for _, edit in ipairs(change.edits) do
          locations[#locations + 1] = { uri = change.textDocument.uri, range = edit.range }
        end
      end
    end
  end
  return locations
end

--- Drop any `spring_items` entry whose (file, line, column-range) already
--- overlaps a location the LSP's own WorkspaceEdit covers -- e.g. a
--- stereotype-annotated class declaration touched by both the LSP rename
--- and the stereotype classifier. Without this, apply_spring_edits would
--- re-splice a line vim.lsp.util.apply_workspace_edit already rewrote,
--- using column coordinates captured before that edit ran, corrupting it.
---@param lsp_items table[] vim.quickfix.entry-shaped, from locations_to_items
---@param spring_items table[] { file, lnum, col, end_col, kind, text }
---@return table[]
function M.filter_overlapping_spring_items(lsp_items, spring_items)
  local lsp_by_key = {}
  for _, item in ipairs(lsp_items) do
    local key = vim.fn.fnamemodify(item.filename, ":p") .. ":" .. item.lnum
    lsp_by_key[key] = lsp_by_key[key] or {}
    table.insert(lsp_by_key[key], { col = item.col, end_col = item.end_col })
  end

  local filtered = {}
  for _, item in ipairs(spring_items) do
    local key = vim.fn.fnamemodify(item.file, ":p") .. ":" .. item.lnum
    local ranges = lsp_by_key[key]
    local overlaps = false
    if ranges then
      for _, r in ipairs(ranges) do
        if item.col < r.end_col and r.col < item.end_col then
          overlaps = true
          break
        end
      end
    end
    if not overlaps then
      filtered[#filtered + 1] = item
    end
  end
  return filtered
end

--- Convert refactor_treesitter.lua's classified Spring-reference hits into
--- vim.quickfix.entry-shaped items, tagged with a human-readable kind so
--- the preview distinguishes them from LSP-provided locations.
---@param spring_items table[]
---@return table[]
function M.spring_items_to_qf(spring_items)
  local kind_labels = {
    xml_bean = "[Spring XML bean]",
    autowired = "[Spring @Autowired]",
    stereotype = "[Spring stereotype]",
  }
  local qf = {}
  for _, item in ipairs(spring_items) do
    qf[#qf + 1] = {
      filename = item.file,
      lnum = item.lnum,
      col = item.col,
      end_col = item.end_col,
      text = (kind_labels[item.kind] or "[Spring]") .. " " .. item.text,
      user_data = { source = "spring", kind = item.kind, col = item.col, end_col = item.end_col },
    }
  end
  return qf
end

--- Apply the Spring-reference textual edits directly: splice `new_name`
--- into each recorded [col, end_col) span via nvim_buf_set_text, grouped
--- per file and applied bottom-to-top so earlier splices on the same line
--- never shift the column of a later one. Uses vim.fn.bufadd/bufload (the
--- same "load, don't write" approach vim.lsp.util.apply_text_edits takes)
--- rather than writing the file directly -- that keeps every touched file
--- in the same "edited buffer, not yet saved" state as the LSP-applied
--- files, so the user reviews/saves everything together through the
--- normal Neovim workflow instead of some files being silently flushed to
--- disk out from under an already-open, possibly-unsaved buffer for the
--- same path.
---@param spring_items table[]
---@param new_name string
---@param old_name string|nil when given, every [col,end_col) span is re-read
---  from the loaded buffer and skipped (its file marked failed) if it no
---  longer holds exactly `old_name` -- guards against splicing into a file
---  whose on-disk content (read at scan time) has since diverged from the
---  live buffer: an already-open file with unsaved edits, or one the user
---  edited in the :copen preview before pressing Apply.
---@return integer applied how many of #spring_items were actually applied
---@return string[] failed_files files where at least one edit failed (load, splice, or a stale span)
function M.apply_spring_edits(spring_items, new_name, old_name)
  local by_file = {}
  for _, item in ipairs(spring_items) do
    by_file[item.file] = by_file[item.file] or {}
    table.insert(by_file[item.file], item)
  end

  local applied = 0
  local failed_files = {}

  for file, items in pairs(by_file) do
    table.sort(items, function(a, b)
      if a.lnum ~= b.lnum then
        return a.lnum > b.lnum
      end
      return a.col > b.col
    end)

    -- Loading a not-yet-open file via bufadd/bufload fires FileType/
    -- BufReadPost autocmds same as a normal :edit -- for a .java/.kt file
    -- that means ftplugin/java.lua or lsp-kotlin.lua's on_attach actually
    -- launching a language server, as an unwanted side effect of applying
    -- a rename edit to a file the user never asked to open. eventignore
    -- suppresses that while still loading real buffer content to edit.
    local saved_eventignore = vim.o.eventignore
    vim.o.eventignore = "all"
    local ok, bufnr = pcall(vim.fn.bufadd, file)
    local loaded = false
    if ok and bufnr and bufnr ~= 0 then
      loaded = pcall(vim.fn.bufload, bufnr)
    end
    vim.o.eventignore = saved_eventignore

    if ok and loaded then
      local file_failed = false
      for _, item in ipairs(items) do
        -- Verify the span still holds `old_name` before overwriting it: the
        -- coordinates were captured from disk at scan time, so a file that
        -- is open with unsaved edits (or was edited in the preview) may have
        -- shifted content underneath them -- splicing blind would corrupt it.
        local span_ok = true
        if old_name ~= nil then
          local got_ok, cur =
            pcall(vim.api.nvim_buf_get_text, bufnr, item.lnum - 1, item.col - 1, item.lnum - 1, item.end_col - 1, {})
          span_ok = got_ok and cur[1] == old_name
        end

        local set_ok = span_ok
          and pcall(
            vim.api.nvim_buf_set_text,
            bufnr,
            item.lnum - 1,
            item.col - 1,
            item.lnum - 1,
            item.end_col - 1,
            { new_name }
          )
        if set_ok then
          applied = applied + 1
        else
          file_failed = true
        end
      end
      if file_failed then
        failed_files[#failed_files + 1] = file
      end
    else
      failed_files[#failed_files + 1] = file
    end
  end

  return applied, failed_files
end

--- Core async rename flow: request textDocument/rename for `new_name` at
--- the current cursor position without auto-applying, merge in Tree-sitter-
--- detected Spring references, preview everything via the quickfix list,
--- and apply only on explicit confirm.
---
--- If `new_name` is omitted, prompts for it via vim.ui.input (default: the
--- word under the cursor) before continuing -- this is the shape bound to
--- <leader>cr in ftplugin/java.lua and lsp-kotlin.lua. Passing `new_name`
--- directly (as tests do) skips the prompt.
---@param new_name string|nil
function M.project_rename(new_name)
  if action_lock.is_busy() then
    notify_warn("A project-wide rename is already in progress -- please wait for it to finish")
    return
  end

  local bufnr = vim.api.nvim_get_current_buf()
  local win = vim.api.nvim_get_current_win()

  local jvm_client = M.find_jvm_client(bufnr)
  if not jvm_client then
    notify_warn("No project-wide rename available for this buffer (no JDTLS/Kotlin LS client attached)")
    return
  end

  local old_name = vim.fn.expand("<cword>")
  if old_name == "" then
    notify_warn("No symbol under the cursor to rename")
    return
  end

  if new_name == nil then
    action_lock.acquire()
    -- pcall guards against vim.ui.input itself throwing synchronously (e.g.
    -- no UI provider registered) -- without this, the lock would be stuck
    -- held forever with no callback ever firing to release it.
    local input_ok, input_err = pcall(vim.ui.input, {
      prompt = "Project-wide rename '" .. old_name .. "' to: ",
      default = old_name,
    }, function(input)
      if not input then
        action_lock.release()
        return
      end
      input = vim.trim(input)
      if input == "" then
        action_lock.release()
        return
      end
      if input == old_name then
        notify_info("New name is the same as the current name -- nothing to do")
        action_lock.release()
        return
      end
      if not valid_identifier(input) then
        notify_err("Project rename: '" .. input .. "' is not a valid identifier -- no changes applied")
        action_lock.release()
        return
      end
      -- _do_rename already acquires the lock, so this is just a safe pass
      M._do_rename(bufnr, win, jvm_client, old_name, input)
    end)
    if not input_ok then
      action_lock.release()
      notify_err("Project rename: vim.ui.input failed: " .. tostring(input_err))
    end
    return
  end

  new_name = vim.trim(new_name)
  if new_name == "" then
    return
  end
  if new_name == old_name then
    notify_info("New name is the same as the current name -- nothing to do")
    return
  end
  if not valid_identifier(new_name) then
    notify_err("Project rename: '" .. new_name .. "' is not a valid identifier -- no changes applied")
    return
  end

  M._do_rename(bufnr, win, jvm_client, old_name, new_name)
end

--- Internal: runs once new_name is known and a JVM client is confirmed
--- attached. Split out from project_rename so tests can call it directly
--- with an already-known name (see project_rename's doc comment). Marks
--- the rename in-flight (action_lock.lua) and guards the request with a
--- timeout so a non-responding server can't hang the flow silently forever.
---@param bufnr integer
---@param win integer
---@param jvm_client vim.lsp.Client
---@param old_name string
---@param new_name string
function M._do_rename(bufnr, win, jvm_client, old_name, new_name)
  action_lock.acquire()

  local params = vim.lsp.util.make_position_params(win, jvm_client.offset_encoding)
  params.newName = new_name

  local responded = false

  local timeout_timer = vim.defer_fn(function()
    if responded then
      return
    end
    responded = true
    action_lock.release()
    notify_err(
      "Project rename timed out waiting for '"
        .. jvm_client.name
        .. "' to respond to textDocument/rename ("
        .. (M.RENAME_TIMEOUT_MS / 1000)
        .. "s) -- no changes applied"
    )
  end, M.RENAME_TIMEOUT_MS)

  require("tetravim.util.lsp.async").request_all_async(bufnr, "textDocument/rename", params, function(responses)
    if responded then
      -- The timeout already fired and notified; ignore a very late response.
      return
    end
    responded = true
    -- Cancel the watchdog now that a response landed -- otherwise it stays
    -- pending for the full RENAME_TIMEOUT_MS before firing into a no-op.
    if timeout_timer and not timeout_timer:is_closing() then
      timeout_timer:stop()
      timeout_timer:close()
    end
    vim.schedule(function()
      M._on_rename_response(bufnr, jvm_client, old_name, new_name, responses)
    end)
  end)
end

--- Internal: handles the raw textDocument/rename response set (already
--- vim.schedule'd), validates it, kicks off the Spring reference scan
--- (package-scoped to the renamed symbol's own file), filters out any
--- Spring match that overlaps an LSP-provided location, and proceeds to
--- the merged preview.
function M._on_rename_response(bufnr, jvm_client, old_name, new_name, responses)
  local resp = responses[jvm_client.id]
  if not resp or resp.err then
    local detail = resp and resp.err and resp.err.message or "no response from language server"
    notify_err("Project rename aborted for '" .. old_name .. "' -> '" .. new_name .. "': " .. detail)
    action_lock.release()
    return
  end

  local workspace_edit = resp.result
  if not workspace_edit or (not workspace_edit.changes and not workspace_edit.documentChanges) then
    notify_warn("Project rename: no changes returned for '" .. old_name .. "'")
    action_lock.release()
    return
  end

  -- workspace_edit_to_locations intentionally drops create/rename/delete
  -- resource operations (file-move handling is out of scope for this spec),
  -- but the user must be told rather than left with e.g. FooService.java
  -- silently holding `class BarService` after the rename.
  if workspace_edit.documentChanges then
    local resource_ops = 0
    for _, change in ipairs(workspace_edit.documentChanges) do
      if change.kind == "create" or change.kind == "rename" or change.kind == "delete" then
        resource_ops = resource_ops + 1
      end
    end
    if resource_ops > 0 then
      notify_warn(
        string.format(
          "Project rename: %d file move/rename operation(s) from '%s' were skipped (file-move handling is out of scope) -- rename the file(s) manually.",
          resource_ops,
          jvm_client.name
        )
      )
    end
  end

  local locations = M.workspace_edit_to_locations(workspace_edit)
  local lsp_items = vim.lsp.util.locations_to_items(locations, jvm_client.offset_encoding)

  local root = jvm_client.config.root_dir
  local refactor_ts = require("tetravim.util.edit.refactor_treesitter")
  local old_package = refactor_ts.file_package(vim.api.nvim_buf_get_lines(bufnr, 0, -1, false))

  if not root then
    -- Falling back to cwd here would silently scan the wrong tree (whatever
    -- directory Neovim happened to be started/`:cd`'d in, not this
    -- project's actual root) -- warn and skip the Spring scan instead,
    -- keeping the LSP-provided locations only.
    notify_warn(
      "Project rename: '"
        .. jvm_client.name
        .. "' reported no root_dir -- skipping the Spring XML/@Autowired/stereotype reference scan (LSP-provided locations only)"
    )
    M._show_preview(workspace_edit, jvm_client, old_name, new_name, lsp_items, {})
    return
  end

  refactor_ts.scan_root_async(root, old_name, old_package, function(spring_items)
    spring_items = M.filter_overlapping_spring_items(lsp_items, spring_items)
    M._show_preview(workspace_edit, jvm_client, old_name, new_name, lsp_items, spring_items)
  end)
end

--- Internal: builds and opens the merged quickfix preview, then confirms
--- via vim.ui.select before applying anything. On Apply, the LSP edit is
--- applied first (pcall-guarded -- a failure here aborts entirely, since
--- applying only the Spring text edits after a failed LSP edit would leave
--- a worse, half-renamed state than not applying at all); the Spring edits
--- are applied second and failure-tracked so the final notification
--- reflects a partial failure rather than always claiming full success.
function M._show_preview(workspace_edit, jvm_client, old_name, new_name, lsp_items, spring_items)
  local qf_items = {}
  vim.list_extend(qf_items, lsp_items)
  vim.list_extend(qf_items, M.spring_items_to_qf(spring_items))

  if #qf_items == 0 then
    notify_warn("Project rename: no locations found for '" .. old_name .. "'")
    action_lock.release()
    return
  end

  vim.fn.setqflist({}, " ", {
    title = string.format(
      "Rename '%s' -> '%s' (%d location%s)",
      old_name,
      new_name,
      #qf_items,
      #qf_items == 1 and "" or "s"
    ),
    items = qf_items,
  })
  vim.cmd("copen")

  -- pcall guards against vim.ui.select itself throwing synchronously (e.g.
  -- no UI provider registered) -- without this, the lock would be stuck
  -- held forever with no callback ever firing to release it.
  local select_ok, select_err = pcall(vim.ui.select, { "Apply", "Cancel" }, {
    prompt = string.format("Apply rename '%s' -> '%s' to %d location(s)?", old_name, new_name, #qf_items),
  }, function(choice)
    if choice ~= "Apply" then
      notify_info("Project rename cancelled -- no changes applied")
      action_lock.release()
      return
    end

    -- Loading/editing files via apply_workspace_edit can fire FileType/
    -- BufReadPost/etc. autocmds for any file it touches that isn't already
    -- open (e.g. launching an unwanted language server) -- eventignore
    -- suppresses that side effect while still applying the edit, mirroring
    -- the same guard apply_spring_edits below already uses.
    local saved_eventignore = vim.o.eventignore
    vim.o.eventignore = "all"
    local lsp_ok, lsp_err = pcall(vim.lsp.util.apply_workspace_edit, workspace_edit, jvm_client.offset_encoding)
    vim.o.eventignore = saved_eventignore
    if not lsp_ok then
      notify_err(
        "Project rename: failed to apply the LSP workspace edit ("
          .. tostring(lsp_err)
          .. ") -- Spring-reference edits were not applied either, to avoid a half-applied rename"
      )
      action_lock.release()
      return
    end

    local spring_applied, spring_failed_files = 0, {}
    if #spring_items > 0 then
      spring_applied, spring_failed_files = M.apply_spring_edits(spring_items, new_name, old_name)
    end

    local total_applied = #lsp_items + spring_applied
    if #spring_failed_files > 0 then
      notify_warn(
        string.format(
          "Renamed %d/%d location(s) -- %d Spring-reference edit(s) failed in: %s",
          total_applied,
          #qf_items,
          #spring_items - spring_applied,
          table.concat(spring_failed_files, ", ")
        )
      )
    else
      notify_info(string.format("Renamed '%s' -> '%s' across %d location(s)", old_name, new_name, #qf_items))
    end
    action_lock.release()
  end)
  if not select_ok then
    action_lock.release()
    notify_err("Project rename: vim.ui.select failed: " .. tostring(select_err))
  end
end

return M
