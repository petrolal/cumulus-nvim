-- TetraVim Healthcheck -- CloudFormation/SAM, Ansible, CI/CD YAML
-- Carved out of the former monolithic lua/tetravim/health.lua
-- (Story 27.2 / Story 35.1 / Story 6.1). Orchestrated by health/init.lua;
-- sections run in the original order so :checkhealth output is unchanged.

local M = {}

function M.check()
  vim.health.start("AWS CloudFormation & SAM DevOps Tooling")

  local cfn_tools = {
    {
      name = "aws",
      desc = "AWS CLI (required for 'aws cloudformation validate-template')",
      install = "Install via https://aws.amazon.com/cli/",
    },
    {
      name = "sam",
      desc = "AWS SAM CLI (required for 'sam build', 'sam local invoke', 'sam validate')",
      install = "Install via https://docs.aws.amazon.com/serverless-application-model/latest/developerguide/install-sam-cli.html",
    },
    {
      name = "cfn-lint",
      desc = "CloudFormation Linter (cfn-lint)",
      install = ":MasonInstall cfn-lint or pip install cfn-lint",
    },
    {
      name = "cfn-guard",
      desc = "CloudFormation Guard Policy Evaluator (cfn-guard)",
      install = "Install via brew install cloudformation-guard or cargo install cfn-guard",
    },
  }

  for _, tool in ipairs(cfn_tools) do
    if vim.fn.executable(tool.name) == 1 then
      vim.health.ok(string.format("%s: installed and executable", tool.name))
    else
      vim.health.info(string.format("%s: NOT found on $PATH (%s. Suggestion: %s)", tool.name, tool.desc, tool.install))
    end
  end

  vim.health.start("Ansible Automation Tooling")

  local ansible_tools = {
    {
      name = "ansible-playbook",
      desc = "Ansible Playbook CLI (required for '--syntax-check', '--check', execution)",
      install = "Install via pip install ansible or brew install ansible",
    },
    {
      name = "ansible-lint",
      desc = "Ansible Playbook Linter",
      install = ":MasonInstall ansible-lint or pip install ansible-lint",
    },
    {
      name = "ansible-inventory",
      desc = "Ansible Inventory CLI (required for '--graph')",
      install = "Included with ansible package (pip install ansible)",
    },
    {
      name = "ansible-vault",
      desc = "Ansible Vault CLI (encrypt/decrypt/view secrets)",
      install = "Included with ansible package (pip install ansible)",
    },
    {
      name = "ansible-doc",
      desc = "Ansible Module Documentation Browser",
      install = "Included with ansible package (pip install ansible)",
    },
  }

  for _, tool in ipairs(ansible_tools) do
    if vim.fn.executable(tool.name) == 1 then
      vim.health.ok(string.format("%s: installed and executable", tool.name))
    else
      vim.health.info(string.format("%s: NOT found on $PATH (%s. Suggestion: %s)", tool.name, tool.desc, tool.install))
    end
  end

  vim.health.start("TetraVim CI/CD YAML -- GitHub Actions & GitLab CI")

  if pcall(require, "schemastore") then
    vim.health.ok("SchemaStore.nvim: resolvable (JSON Schema Store catalog feeds yamlls/jsonls)")
  else
    vim.health.warn(
      "SchemaStore.nvim: NOT resolvable -- run :Lazy sync (GitHub Workflow / GitLab CI schema validation unavailable)"
    )
  end

  local ci_tools = {
    {
      name = "yaml-language-server",
      desc = "YAML LSP -- schema validation, completion and hover for workflow & pipeline files",
      install = ":MasonInstall yaml-language-server",
    },
    {
      name = "gh-actions-language-server",
      desc = "GitHub Actions LSP -- 'uses:' resolution, expression and input checks",
      install = ":MasonInstall gh-actions-language-server",
    },
    {
      name = "actionlint",
      desc = "GitHub Actions workflow linter (shellcheck-backed 'run:' analysis)",
      install = ":MasonInstall actionlint",
    },
    {
      name = "yamllint",
      desc = "Generic YAML linter -- style checks for .gitlab-ci.yml",
      install = ":MasonInstall yamllint",
    },
  }

  for _, tool in ipairs(ci_tools) do
    if vim.fn.executable(tool.name) == 1 then
      vim.health.ok(string.format("%s: installed and executable", tool.name))
    else
      vim.health.info(string.format("%s: NOT found on $PATH (%s. Suggestion: %s)", tool.name, tool.desc, tool.install))
    end
  end

  if vim.fn.executable("glab") == 1 then
    vim.health.ok("glab: installed (optional -- 'glab ci lint' server-side pipeline validation)")
  else
    vim.health.info("glab: NOT found on $PATH (optional -- enables server-side 'glab ci lint' validation)")
  end
end

return M
