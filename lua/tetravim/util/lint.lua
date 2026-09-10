-- Auto-lint toggle + dispatch helper (Story 3.x, mirrors util/format.lua)
--
-- Owns the nvim-lint dispatch that `plugins/tools-linting.lua` used to inline:
-- filetype -> linter resolution, "is this binary installed" gating, and the
-- CI-file path scoping for actionlint/yamllint. Exposing it here lets both the
-- autocmds and a manual `<leader>xlb` keymap share one code path, and lets the
-- `vim.g.autolint` / `vim.b.autolint` flags gate auto-lint without touching
-- nvim-lint's `linters_by_ft` table.
--
-- Java is linted with `checkstyle`, Kotlin with `ktlint`, Groovy with
-- `npm-groovy-lint` -- all three are in `tools-mason.lua`'s ensure_installed.

local M = {}

---@param buf? number
---@return boolean
function M.enabled(buf)
  buf = (buf == nil or buf == 0) and vim.api.nvim_get_current_buf() or buf
  local bal = vim.b[buf].autolint

  if bal ~= nil then
    return bal
  end

  return vim.g.autolint ~= false
end

---@param buf? number
function M.info(buf)
  buf = buf or vim.api.nvim_get_current_buf()
  local gal = (vim.g.autolint ~= false)
  local bal = vim.b[buf].autolint
  local enabled = M.enabled(buf)
  local lines = {
    ("global: %s"):format(gal and "enabled" or "disabled"),
    ("buffer: %s"):format(bal == nil and "inherit" or (bal and "enabled" or "disabled")),
  }
  ui.notify(
    table.concat(lines, "\n"),
    enabled and vim.log.levels.INFO or vim.log.levels.WARN,
    "Autolint (" .. (enabled and "enabled" or "disabled") .. ")"
  )
end

---@param buf boolean If true, toggle for the current buffer only; otherwise toggle globally.
function M.toggle(buf)
  local bufnr = buf and vim.api.nvim_get_current_buf() or nil
  local enable = not M.enabled(bufnr)
  if buf then
    vim.b.autolint = enable
  else
    vim.g.autolint = enable
    vim.b.autolint = nil
  end
  M.info()
end

---@return table|nil lint the "lint" module, or nil if nvim-lint is not loaded
local function get_lint()
  local ok, lint = pcall(require, "lint")
  return ok and lint or nil
end

---@param name string linter name as registered with nvim-lint
---@return boolean
local function linter_executable(name)
  local lint = get_lint()
  if not lint then
    return false
  end
  local linter_obj = lint.linters[name]
  local cmd = (linter_obj and linter_obj.cmd) or name
  if type(cmd) == "function" then
    cmd = cmd()
  end
  return type(cmd) == "string" and vim.fn.executable(cmd) == 1
end
M.linter_executable = linter_executable

--- Locate a scalastyle rules file by walking up from `dir` (or cwd). scalastyle
--- refuses to run without `-c <config>`, so a missing file means "not ready"
--- rather than a noisy per-buffer error.
---@param dir? string
---@return string|nil path
function M.scalastyle_config(dir)
  local found = vim.fs.find({ "scalastyle-config.xml", "scalastyle_config.xml" }, {
    upward = true,
    type = "file",
    path = dir or vim.fn.getcwd(),
  })
  return found[1]
end

-- Extra per-linter readiness checks on top of `linter_executable` -- the binary
-- is installed but still needs project config to do anything useful.
local extra_ready = {
  scalastyle = function()
    return M.scalastyle_config() ~= nil
  end,
}
M.extra_ready = extra_ready

-- Classify a YAML buffer by CI system from its path (Epic 39). GitHub workflow
-- and GitLab CI files are plain `yaml` to Neovim; this routes them to
-- actionlint / yamllint via `lint_ci` instead of the filetype linters.
---@param path string|nil
---@return "github"|"gitlab"|nil
function M.ci_kind(path)
  if type(path) ~= "string" then
    return nil
  end
  if path:match("[/\\]%.github[/\\]workflows[/\\][^/\\]+%.ya?ml$") then
    return "github"
  end
  if
    path:match("[/\\]%.gitlab%-ci%.yml$")
    or path:match("^%.gitlab%-ci%.yml$")
    or path:match("[/\\]%.gitlab[/\\].+%.ya?ml$")
  then
    return "gitlab"
  end
  return nil
