-- TetraVim "New File from Template" engine
--
-- IntelliJ IDEA Ultimate's `New > Java Class / Kotlin Class / HTML File / ...`
-- action, ported to native Neovim. One entry point (`M.new_file()` behind
-- `<leader>fn` / `:TetraVimNewFile`) opens a context-aware picker of file
-- templates; picking one prompts for a name, resolves the target path
-- (deriving the JVM package from the directory layout), scaffolds the file
-- on disk and opens it with the cursor parked at the `${cursor}` marker.
--
-- Design, per CLAUDE.md conventions:
--   * All logic lives here; the keymap in core/keymaps.lua is a thin dispatch.
--   * Every built-in template is a pure `body(ctx) -> string` function -- no
--     external binary is required, so the feature always degrades to a plain
--     `vim.notify` and never hard-errors.
--   * User templates drop into `stdpath("config")/templates/`; each file is
--     one template, its extension is the target extension, `${NAME}` /
--     `$NAME$` (+ friends) are substituted, and an optional first-line
--     `tetravim:` directive comment can set the label / language tags.

local ui = require("tetravim.util.ui")

local M = {}

M.TITLE = "TetraVim New File"

--- Directory holding user-supplied templates (one file == one template).
function M.user_dir()
  return vim.fs.normalize(vim.fn.stdpath("config") .. "/templates")
end

-- ---------------------------------------------------------------------------
-- Context helpers
-- ---------------------------------------------------------------------------

--- The directory a "new file" action should target: the browsed directory in
--- an oil buffer, else the current file's parent, else the working dir.
---@return string
function M.target_dir()
  if vim.bo.filetype == "oil" then
    local ok, oil = pcall(require, "oil")
    if ok then
      local dir = oil.get_current_dir()
      if dir and dir ~= "" then
        return vim.fs.normalize((dir:gsub("/$", "")))
      end
    end
  end
  local buf_name = vim.api.nvim_buf_get_name(0)
  if buf_name ~= "" and vim.bo.buftype == "" then
    return vim.fs.normalize(vim.fn.fnamemodify(buf_name, ":p:h"))
  end
  return vim.fs.normalize(vim.fn.getcwd())
end

--- Nearest project root above `dir` (build-tool / VCS markers), else `dir`.
---@param dir string
---@return string
function M.project_root(dir)
  local markers = {
    "pom.xml",
    "build.gradle",
    "build.gradle.kts",
    "settings.gradle",
    "settings.gradle.kts",
    "build.sbt",
    ".git",
  }
  local found = vim.fs.find(markers, { upward = true, path = dir, type = "file" })[1]
    or vim.fs.find({ ".git" }, { upward = true, path = dir })[1]
  if found then
    return vim.fs.normalize(vim.fn.fnamemodify(found, ":h"))
  end
  return dir
end

--- Derive a JVM package name from a source directory using the standard
--- `.../src/<sourceSet>/<lang>/<pkg>/<path>` layout (Maven & Gradle, single-
--- or multi-module). Returns "" when `dir` is not under a recognised source
--- root.
---@param dir string
---@return string
function M.derive_package(dir)
  dir = vim.fs.normalize(vim.fn.fnamemodify(dir, ":p")):gsub("/$", "")

  -- .../src/<sourceSet>/<lang>/<pkg path>   (src/main/java/com/foo)
  local lang, pkg = dir:match("/src/[^/]+/(%a+)/(.+)$")
  -- .../src/<lang>/<pkg path>               (rare flat src/java/com/foo)
  if not pkg then
    lang, pkg = dir:match("/src/(%a+)/(.+)$")
  end
  if not pkg or pkg == "" then
    return ""
  end
  -- A recognised JVM source directory, not a resources / webapp / gen tree.
  local jvm_langs = { java = true, kotlin = true, scala = true, groovy = true }
  if not jvm_langs[lang] then
    return ""
  end
  return (pkg:gsub("/", "."))
end

