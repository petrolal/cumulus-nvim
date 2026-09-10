-- TetraVim Core Autocmds (Story 1.1)

local function augroup(name)
  return vim.api.nvim_create_augroup("tetravim_" .. name, { clear = true })
end

-- Discard any stray keystrokes typed into the terminal while Neovim was
-- still starting up (e.g. an extra "n" or "g" pressed right after
-- `nvim<CR>`). Without this, that buffered input gets replayed as
-- normal-mode commands the instant the dashboard buffer's single-key
-- mappings become active, unexpectedly opening a scratch buffer or the
-- grep picker instead of showing the dashboard.
-- NOTE: this must be deferred with vim.schedule rather than run inline in
-- the VimEnter callback -- some terminals (e.g. kitty) negotiate extended
-- keyboard protocol support over the same input stream right around
-- startup, and draining raw getchar() input synchronously at VimEnter can
-- race with and corrupt that in-flight handshake, which then shows up as
-- every keystroke getting duplicated for the rest of the session.
vim.api.nvim_create_autocmd("VimEnter", {
  group = augroup("flush_typeahead"),
  callback = function()
    vim.schedule(function()
      -- Bounded drain: a genuine startup typeahead buffer is a handful of
      -- stray keys, so cap the loop. An unbounded `while getchar(1) ~= 0`
      -- would spin forever if some input source keeps `getchar` non-empty
      -- (paste bracketing, a terminal still streaming its handshake).
      for _ = 1, 256 do
        if vim.fn.getchar(1) == 0 then
          break
        end
        vim.fn.getchar()
      end
    end)
  end,
})