end

-- Linters that fire on the bare `yaml` filetype but only make sense for a
-- specific kind of YAML document. `cfn-lint` treats every input as a
-- CloudFormation template ("'Resources' is a required property", "Additional
-- properties are not allowed") and `ansible-lint` as a playbook, so on an
-- `application.yaml`, a docker-compose file or any other plain YAML they are
-- pure noise. Each entry is a predicate: the linter only runs when the buffer
-- actually looks like its document type (path / filetype / header sniff, shared
-- with the `<leader>o` DevOps helpers via `core.devops`).
---@type table<string, fun(buf: number): boolean>
local generic_yaml_noise = {
  cfn_lint = function(buf)
    local ok, devops = pcall(require, "tetravim.core.devops")
    return ok and devops.is_cloudformation_buffer(buf) or false
  end,
  ansible_lint = function(buf)
    local ok, devops = pcall(require, "tetravim.core.devops")
    return ok and devops.is_ansible_buffer(buf) or false
  end,
}

--- Run the filetype-scoped linters for a buffer.
---@param buf number
---@param opts? { force?: boolean } force skips the `vim.g/b.autolint` gate
---@return boolean ran whether at least one linter was dispatched
function M.lint_buffer(buf, opts)
  opts = opts or {}
  local lint = get_lint()
  if not lint then
    return false
  end
  if not (opts.force or M.enabled(buf)) then
    return false
  end

  local ft = vim.bo[buf].filetype
  local linters = lint.linters_by_ft[ft]

  if not linters then
    lint.try_lint()
    return true
  end

  local valid = {}
  for _, linter in ipairs(linters) do
    local name = type(linter) == "table" and linter.cmd or linter
    local ready = not extra_ready[name] or extra_ready[name]()
    local doc_ok = not generic_yaml_noise[name] or generic_yaml_noise[name](buf)
    if doc_ok and linter_executable(name) and ready then
      table.insert(valid, linter)
    end
  end
  if #valid > 0 then
    lint.try_lint(valid)
    return true
  end
  return false
end

--- Run the path-scoped CI linters (actionlint / yamllint) for a buffer.
---@param buf number
---@param opts? { force?: boolean }
---@return boolean ran
function M.lint_ci(buf, opts)
  opts = opts or {}
  local lint = get_lint()
  if not lint then
    return false
  end
  if not (opts.force or M.enabled(buf)) then
    return false
  end

  local kind = M.ci_kind(vim.api.nvim_buf_get_name(buf))
  if kind == "github" and linter_executable("actionlint") then
    lint.try_lint("actionlint")
    return true
  elseif kind == "gitlab" and linter_executable("yamllint") then
    lint.try_lint("yamllint")
    return true
  end
  return false
end

--- Manual "lint now" entry point for the `<leader>xlb` keymap. Ignores the
--- autolint toggle and reports what happened via a single notification.
---@param buf? number
function M.lint_now(buf)
  buf = (buf == nil or buf == 0) and vim.api.nvim_get_current_buf() or buf
  local ui = require("tetravim.util.ui")

  if not get_lint() then
    ui.notify_err("nvim-lint is not loaded -- open a lintable buffer first")
    return
  end

  local ran = M.lint_buffer(buf, { force = true })
  local ci = M.lint_ci(buf, { force = true })
  ran = ran or ci

  local ft = vim.bo[buf].filetype
  if ran then
    ui.notify_info(("Linting %s buffer..."):format(ft ~= "" and ft or "current"))
  else
    ui.notify_warn(("No installed linter for filetype '%s'"):format(ft ~= "" and ft or "(none)"))
  end
end

-- ---------------------------------------------------------------------------
-- Buffer-scoped autofix (<leader>xlf)
-- ---------------------------------------------------------------------------
--
-- The per-language autofix argv for a SINGLE file -- the buffer-scoped twin of
-- the project `fix` rows in `M.project_tools` below. `argv[1]` is the binary
-- that must be on $PATH; the file path is appended by the builder.

---@type table<string, fun(file: string): string[]>
M.buffer_fix_argv = {
  kotlin = function(file)
    return { "ktlint", "--format", file }
  end,
  java = function(file)
    return { "google-java-format", "--replace", file }
  end,
  scala = function(file)
    return { "scalafmt", file }
  end,
  groovy = function(file)
    return { "npm-groovy-lint", "--no-insight", "--fix", file }
  end,
}

--- Autofix the current buffer's file in place with its language's own tool
--- (ktlint --format, google-java-format --replace, scalafmt, npm-groovy-lint
--- --fix). The buffer must be saved first; the rewritten file is reloaded via
--- `:checktime`. This is the buffer-scoped counterpart to `project_run("fix")`.
---@param buf? number
function M.fix_now(buf)
  buf = (buf == nil or buf == 0) and vim.api.nvim_get_current_buf() or buf
  local ui = require("tetravim.util.ui")
  local ft = vim.bo[buf].filetype
  local build = M.buffer_fix_argv[ft]

  if not build then
    ui.notify_warn(
      ("No buffer autofix tool for filetype '%s' -- <leader>xlF runs a project-wide pass"):format(
        ft ~= "" and ft or "(none)"
      )
    )
    return
  end

  local path = vim.api.nvim_buf_get_name(buf)
  if path == "" or not vim.uv.fs_stat(path) then
    ui.notify_err("Lint autofix: this buffer is not backed by a file on disk yet -- save it first")
    return
  end
  if vim.bo[buf].modified then
    ui.notify_warn("Lint autofix: save the buffer first -- the fixer rewrites the file on disk")
    return
  end

  local argv = build(path)
  if vim.fn.executable(argv[1]) ~= 1 then
    ui.notify_warn(("'%s' is not installed -- cannot autofix this %s buffer"):format(argv[1], ft))
    return
  end

  ui.notify_info(("Autofixing %s with %s..."):format(vim.fs.basename(path), argv[1]))
  vim.system(argv, { cwd = vim.fn.getcwd(), text = true }, function(res)
    vim.schedule(function()
      if res.code == 0 then
        vim.cmd("checktime")
        ui.notify_info(("%s: %s reformatted"):format(argv[1], vim.fs.basename(path)))
      else
        local out = vim.trim((res.stderr or "") .. "\n" .. (res.stdout or ""))
        ui.notify_warn(("%s exited %d%s"):format(argv[1], res.code or -1, out ~= "" and (": " .. out) or ""))
      end
    end)
  end)
end

-- ---------------------------------------------------------------------------
-- Project-wide lint check / fix (<leader>xlp / <leader>xlF)
-- ---------------------------------------------------------------------------
--
-- nvim-lint and conform are buffer-scoped; "lint the whole repo" means
-- shelling out to each tool's own project mode. This table is the single
-- source of truth -- add a row to extend it to another stack.
--
--   bin   : executable that must be on $PATH for the row to run
--   langs : human label for the report header
--   check : argv for a read-only pass (nil = no standalone checker)
--   fix   : argv for an in-place autofix pass (nil = tool has no fixer)
--   glob  : when set, the tool needs an explicit file list; we append every
--           matching file under cwd to the argv (checkstyle/g-j-f take files,
--           not a directory-recurse flag)

---@type table<string, { bin: string, langs: string, check?: string[], fix?: string[], glob?: string }>
M.project_tools = {
  ktlint = {
    bin = "ktlint",
    langs = "Kotlin",
    check = { "ktlint", "--relative" },
    fix = { "ktlint", "--relative", "--format" },
  },
  ["npm-groovy-lint"] = {
    bin = "npm-groovy-lint",
    langs = "Groovy",
    check = { "npm-groovy-lint", "--no-insight", "." },
    fix = { "npm-groovy-lint", "--no-insight", "--fix", "." },
  },
  checkstyle = {
    bin = "checkstyle",
    langs = "Java",
    check = { "checkstyle", "-c", "/google_checks.xml" },
    glob = "*.java",
    -- checkstyle has no autofix; google-java-format below is the fixer
  },
  ["google-java-format"] = {
    bin = "google-java-format",
    langs = "Java",
    fix = { "google-java-format", "--replace" },
    glob = "*.java",
  },
  scalafmt = {
    bin = "scalafmt",
    langs = "Scala",
    check = { "scalafmt", "--test" },
    fix = { "scalafmt" },
  },
}

--- Drop `text` into a reused persistent split via the shared renderer
--- (util/split.lua): an unlisted nofile scratch buffer, never a float.
---@param text string
---@param name_hint string
local function open_in_split(text, name_hint)
  require("tetravim.util.split").open(text, { filetype = "log", name_hint = name_hint })
end

--- List the project tools that can run for `mode` right now.
---@param mode "check"|"fix"
---@return { name: string, spec: table }[]
function M.project_plan(mode)
  local plan = {}
  for name, spec in pairs(M.project_tools) do
    if spec[mode] and vim.fn.executable(spec.bin) == 1 then
      table.insert(plan, { name = name, spec = spec })
    end
  end
  table.sort(plan, function(a, b)
    return a.name < b.name
  end)
  return plan
end

--- Run every applicable project tool for `mode` and render a combined report
--- in a persistent split. On "fix" the changed files are reloaded (`:checktime`).
---@param mode "check"|"fix"
function M.project_run(mode)
  local ui = require("tetravim.util.ui")
  local cwd = vim.fn.getcwd()
  local plan = M.project_plan(mode)

  if #plan == 0 then
    ui.notify_warn(
      ("No project lint-%s tool installed (ktlint, npm-groovy-lint, checkstyle, google-java-format, scalafmt)"):format(
        mode
      )
    )
    return
  end

  local lines = {
    ("# TetraVim lint %s -- %s"):format(mode, os.date("%Y-%m-%d %H:%M:%S")),
    ("# cwd: %s"):format(cwd),
    "",
  }
  local pending = #plan

  local function finish()
    open_in_split(table.concat(lines, "\n"), "tetravim-lint")
    if mode == "fix" then
      -- pull rewritten files back into their buffers
      vim.cmd("checktime")
    end
    ui.notify_info(("Project lint %s finished (%d tool(s))"):format(mode, #plan))
  end

  for _, job in ipairs(plan) do
    local argv = vim.deepcopy(job.spec[mode])

    if job.spec.glob then
      local files = vim.fn.globpath(cwd, "**/" .. job.spec.glob, false, true)
      -- skip common build-output trees so we lint sources, not generated code
      files = vim.tbl_filter(function(f)
        return not f:match("[/\\][%.]?build[/\\]") and not f:match("[/\\]target[/\\]") and not f:match("[/\\]out[/\\]")
      end, files)
      if #files == 0 then
        table.insert(lines, ("== %s (%s) -- no matching files =="):format(job.name, job.spec.langs))
        table.insert(lines, "")
        pending = pending - 1
        if pending == 0 then
          finish()
        end
        goto continue
      end
      vim.list_extend(argv, files)
    end

    vim.system(argv, { cwd = cwd, text = true }, function(res)
      vim.schedule(function()
        table.insert(lines, ("== %s (%s) -- exit %d =="):format(job.name, job.spec.langs, res.code or -1))
        local out = vim.trim((res.stdout or "") .. "\n" .. (res.stderr or ""))
        if out == "" then
          table.insert(lines, mode == "fix" and "(no changes / no output)" or "(clean)")
        else
          for l in vim.gsplit(out, "\n", { plain = true }) do
            table.insert(lines, l)
          end
        end
        table.insert(lines, "")
        pending = pending - 1
        if pending == 0 then
          finish()
        end
      end)
    end)

    ::continue::
  end

  ui.notify_info(("Running %d project lint %s tool(s)..."):format(#plan, mode))
end

return M