--- Best-effort "primary language" for ordering the picker: the current
--- buffer's filetype, or the dominant source language of `root` when the
--- current buffer has none (dir / empty / oil).
---@param root string
---@return string|nil
local function context_language(root)
  local ft = vim.bo.filetype
  if ft ~= nil and ft ~= "" and ft ~= "oil" and ft ~= "snacks_picker_list" then
    return ft
  end
  for _, probe in ipairs({
    { ft = "java", glob = "/**/*.java" },
    { ft = "kotlin", glob = "/**/*.kt" },
    { ft = "scala", glob = "/**/*.scala" },
    { ft = "groovy", glob = "/**/*.groovy" },
    { ft = "typescript", glob = "/*.ts" },
    { ft = "python", glob = "/**/*.py" },
  }) do
    if #vim.fn.glob(root .. probe.glob, true, true) > 0 then
      return probe.ft
    end
  end
  return nil
end

--- Build the substitution context shared by every template body.
---@param name string   Bare type / file name (no extension, no path)
---@param dir string    Final parent directory of the file
---@param root string    Project root
---@return table
local function make_ctx(name, dir, root)
  local now = os.time()
  return {
    name = name,
    package = M.derive_package(dir),
    dir = dir,
    root = root,
    filename = name,
    date = os.date("%Y-%m-%d", now),
    time = os.date("%H:%M", now),
    year = os.date("%Y", now),
    user = vim.env.USER or vim.env.USERNAME or "author",
    guard = name:upper():gsub("[^%w]", "_") .. "_H",
  }
end

-- ---------------------------------------------------------------------------
-- Built-in templates
-- ---------------------------------------------------------------------------

--- Built-in template bodies. The ~590-line catalog lives in its own file;
--- `jpkg` / `kpkg` (package-prefix helpers) moved with it. Re-exported here
--- so call sites and tests keep using `filetemplate.builtin`.
--- @type table<string, { label: string, category: string, ext: string, langs: string[], fixed_name?: string, body: fun(ctx: table): string }>
M.builtin = require("tetravim.util.edit.filetemplate.builtins")

-- ---------------------------------------------------------------------------
-- User templates
-- ---------------------------------------------------------------------------

--- Parse an optional first-line directive:
---   `<!-- tetravim: label=My Page langs=html,vue -->`
---   `-- tetravim: label=Spec langs=lua`
--- Returns (directives_table_or_nil, body_without_directive_line).
---@param raw string
---@return table|nil, string
local function parse_directive(raw)
  local first, rest = raw:match("^([^\n]*)\n?(.*)$")
  if not first then
    return nil, raw
  end
  local payload = first:match("tetravim:%s*(.-)%s*%-?%->?%s*$")
  if not payload then
    return nil, raw
  end
  local d = {}
  for key, val in payload:gmatch("(%w+)=([^%s]+)") do
    if key == "langs" then
      d.langs = vim.split(val, ",", { trimempty = true })
    else
      d[key] = val
    end
  end
  return d, rest
end

--- Load every file under `stdpath("config")/templates/` as a template.
---@return table<string, table>
function M.load_user_templates()
  local out = {}
  local dir = M.user_dir()
  if vim.fn.isdirectory(dir) == 0 then
    return out
  end
  for name, typ in vim.fs.dir(dir) do
    if typ == "file" then
      local path = dir .. "/" .. name
      local ok, lines = pcall(vim.fn.readfile, path)
      if ok then
        local raw = table.concat(lines, "\n")
        local directives, body = parse_directive(raw)
        directives = directives or {}
        local ext = name:match("%.([%w]+)$") or directives.ext or "txt"
        out["user." .. name] = {
          label = (directives.label and directives.label:gsub("_", " ")) or ("User: " .. name),
          category = "User Templates",
          ext = directives.ext or ext,
          langs = directives.langs or {},
          user_body = body,
          source = path,
        }
      end
    end
  end
  return out
end

