-- TetraVim DevOps & Infrastructure Tooling Suite
--
-- Interactive and non-blocking compilers, linters, and runners for
-- Terraform/OpenTofu, AWS CloudFormation/SAM, Ansible, Docker, and Helm.
-- Project roots are discovered natively by walking upward for marker files.

local M = {}

local term = require("tetravim.util.term")

-- =============================================================================
-- Native Root Discovery (vim.fs upward marker search)
-- =============================================================================

--- Resolve the search directory from buffer number or path
--- @param buf_or_path? number|string
--- @return string|nil
local function resolve_search_dir(buf_or_path)
  if type(buf_or_path) == "number" then
    if vim.api.nvim_buf_is_valid(buf_or_path) then
      local path = vim.api.nvim_buf_get_name(buf_or_path)
      if path ~= "" then
        return vim.fs.normalize(vim.fn.fnamemodify(path, ":h"))
      end
    end
    return vim.fn.getcwd()
  elseif type(buf_or_path) == "string" and buf_or_path ~= "" then
    return vim.fs.normalize(buf_or_path)
  end
  return vim.fn.getcwd()
end

-- Marker files (or a name predicate) that identify each tool's project root.
local ROOT_MARKERS = {
  terraform = function(name)
    return name:match("%.tf$") ~= nil or name:match("%.tofu$") ~= nil or name == ".terraform"
  end,
  sam = { "template.yaml", "template.yml", "samconfig.toml" },
  ansible = { "ansible.cfg", "playbook.yml", "playbook.yaml", "site.yml" },
  docker = { "Dockerfile", "compose.yaml", "docker-compose.yml" },
  helm = { "Chart.yaml" },
}

-- How deep the downward fallback scan is allowed to recurse below the search
-- directory. Keeps monorepo scans bounded while still catching the common
-- `infra/terraform`, `charts/<name>` layouts.
local DOWNWARD_MAX_DEPTH = 4

