local M = {}
local ui = require("tetravim.util.ui")
local git = require("tetravim.util.git")

local active_sessions = {} -- Map of repo_root -> { number, cli, ref, base }

local function get_session()
  local root = git.repo_root()
  return root, active_sessions[root]
end

local function detect_forge(root)
  if not root then
    return nil
  end
  local ok, res = pcall(function()
    return vim.system({ "git", "-C", root, "remote", "-v" }, { text = true }):wait()
  end)
  if not ok or res.code ~= 0 then
    return nil
  end
  local stdout = res.stdout or ""

  local has_github = stdout:find("github%.com") or stdout:find("github")
  local has_gitlab = stdout:find("gitlab%.com") or stdout:find("gitlab")

  if has_gitlab and vim.fn.executable("glab") == 1 then
    return "glab"
  end
  if has_github and vim.fn.executable("gh") == 1 then
    return "gh"
  end

  if vim.fn.executable("gh") == 1 then
    return "gh"
  end
  if vim.fn.executable("glab") == 1 then
    return "glab"
  end
  return nil
end

local function select_pr(callback)
  local root = git.repo_root()
  local cli = detect_forge(root)
  if not cli then
    ui.notify_err("No `gh` or `glab` CLI installed, or not a GitHub/GitLab remote.")
    return
  end

  local cmd = {}
  if cli == "gh" then
    cmd = {
      "gh",
      "pr",
      "list",
      "--json",
      "number,title,headRefName,baseRefName",
      "--jq",
      '.[] | "#\\(.number) \\(.title)\\t\\(.headRefName)\\t\\(.baseRefName)"',
    }
  else
    cmd = { "glab", "mr", "list", "-F", "json" }
  end

  vim.system(
    cmd,
    { text = true, cwd = root },
    vim.schedule_wrap(function(res)
      if res.code ~= 0 then
        ui.notify_err("Failed to list PRs: " .. (res.stderr or "unknown error"))
        return
      end

      local items = {}
      if cli == "gh" then
        for line in (res.stdout or ""):gmatch("[^\r\n]+") do
          local num, title, ref, base = line:match("^(#%d+)%s+(.+)\t(.+)\t(.+)$")
          if num then
            table.insert(items, { text = num .. " " .. title, number = num:sub(2), ref = ref, base = base })
          end
        end
      elseif cli == "glab" then
        local ok, parsed = pcall(vim.json.decode, res.stdout or "[]")
        if ok and type(parsed) == "table" then
          for _, mr in ipairs(parsed) do
            table.insert(items, {
              text = "!" .. mr.iid .. " " .. mr.title,
              number = tostring(mr.iid),
              ref = mr.source_branch,
              base = mr.target_branch,
            })
          end
        end
      end

      if #items == 0 then
        ui.notify_err("No open PRs found.")
        return
      end

      require("snacks").picker.select(items, {
        prompt = "Select PR",
        format_item = function(item)
          return item.text
        end,
      }, function(selected)
        if selected then
          active_sessions[root] = { number = selected.number, cli = cli, ref = selected.ref, base = selected.base }
          callback(selected, cli, root)
        end
      end)
    end)
  )
end