-- Auto-open README.md once when Neovim is started on a project directory
-- (e.g. `nvim .`), so the project's landing doc is visible instead of a
-- blank "[No Name]" buffer. If there's no README, that blank buffer is left
-- alone -- it's already what shows up by default.
--
-- Snacks' netrw-replacement explorer opens as a *floating* picker on top of
-- that plain background window/buffer rather than replacing it, so editing
-- the README into the background window (instead of `:edit`-ing in the
-- window that's current when this fires, or opening a new tab) shows the
-- README and keeps the explorer float visible at the same time, with no
-- extra tab and no leftover blank buffer.
vim.api.nvim_create_autocmd("VimEnter", {
  group = augroup("open_readme"),
  once = true,
  callback = function()
    local dir = nil
    for _, arg in
      ipairs(vim.fn.argv() --[[@as string[] ]])
    do
      if vim.fn.isdirectory(arg) == 1 then
        dir = vim.fn.fnamemodify(arg, ":p")
        break
      end
    end
    if not dir then
      return
    end

    local matches = vim.fn.globpath(dir, "[Rr][Ee][Aa][Dd][Mm][Ee].md", false, true)
    if #matches == 0 then
      return
    end

    vim.schedule(function()
      for _, win in ipairs(vim.api.nvim_tabpage_list_wins(0)) do
        local buf = vim.api.nvim_win_get_buf(win)
        if vim.bo[buf].buftype == "" then
          vim.api.nvim_win_call(win, function()
            vim.cmd.edit(vim.fn.fnameescape(matches[1]))
            -- `:edit` on an already-loaded buffer keeps its last cursor
            -- position; force it back to the top so the README always
            -- opens at line 1, not wherever it was last left off.
            vim.api.nvim_win_set_cursor(win, { 1, 0 })
          end)
          break
        end
      end

      -- `nvim_win_call` above never moves focus (it runs the callback in
      -- the target window's context and restores focus immediately after),
      -- but explicitly refocusing the explorer here removes any dependency
      -- on that implicit behavior and any ordering with Snacks' own
      -- explorer-open scheduling -- land back on the explorer as directly
      -- as possible instead of leaving focus sitting in the README window.
      local ok, picker_mod = pcall(require, "snacks.picker")
      if ok then
        local explorer = picker_mod.get({ source = "explorer" })[1]
        if explorer then
          explorer:focus()
        end
      end
    end)
  end,
})

-- Sync Maven/Gradle dependencies once per session, at startup -- mirrors
-- the background "Syncing project..." step IDEs run automatically on open.
-- Runs on VimEnter regardless of which (if any) file gets opened first, so
-- it doesn't depend on happening to open a .java/.kt/.groovy/pom.xml/
-- build.gradle buffer -- it just checks whether the project has a pom.xml
-- or build.gradle(.kts) at all and syncs if so.
vim.api.nvim_create_autocmd("VimEnter", {
  group = augroup("build_sync"),
  once = true,
  callback = function()
    vim.schedule(function()
      require("tetravim.util.build-sync-state").run()
    end)
  end,
})

-- Re-sync Maven/Gradle dependencies whenever the project's build file is
-- saved -- mirrors IntelliJ's "auto-reload changed Maven/Gradle projects"
-- behavior instead of requiring a full Neovim restart to pick up new
-- dependencies. build-sync-state.lua's M.syncing guard (see M.run()) makes
-- this safe against overlapping saves -- a save that lands while a sync is
-- already in flight is a no-op, not a second process.
--
-- Debounced: a "Save All" that writes the root pom.xml plus several module
-- poms, or repeated :w while editing the build file, should trigger one
-- re-sync a few seconds after the last write -- not one `mvn
-- dependency:resolve` (a 120s-timeout process) per save. One reusable timer,
-- restarted on each save.
local build_sync_timer = assert(vim.uv.new_timer())
vim.api.nvim_create_autocmd("BufWritePost", {
  group = augroup("build_sync_on_save"),
  -- The first three are bare filenames -- Neovim matches those against just
  -- the tail, regardless of directory. The version catalog needs a leading
  -- "*/" since it contains a path separator: unlike shell globs, "*" in
  -- autocmd patterns crosses "/" boundaries, so "*/gradle/libs.versions.toml"
  -- matches that file at any project root, not just one directory up.
  pattern = { "pom.xml", "build.gradle", "build.gradle.kts", "*/gradle/libs.versions.toml" },
  callback = function()
    build_sync_timer:stop()
    build_sync_timer:start(
      2500,
      0,
      vim.schedule_wrap(function()
        local sync_state = require("tetravim.util.build-sync-state")
        sync_state.reset()
        sync_state.run()
      end)
    )
  end,
})

-- Highlight on yank
vim.api.nvim_create_autocmd("TextYankPost", {
  group = augroup("highlight_yank"),
  callback = function()
    (vim.hl or vim.highlight).on_yank()
  end,
})

-- Re-equalize splits when the terminal window is resized. `tabdo` walks
-- every tabpage, which normally fires BufLeave/BufEnter/WinEnter for each one
-- (re-triggering LSP/lint/statusline churn just from a resize); suppress that
-- with `eventignore` for the duration. `wincmd =` already leaves panels that
-- set `winfixwidth`/`winfixheight` (dap-ui, outline, dadbod, terminal) at
-- their size.
vim.api.nvim_create_autocmd({ "VimResized" }, {
  group = augroup("resize_splits"),
  callback = function()
    local current_tab = vim.fn.tabpagenr()
    local save_ei = vim.o.eventignore
    vim.o.eventignore = "all"
    pcall(function()
      vim.cmd("tabdo wincmd =")
      vim.cmd("tabnext " .. current_tab)
    end)
    vim.o.eventignore = save_ei
  end,
})

-- Close some filetypes with <q>
vim.api.nvim_create_autocmd("FileType", {
  group = augroup("close_with_q"),
  pattern = {
    "PlenaryTestPopup",
    "grug-far",
    "help",
    "lspinfo",
    "notify",
    "qf",
    "spectre_panel",
    "startuptime",
    "tsplayground",
    "neotest-output-panel",
    "checkhealth",
    "neotest-summary",
    "neotest-output",
  },
  callback = function(event)
    vim.bo[event.buf].buflisted = false
    vim.keymap.set("n", "q", "<cmd>close<cr>", {
      buffer = event.buf,
      silent = true,
      desc = "Quit buffer",
    })
  end,
})

-- Auto-insert Java package declaration and class header for new .java files (Story 38.3 & SPEC-017)
vim.api.nvim_create_autocmd("BufNewFile", {
  group = augroup("java_new_file"),
  pattern = "*.java",
  callback = function(event)
    local filepath = vim.api.nvim_buf_get_name(event.buf)
    local filename = vim.fn.fnamemodify(filepath, ":t:r")
    if filename == "" then
      return
    end

    local package_path = filepath:match("src/[^/]+/java/(.+)%/" .. filename .. "%.java")
      or filepath:match("src/(.+)%/" .. filename .. "%.java")

    local lines = {}
    if package_path then
      local package_name = package_path:gsub("/", ".")
      table.insert(lines, "package " .. package_name .. ";")
      table.insert(lines, "")
    end

    table.insert(lines, "public class " .. filename .. " {")
    table.insert(lines, "    ")
    table.insert(lines, "}")

    vim.api.nvim_buf_set_lines(event.buf, 0, -1, false, lines)
    vim.api.nvim_win_set_cursor(0, { #lines - 1, 4 })
  end,
})

-- Offer a file-type skeleton when a brand-new empty file of a recognised type
-- is opened (VSCode-style "suggest an initial template"). Prompts via
-- vim.ui.select; a "(no template)" entry always lets you decline, and it never
-- overwrites content an earlier hook (e.g. the Java skeleton above) inserted.
-- Disable entirely with `vim.g.tetravim_new_file_prompt = false`.
require("tetravim.util.filetemplate").setup_new_file_prompt()

-- Native LSP CodeLens auto-refresh for Java & Kotlin buffers.
-- Deliberately NOT on InsertLeave: that fires on every exit from insert mode
-- and each refresh is a codeLens round-trip to jdtls -- on a large class
-- that's a steady stream of requests for no visible benefit between saves.
-- BufEnter + BufWritePost is what actually changes the lenses.
-- Debounced per buffer: `BufEnter` fires on every window/tab hop back to a
-- Java/Kotlin file, and each refresh is a codeLens round-trip to jdtls. A
-- 250ms per-buffer timer collapses a burst of hops into a single request and
-- keeps the churn off the UI thread. Timers are closed on BufWipeout so the
-- table can't leak libuv handles over a long session.
local codelens_timers = {}

local function codelens_refresh(bufnr)
  if not vim.api.nvim_buf_is_valid(bufnr) then
    return
  end
  for _, client in ipairs(vim.lsp.get_clients({ bufnr = bufnr })) do
    if client:supports_method("textDocument/codeLens") then
      pcall(vim.lsp.codelens.refresh, { bufnr = bufnr })
      break
    end
  end
end

vim.api.nvim_create_autocmd({ "BufEnter", "BufWritePost" }, {
  group = augroup("lsp_codelens"),
  pattern = { "*.java", "*.kt" },
  callback = function(event)
    local bufnr = event.buf
    local timer = codelens_timers[bufnr]
    if not timer then
      timer = assert(vim.uv.new_timer())
      codelens_timers[bufnr] = timer
    end
    timer:stop()
    timer:start(
      250,
      0,
      vim.schedule_wrap(function()
        codelens_refresh(bufnr)
      end)
    )
  end,
})

vim.api.nvim_create_autocmd({ "BufWipeout", "BufDelete" }, {
  group = augroup("lsp_codelens_cleanup"),
  pattern = { "*.java", "*.kt" },
  callback = function(event)
    local timer = codelens_timers[event.buf]
    if timer then
      timer:stop()
      if not timer:is_closing() then
        timer:close()
      end
      codelens_timers[event.buf] = nil
    end
  end,
})

-- Archive & decompiled URI reader for JAR, ZIP, and virtual LSP URIs (e.g. jar://, jar:file://, zipfile://).
-- Enables seamless navigation ("Go to Definition", "Go to Implementation") into dependency JARs and .class files.
local function parse_archive_uri(uri)
  local jar, entry = uri:match("jar:[^/]*//(.-)!/(.*)$")
  if not jar then
    jar, entry = uri:match("jar:(.-)!/(.*)$")
  end
  if not jar then
    jar, entry = uri:match("zipfile://(.-)::(.*)$")
  end
  if not jar then
    jar, entry = uri:match("^(.-%.[jJ][aA][rR])!/(.*)$")
  end
  if not jar then
    jar, entry = uri:match("^(.-%.[zZ][iI][pP])!/(.*)$")
  end
  if not jar then
    jar, entry = uri:match("^(.-%.[jJ][aA][rR])::(.*)$")
  end
  if jar and jar:sub(1, 1) ~= "/" and not jar:match("^%a:") then
    jar = "/" .. jar
  end
  return jar, entry
end

vim.api.nvim_create_autocmd("BufReadCmd", {
  group = augroup("archive_reader"),
  pattern = { "jar://*", "*jar:file:/*", "zipfile://*", "*.jar!*", "*.zip!*" },
  callback = function(args)
    local raw_name = args.match
    local jar_path, inner_path = parse_archive_uri(raw_name)
    if not jar_path or not inner_path or vim.fn.filereadable(jar_path) ~= 1 then
      return
    end

    local bufnr = args.buf
    local is_class = inner_path:match("%.class$") ~= nil

    -- Show the extracted/decompiled contents synchronously would block the
    -- UI for as long as `javap` / `unzip` take on a large jar. Instead: drop
    -- a placeholder now, then fill the buffer from `vim.system` callbacks.
    local function fill(lines)
      if not vim.api.nvim_buf_is_valid(bufnr) then
        return
      end
      vim.bo[bufnr].modifiable = true
      vim.api.nvim_buf_set_lines(bufnr, 0, -1, false, lines)
      vim.bo[bufnr].modifiable = false
      vim.bo[bufnr].readonly = true
      local ft = is_class and "java" or vim.filetype.match({ filename = inner_path })
      if ft then
        vim.bo[bufnr].filetype = ft
      end
    end

    vim.bo[bufnr].modifiable = true
    vim.bo[bufnr].buftype = "nofile"
    vim.bo[bufnr].swapfile = false
    vim.api.nvim_buf_set_lines(bufnr, 0, -1, false, { "Loading " .. inner_path .. " ..." })
    vim.bo[bufnr].modifiable = false

    local function unzip_fallback()
      if vim.fn.executable("unzip") ~= 1 then
        fill({ "Cannot read " .. inner_path .. ": no 'javap' / 'unzip' on PATH" })
        return
      end
      vim.system(
        { "unzip", "-p", jar_path, inner_path },
        { text = true },
        vim.schedule_wrap(function(res)
          local out = vim.split(res.stdout or "", "\n", { plain = true })
          if #out == 0 or (res.code ~= 0 and (res.stdout or "") == "") then
            out = { "Failed to extract " .. inner_path, res.stderr or "" }
          end
          fill(out)
        end)
      )
    end

    if is_class and vim.fn.executable("javap") == 1 then
      local classname = inner_path:gsub("%.class$", ""):gsub("/", ".")
      vim.system(
        { "javap", "-cp", jar_path, classname },
        { text = true },
        vim.schedule_wrap(function(res)
          local out = vim.split(res.stdout or "", "\n", { plain = true })
          if res.code ~= 0 or #out == 0 or (out[1] and out[1]:match("^Error:")) then
            unzip_fallback()
          else
            fill(out)
          end
        end)
      )
    else
      unzip_fallback()
    end
  end,
})