--- Breadth-first downward search for the shallowest directory containing a marker.
--- Used when the buffer sits at a workspace root and the config lives in a
--- conventional subdirectory rather than upward on the path.
--- @param markers string[]|fun(name: string): boolean
--- @param dir string
--- @return string|nil
local function find_downward(markers, dir)
  local match = markers
  if type(markers) == "table" then
    local set = {}
    for _, name in ipairs(markers) do
      set[name] = true
    end
    match = function(name)
      return set[name] == true
    end
  end
  local found = vim.fs.find(function(name, path)
    if not match(name) then
      return false
    end
    local rel = path:sub(#dir + 1)
    return select(2, rel:gsub("/", "/")) <= DOWNWARD_MAX_DEPTH
  end, {
    path = dir,
    limit = 1,
    type = "file",
  })[1]
  return found and vim.fs.dirname(found) or nil
end

--- Build a finder that walks upward from a buffer/path for a tool's markers,
--- falling back to a bounded downward scan when invoked from a workspace root.
--- @param root_key string One of terraform, sam, ansible, docker, helm
--- @return fun(buf_or_path?: number|string): string|nil
local function create_root_finder(root_key)
  local markers = ROOT_MARKERS[root_key]
  return function(buf_or_path)
    local search_dir = resolve_search_dir(buf_or_path)
    if not search_dir or search_dir == "" then
      return nil
    end
    local found = vim.fs.find(markers, {
      upward = true,
      path = search_dir,
      stop = vim.uv.os_homedir(),
    })[1]
    if found then
      return vim.fs.dirname(found)
    end
    return find_downward(markers, search_dir)
  end
end

M.find_tf_root = create_root_finder("terraform")
M.find_cfn_root = create_root_finder("sam")
M.find_ansible_root = create_root_finder("ansible")
M.find_docker_root = create_root_finder("docker")
M.find_helm_root = create_root_finder("helm")

--- Run a command in an interactive, non-blocking terminal.
function M.run_term(cmd, opts)
  opts = vim.tbl_extend("force", { title = "TetraVim DevOps" }, opts or {})
  term.run_term(cmd, opts)
end

-- =============================================================================
-- Helper Guards for Global Root Execution & Missing Workspace Diagnostics
-- =============================================================================

local function with_root(finder, missing_msg, callback)
  local root = finder()
  if not root then
    vim.notify(missing_msg, vim.log.levels.WARN, { title = "TetraVim DevOps" })
    return
  end
  local ok, err = pcall(callback, root)
  if not ok then
    vim.notify("Error executing operation: " .. err, vim.log.levels.ERROR, { title = "TetraVim DevOps" })
  end
end

-- =============================================================================
-- Terraform & OpenTofu
-- =============================================================================

function M.get_tf_cmd()
  if vim.fn.executable("tofu") == 1 then
    return "tofu"
  elseif vim.fn.executable("terraform") == 1 then
    return "terraform"
  end
  return nil
end

local function with_tf(callback)
  local tf = M.get_tf_cmd()
  if not tf then
    vim.notify(
      "Neither 'tofu' nor 'terraform' was found in your PATH. Please install OpenTofu or Terraform.",
      vim.log.levels.WARN,
      { title = "TetraVim DevOps" }
    )
    return
  end
  with_root(M.find_tf_root, "No Terraform/OpenTofu configuration found in workspace", function(root)
    callback(tf, root)
  end)
end

function M.terraform_init()
  with_tf(function(tf, root)
    M.run_term(tf .. " init", { cwd = root })
  end)
end

function M.terraform_validate()
  with_tf(function(tf, root)
    M.run_term(tf .. " validate", { cwd = root })
  end)
end

function M.terraform_plan()
  with_tf(function(tf, root)
    M.run_term(tf .. " plan", { cwd = root })
  end)
end

function M.terraform_apply()
  with_tf(function(tf, root)
    M.run_term(tf .. " apply", { cwd = root })
  end)
end

function M.terraform_fmt()
  with_tf(function(tf, root)
    local file = vim.fn.expand("%:p")
    local is_tf_file = file ~= "" and (file:match("%.tf$") or file:match("%.tofu$") or file:match("%.tfvars$"))
    if is_tf_file and vim.fn.filereadable(file) == 1 then
      local ok_save, err_save = pcall(vim.cmd, "update")
      if not ok_save then
        vim.notify("Failed to save file: " .. err_save, vim.log.levels.ERROR, { title = "TetraVim DevOps" })
        return
      end
      -- Async (canonical vim.system + vim.schedule pattern): a slow disk /
      -- NFS mount must never stall the UI thread. The buffer is reloaded
      -- ONLY on success -- `edit!` on a failed `fmt` would discard buffer
      -- state for nothing.
      vim.system({ tf, "fmt", file }, { text = true, timeout = 15000 }, function(out)
        vim.schedule(function()
          local timed_out = out.code == 124 and out.signal ~= 0
          if out.code == 0 then
            local ok_reload, err_reload = pcall(vim.cmd, "edit!")
            if not ok_reload then
              vim.notify(
                "Formatted, but failed to reload buffer: " .. tostring(err_reload),
                vim.log.levels.WARN,
                { title = "TetraVim DevOps" }
              )
            else
              vim.notify("Formatted with " .. tf .. " fmt", vim.log.levels.INFO, { title = "TetraVim DevOps" })
            end
          elseif timed_out then
            vim.notify(tf .. " fmt timed out after 15s", vim.log.levels.ERROR, { title = "TetraVim DevOps" })
          else
            local msg = (out.stderr and out.stderr ~= "" and out.stderr) or out.stdout or "unknown error"
            vim.notify("Formatting error: " .. vim.trim(msg), vim.log.levels.ERROR, { title = "TetraVim DevOps" })
          end
        end)
      end)
    else
      if not is_tf_file then
        vim.notify(
          "Current file is not a Terraform (.tf, .tofu, .tfvars) file.",
          vim.log.levels.WARN,
          { title = "TetraVim DevOps" }
        )
      elseif vim.fn.filereadable(file) ~= 1 then
        vim.notify("Cannot read file: " .. file, vim.log.levels.WARN, { title = "TetraVim DevOps" })
      end
      M.run_term(tf .. " fmt", { cwd = root })
    end
  end)
end

function M.terraform_lint()
  with_root(M.find_tf_root, "No Terraform/OpenTofu configuration found in workspace", function(root)
    if vim.fn.executable("tflint") == 1 then
      M.run_term("tflint", { cwd = root })
    else
      vim.notify(
        "tflint is not installed in PATH. Install via Mason (:MasonInstall tflint).",
        vim.log.levels.WARN,
        { title = "TetraVim DevOps" }
      )
    end
  end)
end

function M.terraform_security()
  with_root(M.find_tf_root, "No Terraform/OpenTofu configuration found in workspace", function(root)
    if vim.fn.executable("trivy") == 1 then
      M.run_term("trivy config .", { cwd = root })
    elseif vim.fn.executable("tfsec") == 1 then
      M.run_term("tfsec .", { cwd = root })
    else
      vim.notify(
        "Neither 'trivy' nor 'tfsec' is installed in PATH.",
        vim.log.levels.WARN,
        { title = "TetraVim DevOps" }
      )
    end
  end)
end

function M.terraform_output()
  with_tf(function(tf, root)
    M.run_term(tf .. " output", { cwd = root })
  end)
end

-- =============================================================================
-- AWS CloudFormation & SAM
-- =============================================================================

--- Check if current buffer is likely a CloudFormation / SAM template
function M.is_cloudformation_buffer(buf)
  buf = buf or vim.api.nvim_get_current_buf()
  if not vim.api.nvim_buf_is_valid(buf) then
    return false
  end
  local ft = vim.bo[buf].filetype
  if ft == "yaml.cfn" or ft == "yaml.sam" or ft == "cloudformation" or ft == "sam" then
    return true
  end
  if ft == "yaml" or ft == "json" then
    local lines = vim.api.nvim_buf_get_lines(buf, 0, 30, false)
    local header = table.concat(lines, "\n")
    if
      header:match("AWSTemplateFormatVersion")
      or header:match("AWS::Serverless")
      or header:match("Transform:%s*AWS::Serverless")
    then
      return true
    end
  end
  return false
end

local function with_cfn(callback)
  with_root(M.find_cfn_root, "No CloudFormation/SAM configuration found in workspace", callback)
end

local function resolve_cfn_target_file(root)
  local file = vim.fn.expand("%:p")
  if file ~= "" and M.is_cloudformation_buffer() then
    return file
  end
  if root then
    if vim.fn.filereadable(root .. "/template.yaml") == 1 then
      return root .. "/template.yaml"
    elseif vim.fn.filereadable(root .. "/template.yml") == 1 then
      return root .. "/template.yml"
    elseif vim.fn.filereadable(root .. "/template.json") == 1 then
      return root .. "/template.json"
    end
  end
  return nil
end

function M.cfn_validate()
  with_cfn(function(root)
    local file = resolve_cfn_target_file(root)
    if not file then
      vim.notify(
        "No CloudFormation/SAM template file found to validate.",
        vim.log.levels.WARN,
        { title = "TetraVim DevOps" }
      )
      return
    end
    local cwd = root or vim.fs.normalize(vim.fn.fnamemodify(file, ":h"))
    if vim.fn.executable("aws") == 1 then
      M.run_term(
        "aws cloudformation validate-template --template-body " .. vim.fn.shellescape("file://" .. file),
        { cwd = cwd }
      )
    elseif vim.fn.executable("cfn-lint") == 1 then
      M.run_term("cfn-lint " .. vim.fn.shellescape(file), { cwd = cwd })
    else
      vim.notify(
        "Neither 'aws' CLI nor 'cfn-lint' was found in PATH. Please install the AWS CLI or cfn-lint (:MasonInstall cfn-lint).",
        vim.log.levels.WARN,
        { title = "TetraVim DevOps" }
      )
    end
  end)
end

function M.cfn_lint()
  with_cfn(function(root)
    local file = resolve_cfn_target_file(root)
    if vim.fn.executable("cfn-lint") == 1 then
      if file and file ~= "" then
        M.run_term("cfn-lint " .. vim.fn.shellescape(file), { cwd = root })
      else
        M.run_term("cfn-lint", { cwd = root })
      end
    else
      vim.notify(
        "cfn-lint is not installed in PATH. Install via Mason (:MasonInstall cfn-lint) or pip ('pip install cfn-lint').",
        vim.log.levels.WARN,
        { title = "TetraVim DevOps" }
      )
    end
  end)
end

function M.sam_validate()
  with_cfn(function(root)
    if vim.fn.executable("sam") == 1 then
      M.run_term("sam validate", { cwd = root })
    else
      vim.notify(
        "AWS SAM CLI ('sam') is not installed in PATH. Visit https://docs.aws.amazon.com/serverless-application-model/latest/developerguide/install-sam-cli.html",
        vim.log.levels.WARN,
        { title = "TetraVim DevOps" }
      )
    end
  end)
end

function M.sam_build()
  with_cfn(function(root)
    if vim.fn.executable("sam") == 1 then
      M.run_term("sam build", { cwd = root })
    else
      vim.notify(
        "AWS SAM CLI ('sam') is not installed in PATH. Visit https://docs.aws.amazon.com/serverless-application-model/latest/developerguide/install-sam-cli.html",
        vim.log.levels.WARN,
        { title = "TetraVim DevOps" }
      )
    end
  end)
end

function M.sam_local_invoke()
  with_cfn(function(root)
    if vim.fn.executable("sam") ~= 1 then
      vim.notify(
        "AWS SAM CLI ('sam') is not installed in PATH. Visit https://docs.aws.amazon.com/serverless-application-model/latest/developerguide/install-sam-cli.html",
        vim.log.levels.WARN,
        { title = "TetraVim DevOps" }
      )
      return
    end

    local file = resolve_cfn_target_file(root) or ""
    local functions = {}

    local tmpl_flag = (file ~= "") and (" -t " .. vim.fn.shellescape(file)) or ""

    if #functions > 1 then
      vim.ui.select(functions, { prompt = "Select Lambda Function to Invoke:" }, function(choice)
        if choice and choice ~= "" then
          M.run_term("sam local invoke " .. vim.fn.shellescape(choice) .. tmpl_flag, { cwd = root })
        end
      end)
    elseif #functions == 1 then
      M.run_term("sam local invoke " .. vim.fn.shellescape(functions[1]) .. tmpl_flag, { cwd = root })
    else
      vim.ui.input({ prompt = "Lambda Function Logical ID (optional, Esc to cancel): " }, function(input)
        if input == nil then
          return
        elseif input ~= "" then
          if not input:match("^[a-zA-Z0-9_-]+$") then
            vim.notify(
              "Invalid Lambda function name. Only alphanumeric, underscore, and hyphen allowed.",
              vim.log.levels.WARN,
              { title = "TetraVim DevOps" }
            )
            return
          end
          M.run_term("sam local invoke " .. vim.fn.shellescape(input) .. tmpl_flag, { cwd = root })
        else
          M.run_term("sam local invoke" .. tmpl_flag, { cwd = root })
        end
      end)
    end
  end)
end

function M.sam_local_start_api()
  with_cfn(function(root)
    if vim.fn.executable("sam") == 1 then
      M.run_term("sam local start-api", { cwd = root })
    else
      vim.notify(
        "AWS SAM CLI ('sam') is not installed in PATH. Visit https://docs.aws.amazon.com/serverless-application-model/latest/developerguide/install-sam-cli.html",
        vim.log.levels.WARN,
        { title = "TetraVim DevOps" }
      )
    end
  end)
end

function M.cfn_guard_validate()
  with_cfn(function(root)
    if vim.fn.executable("cfn-guard") == 1 then
      local file = resolve_cfn_target_file(root) or (vim.fn.expand("%:p") ~= "" and vim.fn.expand("%:p") or nil)
      if not file then
        vim.notify(
          "No CloudFormation template found to validate with cfn-guard.",
          vim.log.levels.WARN,
          { title = "TetraVim DevOps" }
        )
        return
      end
      M.run_term("cfn-guard validate --template " .. vim.fn.shellescape(file), { cwd = root })
    else
      vim.notify(
        "cfn-guard is not installed in PATH. Install CloudFormation Guard via cargo or homebrew ('brew install cloudformation-guard').",
        vim.log.levels.WARN,
        { title = "TetraVim DevOps" }
      )
    end
  end)
end

-- =============================================================================
-- Ansible Automation
-- =============================================================================

--- Check if current buffer is likely an Ansible playbook/role
function M.is_ansible_buffer(buf)
  buf = buf or vim.api.nvim_get_current_buf()
  if not vim.api.nvim_buf_is_valid(buf) then
    return false
  end
  local ft = vim.bo[buf].filetype
  if ft == "yaml.ansible" or ft == "ansible" then
    return true
  end
  if ft == "yaml" then
    local path = vim.api.nvim_buf_get_name(buf)
    if path:match("playbook") or path:match("roles/") or path:match("tasks/") or path:match("handlers/") then
      return true
    end
    local lines = vim.api.nvim_buf_get_lines(buf, 0, 20, false)
    local content = table.concat(lines, "\n")
    if content:match("%-%s*hosts:") or (content:match("%-%s*name:") and content:match("tasks:")) then
      return true
    end
  end
  return false
end

local function with_ansible(callback)
  with_root(M.find_ansible_root, "No Ansible configuration found in workspace", callback)
end

local function resolve_ansible_target_file(root)
  local file = vim.fn.expand("%:p")
  if file ~= "" and M.is_ansible_buffer() then
    return file
  end
  if root then
    if vim.fn.filereadable(root .. "/site.yml") == 1 then
      return root .. "/site.yml"
    elseif vim.fn.filereadable(root .. "/site.yaml") == 1 then
      return root .. "/site.yaml"
    elseif vim.fn.filereadable(root .. "/playbook.yml") == 1 then
      return root .. "/playbook.yml"
    elseif vim.fn.filereadable(root .. "/playbook.yaml") == 1 then
      return root .. "/playbook.yaml"
    end
  end
  return file ~= "" and file or nil
end

function M.ansible_syntax_check()
  with_ansible(function(root)
    local file = resolve_ansible_target_file(root)
    if not file then
      vim.notify("No Ansible playbook found to check syntax.", vim.log.levels.WARN, { title = "TetraVim DevOps" })
      return
    end
    if vim.fn.executable("ansible-playbook") == 1 then
      M.run_term("ansible-playbook --syntax-check " .. vim.fn.shellescape(file), { cwd = root })
    else
      vim.notify("ansible-playbook is not installed in PATH.", vim.log.levels.WARN, { title = "TetraVim DevOps" })
    end
  end)
end

function M.ansible_lint()
  with_ansible(function(root)
    local file = resolve_ansible_target_file(root)
    if vim.fn.executable("ansible-lint") == 1 then
      if file and file ~= "" then
        M.run_term("ansible-lint " .. vim.fn.shellescape(file), { cwd = root })
      else
        M.run_term("ansible-lint", { cwd = root })
      end
    else
      vim.notify(
        "ansible-lint is not installed in PATH. Install via Mason (:MasonInstall ansible-lint).",
        vim.log.levels.WARN,
        { title = "TetraVim DevOps" }
      )
    end
  end)
end

function M.ansible_dry_run()
  with_ansible(function(root)
    local file = resolve_ansible_target_file(root)
    if not file then
      vim.notify("No Ansible playbook found to dry run.", vim.log.levels.WARN, { title = "TetraVim DevOps" })
      return
    end
    if vim.fn.executable("ansible-playbook") == 1 then
      M.run_term("ansible-playbook --check " .. vim.fn.shellescape(file), { cwd = root })
    else
      vim.notify("ansible-playbook is not installed in PATH.", vim.log.levels.WARN, { title = "TetraVim DevOps" })
    end
  end)
end

function M.ansible_run_playbook()
  with_ansible(function(root)
    local file = resolve_ansible_target_file(root)
    if not file then
      vim.notify("No Ansible playbook found to run.", vim.log.levels.WARN, { title = "TetraVim DevOps" })
      return
    end
    if vim.fn.executable("ansible-playbook") == 1 then
      M.run_term("ansible-playbook " .. vim.fn.shellescape(file), { cwd = root })
    else
      vim.notify("ansible-playbook is not installed in PATH.", vim.log.levels.WARN, { title = "TetraVim DevOps" })
    end
  end)
end

function M.ansible_inventory_graph()
  with_ansible(function(root)
    if vim.fn.executable("ansible-inventory") == 1 then
      M.run_term("ansible-inventory --graph", { cwd = root })
    else
      vim.notify("ansible-inventory is not installed in PATH.", vim.log.levels.WARN, { title = "TetraVim DevOps" })
    end
  end)
end

function M.ansible_doc_lookup()
  with_ansible(function(root)
    if vim.fn.executable("ansible-doc") == 1 then
      vim.ui.input({ prompt = "Ansible Module / Plugin Doc: " }, function(input)
        if input == nil then
          return
        end
        if input ~= "" then
          if not input:match("^[a-z0-9_.:-]+$") then
            vim.notify(
              "Invalid Ansible module name. Use lowercase alphanumeric, dots, underscores, hyphens, or colons.",
              vim.log.levels.WARN,
              { title = "TetraVim DevOps" }
            )
            return
          end
          M.run_term("ansible-doc " .. vim.fn.shellescape(input), { cwd = root })
        end
      end)
    else
      vim.notify("ansible-doc is not installed in PATH.", vim.log.levels.WARN, { title = "TetraVim DevOps" })
    end
  end)
end

function M.ansible_vault_action()
  with_ansible(function(root)
    if vim.fn.executable("ansible-vault") ~= 1 then
      vim.notify("ansible-vault is not installed in PATH.", vim.log.levels.WARN, { title = "TetraVim DevOps" })
      return
    end
    local file = vim.fn.expand("%:p")
    local actions = { "view", "encrypt", "decrypt", "edit" }

    local function run_vault_on_file(target_file)
      vim.ui.select(actions, { prompt = "Select Ansible Vault Action:" }, function(choice)
        if choice then
          M.run_term("ansible-vault " .. choice .. " " .. vim.fn.shellescape(target_file), { cwd = root })
        end
      end)
    end

    if file and file ~= "" then
      run_vault_on_file(file)
    else
      vim.ui.input({ prompt = "Ansible Vault File: " }, function(input)
        if input == nil then
          return
        end
        if input ~= "" then
          if input:match("^/") or input:match("%.%.") then
            vim.notify(
              "Invalid path. Use relative paths within the project (e.g., 'vault/secrets.yml').",
              vim.log.levels.WARN,
              { title = "TetraVim DevOps" }
            )
            return
          end
          local full_target = vim.fs.normalize(root .. "/" .. input)
          run_vault_on_file(full_target)
        end
      end)
    end
  end)
end

-- =============================================================================
-- Docker & Container Automation
-- =============================================================================

local function with_docker(callback)
  with_root(M.find_docker_root, "No Docker configuration found in workspace", callback)
end

local function resolve_docker_target_file(root)
  local file = vim.fn.expand("%:p")
  if file ~= "" and (vim.bo.filetype == "dockerfile" or file:match("Dockerfile") or file:match("Containerfile")) then
    return file
  end
  if root then
    if vim.fn.filereadable(root .. "/Dockerfile") == 1 then
      return root .. "/Dockerfile"
    elseif vim.fn.filereadable(root .. "/Containerfile") == 1 then
      return root .. "/Containerfile"
    end
  end
  return file ~= "" and file or nil
end

function M.docker_build()
  with_docker(function(root)
    local raw_name = vim.fs.normalize(root):match("([^/]+)$") or "app"
    local target_dir_name = raw_name:lower():gsub("[^%w%._%-]", "-"):gsub("^%-+", ""):gsub("%-+$", "")
    if target_dir_name == "" then
      target_dir_name = "app"
      vim.notify(
        "Using default image name 'app' (root directory name was unprintable)",
        vim.log.levels.INFO,
        { title = "TetraVim DevOps" }
      )
    end
    M.run_term("docker build -t " .. vim.fn.shellescape(target_dir_name) .. " .", { cwd = root })
  end)
end

function M.docker_lint()
  with_docker(function(root)
    local file = resolve_docker_target_file(root)
    if vim.fn.executable("hadolint") == 1 then
      if file and file ~= "" then
        M.run_term("hadolint " .. vim.fn.shellescape(file), { cwd = root })
      else
        local fallback = vim.fn.filereadable(root .. "/Containerfile") == 1 and "Containerfile" or "Dockerfile"
        M.run_term("hadolint " .. fallback, { cwd = root })
      end
    else
      vim.notify(
        "hadolint is not installed in PATH. Install via Mason (:MasonInstall hadolint).",
        vim.log.levels.WARN,
        { title = "TetraVim DevOps" }
      )
    end
  end)
end

-- =============================================================================
-- Helm & Kubernetes Automation
-- =============================================================================

local function with_helm(callback)
  with_root(M.find_helm_root, "No Helm configuration found in workspace", callback)
end

function M.helm_lint()
  with_helm(function(root)
    if vim.fn.executable("helm") == 1 then
      M.run_term("helm lint .", { cwd = root })
    else
      vim.notify("helm CLI is not installed in PATH.", vim.log.levels.WARN, { title = "TetraVim DevOps" })
    end
  end)
end

function M.helm_template()
  with_helm(function(root)
    if vim.fn.executable("helm") == 1 then
      M.run_term("helm template .", { cwd = root })
    else
      vim.notify("helm CLI is not installed in PATH.", vim.log.levels.WARN, { title = "TetraVim DevOps" })
    end
  end)
end

-- =============================================================================
-- Global Keymaps & WhichKey Registration
-- =============================================================================

M.keymaps_registered = false

function M.whichkey_spec()
  return {
    { "<leader>o", group = "devops/infra", icon = "󱁢 " },
    { "<leader>ot", group = "terraform/opentofu", icon = "󱁢 " },
    { "<leader>oc", group = "cloudformation/sam", icon = "󰅟 " },
    { "<leader>oy", group = "ansible", icon = "󰚰 " },
    { "<leader>od", group = "docker", icon = "󰡨 " },
    { "<leader>ok", group = "helm/k8s", icon = "󱃾 " },
  }
end

function M.setup_keymaps(force)
  if M.keymaps_registered and not force then
    return
  end

  -- These are a static list of well-formed mappings registered once at
  -- startup. vim.keymap.set does not throw for valid args, so a bad lhs/rhs
  -- here is a bug that should surface with a stack trace, not be swallowed
  -- into a toast -- hence a plain alias rather than a pcall wrapper.
  local map = vim.keymap.set

  -- Terraform & OpenTofu (<leader>ot). Descriptions omit a "Terraform:" prefix
  -- -- the which-key group label already reads "terraform/opentofu".
  map("n", "<leader>oti", M.terraform_init, { desc = "Init", silent = true })
  map("n", "<leader>otv", M.terraform_validate, { desc = "Validate", silent = true })
  map("n", "<leader>otp", M.terraform_plan, { desc = "Plan", silent = true })
  map("n", "<leader>ota", M.terraform_apply, { desc = "Apply", silent = true })
  map("n", "<leader>otf", M.terraform_fmt, { desc = "Format", silent = true })
  map("n", "<leader>otl", M.terraform_lint, { desc = "Lint (tflint)", silent = true })
  map("n", "<leader>ots", M.terraform_security, { desc = "Security Scan (trivy/tfsec)", silent = true })
  map("n", "<leader>oto", M.terraform_output, { desc = "Output", silent = true })

  -- AWS CloudFormation & SAM (<leader>oc). This group fronts two distinct CLIs,
  -- so the "CloudFormation:" / "SAM:" prefixes stay -- they disambiguate rather
  -- than echo the group label.
  map("n", "<leader>ocv", M.cfn_validate, { desc = "CloudFormation: Validate Template", silent = true })
  map("n", "<leader>ocl", M.cfn_lint, { desc = "CloudFormation: Lint (cfn-lint)", silent = true })
  map("n", "<leader>ocV", M.sam_validate, { desc = "SAM: Validate", silent = true })
  map("n", "<leader>ocb", M.sam_build, { desc = "SAM: Build", silent = true })
  map("n", "<leader>oci", M.sam_local_invoke, { desc = "SAM: Local Invoke", silent = true })
  map("n", "<leader>ocr", M.sam_local_start_api, { desc = "SAM: Local Start API", silent = true })
  map("n", "<leader>ocg", M.cfn_guard_validate, { desc = "CloudFormation: Policy Check (cfn-guard)", silent = true })

  -- Ansible Automation (<leader>oy) -- group label already reads "ansible".
  map("n", "<leader>oys", M.ansible_syntax_check, { desc = "Syntax Check", silent = true })
  map("n", "<leader>oyl", M.ansible_lint, { desc = "Lint Playbook", silent = true })
  map("n", "<leader>oyc", M.ansible_dry_run, { desc = "Dry Run (--check)", silent = true })
  map("n", "<leader>oyr", M.ansible_run_playbook, { desc = "Run Playbook", silent = true })
  map("n", "<leader>oyi", M.ansible_inventory_graph, { desc = "Inventory Graph", silent = true })
  map("n", "<leader>oyd", M.ansible_doc_lookup, { desc = "Module Documentation", silent = true })
  map("n", "<leader>oyv", M.ansible_vault_action, { desc = "Vault Action", silent = true })

  -- Docker & Containers (<leader>od) -- group label already reads "docker".
  map("n", "<leader>odb", M.docker_build, { desc = "Build Image", silent = true })
  map("n", "<leader>odl", M.docker_lint, { desc = "Lint Dockerfile", silent = true })
  map("n", "<leader>odd", function()
    require("tetravim.util.docker").open()
  end, { desc = "Runtime Dashboard", silent = true })

  -- Helm & Kubernetes (<leader>ok) -- group label already reads "helm/k8s".
  map("n", "<leader>okl", M.helm_lint, { desc = "Lint Chart", silent = true })
  map("n", "<leader>okt", M.helm_template, { desc = "Render Template", silent = true })
  map("n", "<leader>oke", function()
    require("tetravim.util.k8s").open()
  end, { desc = "Cluster Explorer", silent = true })

  M.keymaps_registered = true
end

return M