function M.list_and_review_prs()
  if not git.guard() then
    return
  end
  select_pr(function(pr, cli, root)
    if not pr.base or pr.base == "" or not pr.ref or pr.ref == "" then
      ui.notify_err("PR is missing branch metadata (base or ref) — cannot open review.")
      return
    end
    ui.notify_info("Fetching PR " .. pr.number .. " branches...")

    vim.system(
      { "git", "fetch", "origin", pr.base, pr.ref },
      { text = true, cwd = root },
      vim.schedule_wrap(function(fetch_res)
        local base_target = pr.base
        local head_target = pr.ref
        if fetch_res.code == 0 then
          base_target = "origin/" .. pr.base
          head_target = "origin/" .. pr.ref
        end

        local diff_cmd = "DiffviewOpen " .. base_target .. "..." .. head_target
        local ok, err = pcall(function()
          vim.cmd(diff_cmd)
        end)
        if not ok then
          ui.notify_err("Failed to open Diffview: " .. tostring(err))
        end

        local cmd = cli == "gh" and { "gh", "pr", "view", pr.number, "--comments" }
          or { "glab", "mr", "view", pr.number, "--comments" }
        vim.system(
          cmd,
          { text = true, env = { NO_COLOR = "1" }, cwd = root },
          vim.schedule_wrap(function(res)
            if res.code == 0 then
              vim.cmd("botright vnew")
              vim.bo.buftype = "nofile"
              vim.bo.swapfile = false
              vim.bo.bufhidden = "wipe"
              vim.bo.filetype = "markdown"
              vim.api.nvim_buf_set_lines(0, 0, -1, false, vim.split(res.stdout or "", "\n"))
              vim.bo.modifiable = false
            end
          end)
        )
      end)
    )
  end)
end

function M.checkout_pr()
  if not git.guard() then
    return
  end
  select_pr(function(pr, cli, root)
    local cmd = cli == "gh" and { "gh", "pr", "checkout", pr.number } or { "glab", "mr", "checkout", pr.number }
    vim.system(
      cmd,
      { text = true, cwd = root },
      vim.schedule_wrap(function(res)
        if res.code == 0 then
          pcall(function()
            ui.notify_info("Checked out PR " .. pr.number)
          end)
        else
          ui.notify_err("Checkout failed: " .. (res.stderr or ""))
        end
      end)
    )
  end)
end

function M.add_comment()
  if not git.guard() then
    return
  end
  local root, session = get_session()
  if not session or not session.number or not session.cli then
    ui.notify_err("No active PR. Run PR list first.")
    return
  end

  vim.cmd("botright 10new")
  local buf = vim.api.nvim_get_current_buf()
  vim.bo[buf].buftype = "acwrite"
  vim.bo[buf].bufhidden = "wipe"
  local buf_name = "PR_COMMENT_" .. session.number
  local ok_name = pcall(vim.api.nvim_buf_set_name, buf, buf_name)
  if not ok_name then
    -- Another buffer with the same name exists (previous comment still open);
    -- append the buffer number to disambiguate.
    pcall(vim.api.nvim_buf_set_name, buf, buf_name .. "_" .. buf)
  end

  local header = "<!-- Enter comment. Save (:w) to submit. -->"
  vim.api.nvim_buf_set_lines(buf, 0, -1, false, { header, "" })
  vim.api.nvim_win_set_cursor(0, { 2, 0 })

  vim.api.nvim_create_autocmd("BufWriteCmd", {
    buffer = buf,
    callback = function()
      local lines = vim.api.nvim_buf_get_lines(buf, 0, -1, false)
      local content = {}
      for _, l in ipairs(lines) do
        if l ~= header then
          table.insert(content, l)
        end
      end
      local body = vim.trim(table.concat(content, "\n"))
      if body == "" then
        ui.notify_err("Empty comment.")
        pcall(vim.api.nvim_buf_delete, buf, { force = true })
        return
      end

      local cmd = session.cli == "gh" and { "gh", "pr", "comment", session.number, "--body", body }
        or { "glab", "mr", "note", session.number, "-m", body }
      vim.system(
        cmd,
        { text = true, cwd = root },
        vim.schedule_wrap(function(res)
          if res.code == 0 then
            pcall(function()
              ui.notify_info("Comment added to PR " .. session.number)
            end)
            -- Clear modified flag only after a confirmed successful submit,
            -- so the user isn't left with a dirty buffer they can't close.
            vim.bo[buf].modified = false
            pcall(vim.api.nvim_buf_delete, buf, { force = true })
          else
            ui.notify_err("Comment failed: " .. (res.stderr or ""))
            vim.bo[buf].modified = true
          end
        end)
      )
    end,
  })
end

return M