--- Substitute `${NAME}` / `$NAME$` style placeholders in a user template body.
---@param body string
---@param ctx table
---@return string
local function expand_user_body(body, ctx)
  local map = {
    NAME = ctx.name,
    PACKAGE = ctx.package,
    DATE = ctx.date,
    TIME = ctx.time,
    YEAR = ctx.year,
    USER = ctx.user,
    GUARD = ctx.guard,
  }
  body = body:gsub("%${(%w+)}", function(k)
    return map[k] ~= nil and tostring(map[k]) or ("${" .. k .. "}")
  end)
  body = body:gsub("%$(%w+)%$", function(k)
    return map[k] ~= nil and tostring(map[k]) or ("$" .. k .. "$")
  end)
  return body
end

-- ---------------------------------------------------------------------------
-- Catalogue assembly & rendering
-- ---------------------------------------------------------------------------

--- Full template list (built-in + user), each entry carrying its `id`.
---@return table[]
function M.all_templates()
  local list = {}
  for id, t in pairs(M.builtin) do
    list[#list + 1] = vim.tbl_extend("keep", { id = id }, t)
  end
  for id, t in pairs(M.load_user_templates()) do
    list[#list + 1] = vim.tbl_extend("keep", { id = id }, t)
  end
  return list
end

--- Render a template body to (content, cursor_row_0indexed, cursor_col).
--- The `${cursor}` marker is removed and its position reported so the caller
--- can park the cursor there.
---@param tmpl table
---@param ctx table
---@return string content, integer row, integer col
function M.render(tmpl, ctx)
  local content
  if tmpl.user_body then
    content = expand_user_body(tmpl.user_body, ctx)
  else
    content = tmpl.body(ctx)
  end

  local row, col = 0, 0
  local lines = vim.split(content, "\n", { plain = true })
  for i, line in ipairs(lines) do
    local s = line:find("${cursor}", 1, true)
    if s then
      row = i - 1
      col = s - 1
      lines[i] = line:gsub("%${cursor}", "", 1)
      break
    end
  end
  return table.concat(lines, "\n"), row, col
end

-- ---------------------------------------------------------------------------
-- Creation flow
-- ---------------------------------------------------------------------------

--- Resolve the entered name into (parent_dir, bare_name). A name containing
--- `/` or `.` (FQN or relative path) is expanded beneath `base_dir`, exactly
--- like IntelliJ's "Name" field.
---@param entered string
---@param base_dir string
---@param ext string
---@return string parent_dir, string bare_name
local function resolve_name(entered, base_dir, ext)
  entered = vim.trim(entered)
  -- Strip a trailing extension the user may have typed.
  if ext ~= "" then
    entered = entered:gsub("%." .. vim.pesc(ext) .. "$", "")
  end
  local sub = entered
  if not entered:find("/", 1, true) and entered:find(".", 1, true) then
    -- Dotted FQN -> path (Java/Kotlin/Scala idiom).
    sub = entered:gsub("%.", "/")
  end
  local parent = base_dir
  local bare = sub
  if sub:find("/", 1, true) then
    parent = base_dir .. "/" .. vim.fn.fnamemodify(sub, ":h")
    bare = vim.fn.fnamemodify(sub, ":t")
  end
  return vim.fs.normalize(parent), bare
end

--- Write `tmpl` to disk for the given `entered` name. Pure filesystem work,
--- no prompting and no window changes -- returns `path, row, col` on success
--- (row/col 0-indexed cursor target) or `nil, errkind` where errkind is
--- "exists" | "mkdir" | "write".
---@param tmpl table
---@param entered string
---@param base_dir string
---@param root string
---@return string|nil path, integer|string row_or_err, integer? col
function M.scaffold(tmpl, entered, base_dir, root)
  local parent, bare = resolve_name(entered, base_dir, tmpl.ext)
  local fname = tmpl.ext ~= "" and (bare .. "." .. tmpl.ext) or bare
  local path = parent .. "/" .. fname

  if vim.fn.filereadable(path) == 1 then
    return nil, "exists"
  end
  if not pcall(vim.fn.mkdir, parent, "p") then
    return nil, "mkdir"
  end

  local ctx = make_ctx(bare, parent, root)
  local content, crow, ccol = M.render(tmpl, ctx)
  if not pcall(vim.fn.writefile, vim.split(content, "\n", { plain = true }), path) then
    return nil, "write"
  end
  if tmpl.executable then
    pcall(vim.fn.setfperm, path, "rwxr-xr-x")
  end
  return path, crow, ccol
end

--- Scaffold `tmpl` after prompting for a name; opens the new file with the
--- cursor parked at the `${cursor}` marker.
---@param tmpl table
---@param base_dir string
---@param root string
function M.create(tmpl, base_dir, root)
  local function proceed(entered)
    if not entered or vim.trim(entered) == "" then
      return
    end
    local path, row_or_err, col = M.scaffold(tmpl, entered, base_dir, root)
    if not path then
      if row_or_err == "exists" then
        local existing = resolve_name(entered, base_dir, tmpl.ext)
        ui.notify_warn("File already exists -- opening it instead", M.TITLE)
        vim.schedule(function()
          vim.cmd.edit(vim.fn.fnameescape(existing .. "/" .. vim.fn.fnamemodify(entered, ":t")))
        end)
      elseif row_or_err == "mkdir" then
        ui.notify_err("Could not create the target directory", M.TITLE)
      else
        ui.notify_err("Failed to write the new file", M.TITLE)
      end
      return
    end

    vim.cmd.edit(vim.fn.fnameescape(path))
    pcall(vim.api.nvim_win_set_cursor, 0, { math.max(row_or_err + 1, 1), col or 0 })
    ui.notify_info(("Created %s"):format(vim.fn.fnamemodify(path, ":~:.")), M.TITLE)
  end

  if tmpl.fixed_name then
    proceed(tmpl.fixed_name)
  else
    vim.ui.input({ prompt = tmpl.label .. " name: " }, proceed)
  end
end

--- Entry point: context-aware template picker.
function M.new_file()
  local base_dir = M.target_dir()
  local root = M.project_root(base_dir)
  local lang = context_language(root)

  local templates = M.all_templates()
  table.sort(templates, function(a, b)
    local a_ctx = lang ~= nil and vim.tbl_contains(a.langs or {}, lang)
    local b_ctx = lang ~= nil and vim.tbl_contains(b.langs or {}, lang)
    if a_ctx ~= b_ctx then
      return a_ctx
    end
    if a.category ~= b.category then
      return a.category < b.category
    end
    return a.label < b.label
  end)

  vim.ui.select(templates, {
    prompt = ("New file in %s"):format(vim.fn.fnamemodify(base_dir, ":~:.")),
    format_item = function(t)
      local star = (lang ~= nil and vim.tbl_contains(t.langs or {}, lang)) and "★ " or "  "
      return ("%s%-34s  %s"):format(star, t.label, t.category)
    end,
  }, function(choice)
    if choice then
      M.create(choice, base_dir, root)
    end
  end)
end

-- ---------------------------------------------------------------------------
-- New-empty-file skeleton prompt (VSCode-style "suggest an initial template")
-- ---------------------------------------------------------------------------

--- Built-in templates whose extension / language tags / fixed name match the
--- file being opened, ordered best match first (exact extension or fixed-name
--- hits before language-tag hits).
---@param ext string      extension without the dot ("" when extensionless)
---@param ft string        detected filetype ("" when none)
---@param basename string   file name without extension
---@return table[]
function M.skeletons_for(ext, ft, basename)
  local matches = {}
  for id, t in pairs(M.builtin) do
    local by_ext = t.ext ~= "" and ext ~= "" and t.ext == ext
    local by_fixed = t.fixed_name ~= nil and t.fixed_name == basename
    local by_ft = ft ~= "" and vim.tbl_contains(t.langs or {}, ft)
    if by_ext or by_fixed or by_ft then
      matches[#matches + 1] = vim.tbl_extend("keep", { id = id, _exact = (by_ext or by_fixed) and 1 or 0 }, t)
    end
  end
  table.sort(matches, function(a, b)
    if a._exact ~= b._exact then
      return a._exact > b._exact
    end
    return a.label < b.label
  end)
  return matches
end

--- Offer to fill a brand-new empty buffer with a matching template body. When
--- several templates fit, `vim.ui.select` prompts; a "(no template)" entry
--- always lets the user decline. Silent no-op when the buffer already has
--- content (e.g. an earlier BufNewFile hook filled it), the file already
--- exists on disk, or nothing in the catalogue matches the type.
---@param bufnr integer
function M.offer_skeleton(bufnr)
  if vim.g.tetravim_new_file_prompt == false then
    return
  end
  if not vim.api.nvim_buf_is_valid(bufnr) or vim.bo[bufnr].buftype ~= "" then
    return
  end

  -- Only a genuinely empty new buffer -- never clobber content another hook
  -- (e.g. the Java package/class skeleton autocmd) has already inserted.
  local lines = vim.api.nvim_buf_get_lines(bufnr, 0, -1, false)
  if #lines > 1 or (lines[1] ~= nil and lines[1] ~= "") then
    return
  end

  local path = vim.api.nvim_buf_get_name(bufnr)
  if path == "" or vim.fn.filereadable(path) == 1 then
    return
  end

  local basename = vim.fn.fnamemodify(path, ":t:r")
  local ext = vim.fn.fnamemodify(path, ":e")
  local ft = vim.bo[bufnr].filetype or ""

  local choices = M.skeletons_for(ext, ft, basename)
  if #choices == 0 then
    return
  end

  local dir = vim.fs.normalize(vim.fn.fnamemodify(path, ":p:h"))
  local root = M.project_root(dir)

  local function apply(tmpl)
    if not tmpl or not vim.api.nvim_buf_is_valid(bufnr) then
      return
    end
    local ctx = make_ctx(basename ~= "" and basename or "Untitled", dir, root)
    local content, crow, ccol = M.render(tmpl, ctx)
    vim.api.nvim_buf_set_lines(bufnr, 0, -1, false, vim.split(content, "\n", { plain = true }))
    local win = vim.fn.bufwinid(bufnr)
    if win ~= -1 then
      pcall(vim.api.nvim_win_set_cursor, win, { math.max(crow + 1, 1), ccol or 0 })
    end
  end

  local items = vim.list_extend({ { _none = true, label = "(no template)" } }, choices)
  vim.ui.select(items, {
    prompt = ("Insert a %s skeleton?"):format(ft ~= "" and ft or (ext ~= "" and ext or basename)),
    format_item = function(t)
      return t._none and "(no template)" or ("%s  ·  %s"):format(t.label, t.category)
    end,
  }, function(choice)
    if choice and not choice._none then
      apply(choice)
    end
  end)
end

--- Register the BufNewFile hook behind the skeleton prompt. Disabled in
--- headless sessions and when `vim.g.tetravim_new_file_prompt == false`.
function M.setup_new_file_prompt()
  if vim.g.tetravim_headless or vim.g.tetravim_new_file_prompt == false or #vim.api.nvim_list_uis() == 0 then
    return
  end
  local grp = vim.api.nvim_create_augroup("tetravim_filetemplate_newfile", { clear = true })
  vim.api.nvim_create_autocmd("BufNewFile", {
    group = grp,
    pattern = "*",
    callback = function(ev)
      -- Defer so filetype detection and any earlier BufNewFile hook run first.
      vim.schedule(function()
        M.offer_skeleton(ev.buf)
      end)
    end,
  })
end

--- Count of built-in templates (for :checkhealth).
---@return integer
function M.builtin_count()
  return vim.tbl_count(M.builtin)
end

return M
