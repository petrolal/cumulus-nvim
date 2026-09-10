-- TetraVim Diagnostic Linting Specs (Story 3.1, 3.2, 3.3, 40.1)
--
-- The filetype -> linter map lives here; the dispatch logic (executable
-- gating, CI-file path scoping) and the `vim.g.autolint` / `vim.b.autolint`
-- toggle live in `tetravim.util.edit.lint`, shared with the `<leader>xlb` manual
-- "lint now" keymap and the `<leader>ul` / `<leader>uL` toggles.

return {
  {
    "mfussenegger/nvim-lint",
    event = { "BufReadPre", "BufNewFile" },
    config = function()
      local lint = require("lint")
      lint.linters_by_ft = {
        terraform = { "tflint" },
        tf = { "tflint" },
        hcl = { "tflint" },
        ["terraform-vars"] = { "tflint" },
        yaml = { "cfn_lint", "ansible_lint" },
        ["yaml.ansible"] = { "ansible_lint" },
        ansible = { "ansible_lint" },
        ["yaml.cfn"] = { "cfn_lint" },
        ["yaml.sam"] = { "cfn_lint" },
        cloudformation = { "cfn_lint" },
        sam = { "cfn_lint" },
        dockerfile = { "hadolint" },
        kotlin = { "ktlint" },
        groovy = { "npm-groovy-lint" },
        java = { "checkstyle" },
        scala = { "scalastyle" },
        sbt = { "scalastyle" },
        -- IntelliJ IDEA Ultimate parity (see docs/ide-parity.md)
        python = { "ruff" },
        htmldjango = { "djlint" },
      }

      -- nvim-lint ships no scalastyle linter. Define one here: SARIF isn't an
      -- option, so parse the plain text reporter. scalastyle refuses to run
      -- without `-c <rules.xml>`, so `tetravim.util.edit.lint.extra_ready` skips it
      -- until a scalastyle-config.xml is found up-tree (see that module).
      lint.linters.scalastyle = {
        cmd = "scalastyle",
        stdin = false,
        ignore_exitcode = true,
        args = function()
          local cfg = require("tetravim.util.edit.lint").scalastyle_config()
          return cfg and { "-c", cfg } or {}
        end,
        parser = function(output)
          local diagnostics = {}
          for line in vim.gsplit(output or "", "\n", { plain = true }) do
            local level = line:match("^(%a+)%s+file=")
            if level then
              local msg = line:match("message=(.-)%s+line=") or line:match("message=(.+)$") or line
              local lnum = tonumber(line:match("line=(%d+)"))
              local col = tonumber(line:match("column=(%d+)"))
              local sev = vim.diagnostic.severity.INFO
              if level == "error" then
                sev = vim.diagnostic.severity.ERROR
              elseif level == "warning" then
                sev = vim.diagnostic.severity.WARN
              end
              table.insert(diagnostics, {
                lnum = math.max((lnum or 1) - 1, 0),
                col = math.max((col or 1) - 1, 0),
                end_lnum = math.max((lnum or 1) - 1, 0),
                end_col = math.max((col or 1) - 1, 0),
                message = vim.trim(msg),
                severity = sev,
                source = "scalastyle",
              })
            end
          end
          return diagnostics
        end,
      }

      local tvlint = require("tetravim.util.edit.lint")

      -- The JVM linters (checkstyle / ktlint / scalastyle / npm-groovy-lint)
      -- each spin up a JVM or Node process -- cheap enough on save, but too
      -- heavy to fire on every `InsertLeave`. Mirrors the CodeLens-refresh
      -- throttle in core/autocmds.lua: for these filetypes lint on
      -- enter / write only, not on leaving insert mode.
      local heavy_ft = { java = true, kotlin = true, groovy = true, scala = true, sbt = true }

      local lint_augroup = vim.api.nvim_create_augroup("tetravim_lint", { clear = true })
      vim.api.nvim_create_autocmd({ "BufEnter", "BufWritePost", "InsertLeave" }, {
        group = lint_augroup,
        callback = function(args)
          if args.event == "InsertLeave" and heavy_ft[vim.bo[args.buf].filetype] then
            return
          end
          -- honours vim.g.autolint / vim.b.autolint
          tvlint.lint_buffer(args.buf)
        end,
      })

      -- CI/CD YAML linters are path-scoped, not filetype-scoped (Epic 39):
      -- `actionlint` only understands GitHub workflow files and errors loudly
      -- on any other YAML, and `yamllint` is our generic fallback aimed at
      -- GitLab CI. Both run only when the buffer path matches.
      local ci_augroup = vim.api.nvim_create_augroup("tetravim_lint_ci", { clear = true })
      vim.api.nvim_create_autocmd({ "BufReadPost", "BufWritePost" }, {
        group = ci_augroup,
        pattern = { "*.yml", "*.yaml" },
        callback = function(args)
          tvlint.lint_ci(args.buf)
        end,
      })

      -- Discoverable command aliases for the <leader>x* keymaps.
      vim.api.nvim_create_user_command("TetraLint", function()
        tvlint.lint_now()
      end, { desc = "Lint the current buffer now" })
      vim.api.nvim_create_user_command("TetraLintFix", function()
        tvlint.fix_now()
      end, { desc = "Auto-fix the current buffer's file in place" })
      vim.api.nvim_create_user_command("TetraLintAll", function()
        tvlint.project_run("check")
      end, { desc = "Lint-check every supported file in the project" })
      vim.api.nvim_create_user_command("TetraLintFixAll", function()
        tvlint.project_run("fix")
      end, { desc = "Auto-fix lint issues across the whole project" })
    end,
  },
}
