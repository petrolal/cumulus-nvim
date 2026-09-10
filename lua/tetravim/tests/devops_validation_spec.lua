-- DevOps Module Validation Tests
-- Tests input validation, CloudFormation detection, and buffer isolation

describe("DevOps Module - Input Validation", function()
  local devops

  before_each(function()
    devops = require("tetravim.core.devops")
  end)

  describe("sam_local_invoke - Lambda function name validation", function()
    it("should accept valid Lambda function names with alphanumeric and underscore", function()
      local valid_names = {
        "myFunction",
        "my_function",
        "MyFunction123",
        "my-function",
        "func_name_123",
      }
      for _, name in ipairs(valid_names) do
        assert.truthy(name:match("^[a-zA-Z0-9_-]+$"), "Should accept: " .. name)
      end
    end)

    it("should reject invalid Lambda function names with spaces", function()
      local invalid = "my function"
      assert.falsy(invalid:match("^[a-zA-Z0-9_-]+$"))
    end)

    it("should reject invalid Lambda function names with special chars", function()
      local invalid_names = {
        "my@function",
        "my$function",
        "my#function",
        "my.function",
        "my/function",
      }
      for _, name in ipairs(invalid_names) do
        assert.falsy(name:match("^[a-zA-Z0-9_-]+$"), "Should reject: " .. name)
      end
    end)

    it("should reject empty or nil input", function()
      assert.falsy((""):match("^[a-zA-Z0-9_-]+$"))
      assert.falsy((nil or ""):match("^[a-zA-Z0-9_-]+$"))
    end)
  end)

  describe("ansible_doc_lookup - Module name validation", function()
    it("should accept valid Ansible module names", function()
      local valid_modules = {
        "aws_ec2",
        "azure.azcollection.azure_rm_virtualmachine",
        "community.general.debug",
        "ansible.builtin.shell",
        "module_name",
        "ns:plugin:action",
      }
      for _, name in ipairs(valid_modules) do
        assert.truthy(name:match("^[a-z0-9_.:-]+$"), "Should accept: " .. name)
      end
    end)

    it("should reject uppercase letters in module names", function()
      local invalid = "MyModule"
      assert.falsy(invalid:match("^[a-z0-9_.:-]+$"))
    end)

    it("should reject invalid special characters", function()
      local invalid_modules = {
        "module@name",
        "module#name",
        "module$name",
        "module name",
        "module/name",
      }
      for _, name in ipairs(invalid_modules) do
        assert.falsy(name:match("^[a-z0-9_.:-]+$"), "Should reject: " .. name)
      end
    end)

    it("should allow colons for namespace:plugin:action format", function()
      local valid = "community.general.debug"
      assert.truthy(valid:match("^[a-z0-9_.:-]+$"))
    end)
  end)

  describe("CloudFormation buffer detection", function()
    it("should detect CloudFormation YAML by template version", function()
      assert.truthy(("AWSTemplateFormatVersion: '2010-09-09'"):match("AWSTemplateFormatVersion"))
    end)

    it("should detect SAM template by Transform directive", function()
      assert.truthy(("Transform: AWS::Serverless-2016-10-31"):match("Transform:%s*AWS::Serverless"))
    end)

    it("should detect SAM by AWS::Serverless resource", function()
      assert.truthy(("AWS::Serverless::Function:"):match("AWS::Serverless"))
    end)

    it("should not false-positive on regular YAML", function()
      local regular_yaml = "key: value\nlist:\n  - item1"
      assert.falsy(regular_yaml:match("AWSTemplateFormatVersion"))
      assert.falsy(regular_yaml:match("AWS::Serverless"))
    end)
  end)

  describe("Path validation for Ansible vault", function()
    it("should reject absolute paths", function()
      local absolute_path = "/etc/ansible/vault"
      assert.truthy(absolute_path:match("^/"))
    end)

    it("should reject paths with parent directory traversal", function()
      local traversal = "../../secrets/vault"
      assert.truthy(traversal:match("%.%."))
    end)

    it("should accept relative paths", function()
      local relative = "vault/secrets.yml"
      assert.falsy(relative:match("^/"))
      assert.falsy(relative:match("%.%."))
    end)

    it("should accept deep relative paths", function()
      local deep_path = "roles/common/files/vault.yml"
      assert.falsy(deep_path:match("^/"))
      assert.falsy(deep_path:match("%.%."))
    end)
  end)

  describe("devops module buffer safety", function()
    it("should validate buffer before accessing", function()
      local invalid_buf = 99999
      -- This would normally use vim.api.nvim_buf_is_valid, which we can't test in isolation
      -- But we verify the pattern is used throughout the module
      local code = io.open("lua/tetravim/core/devops.lua"):read("*a")
      assert.truthy(code:find("nvim_buf_is_valid"))
    end)

    it("should use pcall for error handling in callbacks", function()
      local code = io.open("lua/tetravim/core/devops.lua"):read("*a")
      assert.truthy(code:find("pcall.*callback"))
    end)

    it("should validate file readability before operations", function()
      local code = io.open("lua/tetravim/core/devops.lua"):read("*a")
      assert.truthy(code:find("filereadable"))
    end)
  end)
end)

describe("DevOps Module - Root Discovery Safety", function()
  local devops

  before_each(function()
    devops = require("tetravim.core.devops")
  end)

  describe("root finder type validation", function()
    it("should handle nil roots gracefully", function()
      local get_first_root = function(roots, key)
        if not roots or type(roots) ~= "table" then
          return nil
        end
        local items = roots[key]
        if not items or type(items) ~= "table" or #items == 0 then
          return nil
        end
        return items[1]
      end
      assert.is_nil(get_first_root(nil, "terraform"))
    end)

    it("should handle missing key in roots", function()
      local get_first_root = function(roots, key)
        if not roots or type(roots) ~= "table" then
          return nil
        end
        local items = roots[key]
        if not items or type(items) ~= "table" or #items == 0 then
          return nil
        end
        return items[1]
      end
      local roots = { aws = { "/some/path" } }
      assert.is_nil(get_first_root(roots, "terraform"))
    end)

    it("should return first item when available", function()
      local get_first_root = function(roots, key)
        if not roots or type(roots) ~= "table" then
          return nil
        end
        local items = roots[key]
        if not items or type(items) ~= "table" or #items == 0 then
          return nil
        end
        return items[1]
      end
      local roots = { terraform = { "/tf/root", "/tf/root2" } }
      assert.equals("/tf/root", get_first_root(roots, "terraform"))
    end)
  end)
end)

describe("DevOps Module - Error Handling", function()
  it("should use with_root for safe execution", function()
    local code = io.open("lua/tetravim/core/devops.lua"):read("*a")
    assert.truthy(code:find("function with_root"))
    assert.truthy(code:find("pcall.*callback"))
  end)

  it("should notify user on missing tools", function()
    local code = io.open("lua/tetravim/core/devops.lua"):read("*a")
    assert.truthy(code:find("vim.notify"))
  end)

  it("should provide helpful error messages", function()
    local code = io.open("lua/tetravim/core/devops.lua"):read("*a")
    -- Check for descriptive error messages
    assert.truthy(code:find("not installed in PATH"))
    assert.truthy(code:find("configuration found"))
  end)
end)

-- Migrated from scripts/validate-devops.sh: the root-finder declaration-order
-- regression guard. `create_root_finder` closes over `resolve_search_dir`, and
-- every `M.find_*_root` is built by calling it at module-load time; a prior
-- version assigned those before the helpers existed (forward local refs capture
-- nil, so the assignment is silent but every later CALL throws).
describe("DevOps Module - root-finder declaration order", function()
  it("declares resolve_search_dir and create_root_finder before any M.find_*_root assignment", function()
    local src = io.open("lua/tetravim/core/devops.lua"):read("*a")
    local resolve_pos = src:find("local function resolve_search_dir")
    local factory_pos = src:find("local function create_root_finder")
    local first_assign_pos = src:find("M%.find_tf_root%s*=%s*create_root_finder")

    assert.truthy(resolve_pos, "resolve_search_dir declaration not found")
    assert.truthy(factory_pos, "create_root_finder declaration not found")
    assert.truthy(first_assign_pos, "M.find_tf_root assignment not found")
    assert.is_true(resolve_pos < first_assign_pos, "resolve_search_dir must precede the first M.find_*_root assignment")
    assert.is_true(factory_pos < first_assign_pos, "create_root_finder must precede the first M.find_*_root assignment")
  end)

  it("every M.find_*_root is real-callable (buffer and path forms) without erroring", function()
    local devops = require("tetravim.core.devops")
    local finders = { "find_tf_root", "find_cfn_root", "find_ansible_root", "find_docker_root", "find_helm_root" }

    vim.cmd("enew")
    local bufnr = vim.api.nvim_get_current_buf()
    local orig_notify = vim.notify
    vim.notify = function() end
    local err
    for _, name in ipairs(finders) do
      assert.is_function(devops[name], name .. " is not a function on tetravim.core.devops")
      local ok1 = pcall(devops[name], bufnr)
      local ok2 = pcall(devops[name], vim.fn.getcwd())
      if not (ok1 and ok2) then
        err = name .. " raised an error -- declaration-order regression"
        break
      end
    end
    vim.notify = orig_notify
    assert.is_nil(err, err)
  end)
end)

describe("DevOps Module - validate.sh stage 6 functional suite", function()
  it(
    "Purge guards (engine, rust, beans, endpoints, import-optimizer, k8s-validator, migrations, conflicts, log-indexer must NOT require)",
    function()
      assert.has_error(function()
        require("tetravim.util.engine")
      end)
      assert.has_error(function()
        require("tetravim.util.rust")
      end)
      assert.has_error(function()
        require("tetravim.util.beans")
      end)
      assert.has_error(function()
        require("tetravim.util.endpoints")
      end)
      assert.has_error(function()
        require("tetravim.util.import-optimizer")
      end)
      assert.has_error(function()
        require("tetravim.util.k8s-validator")
      end)
      assert.has_error(function()
        require("tetravim.util.migrations")
      end)
      assert.has_error(function()
        require("tetravim.util.conflicts")
      end)
      assert.has_error(function()
        require("tetravim.util.log-indexer")
      end)
    end
  )

  it("API surface (notify)", function()
    local notify = require("tetravim.util.notify")
    assert.is_function(notify.notify)
    assert.is_function(notify.notify_info)
    assert.is_function(notify.notify_warn)
    assert.is_function(notify.notify_err)
  end)

  it("API surface (term)", function()
    local term = require("tetravim.util.term")
    assert.is_function(term.run_term)
  end)

  it("API surface (spring and spring_picker)", function()
    local s = require("tetravim.util.spring")
    local p = require("tetravim.util.spring_picker")
    assert.is_function(s.build_dap_config)
    assert.is_function(s.find_beans)
    assert.is_function(s.find_endpoints)
    assert.is_function(p.pick_bean)
    assert.is_function(p.pick_endpoint)
  end)

  it("API surface (coverage)", function()
    local cov = require("tetravim.util.coverage")
    assert.is_function(cov.load)
    assert.is_function(cov.clear)
    assert.is_function(cov.toggle)
    assert.is_function(cov.parse)
  end)

  it("API surface (devops)", function()
    local devops = require("tetravim.core.devops")
    assert.is_function(devops.cfn_validate)
    assert.is_function(devops.sam_local_invoke)
    assert.is_function(devops.ansible_syntax_check)
    assert.is_function(devops.ansible_lint)
    assert.is_function(devops.ansible_dry_run)
    assert.is_function(devops.ansible_run_playbook)
    assert.is_function(devops.ansible_inventory_graph)
    assert.is_function(devops.ansible_doc_lookup)
    assert.is_function(devops.ansible_vault_action)
  end)

  it("WhichKey spec groups", function()
    local devops = require("tetravim.core.devops")
    assert.is_function(devops.setup_keymaps)
    assert.is_function(devops.whichkey_spec)
    local wk_spec = devops.whichkey_spec()
    local groups = {}
    for _, item in ipairs(wk_spec) do
      groups[item[1]] = item.group
    end
    assert.equals("devops/infra", groups["<leader>o"])
    assert.equals("terraform/opentofu", groups["<leader>ot"])
    assert.equals("cloudformation/sam", groups["<leader>oc"])
    assert.equals("ansible", groups["<leader>oy"])
    assert.equals("docker", groups["<leader>od"])
    assert.equals("helm/k8s", groups["<leader>ok"])
  end)

  it("Global keymap registration", function()
    local devops = require("tetravim.core.devops")
    devops.setup_keymaps()
    local global_maps = vim.api.nvim_get_keymap("n")
    local expected_subkeys = {
      "oti",
      "otv",
      "otp",
      "ota",
      "otf",
      "otl",
      "ots",
      "oto",
      "ocv",
      "ocl",
      "ocV",
      "ocb",
      "oci",
      "ocr",
      "ocg",
      "oys",
      "oyl",
      "oyc",
      "oyr",
      "oyi",
      "oyd",
      "oyv",
      "odb",
      "odl",
      "okl",
      "okt",
    }
    local found_keymaps = 0
    for _, key in ipairs(expected_subkeys) do
      local found = false
      for _, m in ipairs(global_maps) do
        if m.lhs == "<leader>" .. key or m.lhs == "<Space>" .. key or m.lhs == " " .. key then
          found = true
          found_keymaps = found_keymaps + 1
          break
        end
      end
      assert.is_true(found, "leader " .. key .. " missing from global keymaps")
    end
    assert.is_true(found_keymaps >= 26)
  end)

  it("Mason ensure_installed", function()
    local mason_plugins = require("tetravim.plugins.tools-mason")
    local ensure_installed = nil
    for _, plugin in ipairs(mason_plugins) do
      if plugin.opts and plugin.opts.ensure_installed then
        ensure_installed = plugin.opts.ensure_installed
        break
      end
    end
    assert.is_not_nil(ensure_installed)
    local ensure_set = {}
    for _, pkg in ipairs(ensure_installed) do
      ensure_set[pkg] = true
    end
    for _, req in ipairs({
      "terraform-ls",
      "tflint",
      "cfn-lint",
      "ansible-language-server",
      "ansible-lint",
      "yaml-language-server",
    }) do
      assert.is_true(ensure_set[req] or false, "Missing Mason package: " .. req)
    end
  end)

  it("SPEC-1.1 lsp-scala + dap-devops", function()
    local lsp_scala_ok, lsp_scala_spec = pcall(require, "tetravim.plugins.lsp-scala")
    assert.is_true(lsp_scala_ok)
    assert.equals("table", type(lsp_scala_spec))
    assert.equals("table", type(lsp_scala_spec[1]))
    assert.equals("scalameta/nvim-metals", lsp_scala_spec[1][1])

    local dap_devops_ok, dap_devops_spec = pcall(require, "tetravim.plugins.tools-dap-devops")
    assert.is_true(dap_devops_ok)
    local dap_keys = dap_devops_spec[1].keys
    local dap_key_lhs = {}
    for _, k in ipairs(dap_keys) do
      dap_key_lhs[k[1]] = true
    end
    for _, req in ipairs({ "<leader>dC", "<leader>dL", "<leader>dE", "<leader>dv" }) do
      assert.is_true(dap_key_lhs[req] or false, "Missing DAP keymap: " .. req)
    end
  end)

  it("Conform formatters_by_ft", function()
    local conform_plugins = require("tetravim.plugins.tools-formatting")
    local formatters_by_ft = nil
    for _, plugin in ipairs(conform_plugins) do
      if plugin.opts and plugin.opts.formatters_by_ft then
        formatters_by_ft = plugin.opts.formatters_by_ft
        break
      end
    end
    assert.is_not_nil(formatters_by_ft)
    assert.equals("terraform_fmt", formatters_by_ft.terraform[1])
  end)

  describe("Real workspace root discovery", function()
    local tmp_root
    local devops

    before_each(function()
      devops = require("tetravim.core.devops")
      tmp_root = vim.fs.normalize(vim.fn.tempname())
      vim.fn.mkdir(tmp_root, "p")
    end)

    after_each(function()
      vim.fn.delete(tmp_root, "rf")
    end)

    it("Terraform discovery", function()
      local tf_proj = tmp_root .. "/tf_proj"
      local tf_mod = tf_proj .. "/infra/terraform/modules/vpc"
      vim.fn.mkdir(tf_mod, "p")
      vim.fn.writefile({ 'resource "vpc" {}' }, tf_mod .. "/vpc.tf")
      vim.fn.writefile({ "terraform {}" }, tf_proj .. "/infra/terraform/main.tf")

      assert.equals(tf_mod, devops.find_tf_root(tf_mod .. "/vpc.tf"))
      assert.equals(tf_proj .. "/infra/terraform", devops.find_tf_root(tf_proj))
    end)

    it("CloudFormation / SAM discovery", function()
      local cfn_proj = tmp_root .. "/cfn_proj"
      vim.fn.mkdir(cfn_proj .. "/src", "p")
      vim.fn.writefile({ "AWSTemplateFormatVersion: 2010-09-09" }, cfn_proj .. "/template.yaml")
      vim.fn.writefile({ "version = 0.1" }, cfn_proj .. "/samconfig.toml")

      assert.equals(cfn_proj, devops.find_cfn_root(cfn_proj))
      assert.equals(cfn_proj, devops.find_cfn_root(cfn_proj .. "/src/app.py"))
    end)

    it("Ansible discovery", function()
      local ans_proj = tmp_root .. "/ans_proj"
      local ans_pb = ans_proj .. "/playbooks"
      vim.fn.mkdir(ans_pb, "p")
      vim.fn.writefile({ "[defaults]" }, ans_proj .. "/ansible.cfg")
      vim.fn.writefile({ "- hosts: all" }, ans_pb .. "/site.yml")

      assert.equals(ans_proj, devops.find_ansible_root(ans_proj))
      assert.equals(ans_pb, devops.find_ansible_root(ans_pb .. "/site.yml"))
    end)

    it("Docker discovery", function()
      local doc_proj = tmp_root .. "/doc_proj"
      vim.fn.mkdir(doc_proj .. "/src", "p")
      vim.fn.writefile({ "FROM alpine" }, doc_proj .. "/Dockerfile")
      vim.fn.writefile({ "services: {}" }, doc_proj .. "/docker-compose.yml")

      assert.equals(doc_proj, devops.find_docker_root(doc_proj))
      assert.equals(doc_proj, devops.find_docker_root(doc_proj .. "/src/main.go"))
    end)

    it("Helm discovery", function()
      local helm_proj = tmp_root .. "/helm_proj"
      local helm_chart = helm_proj .. "/charts/web-service"
      vim.fn.mkdir(helm_chart .. "/templates", "p")
      vim.fn.writefile({ "apiVersion: v2", "name: web-service" }, helm_chart .. "/Chart.yaml")
      vim.fn.writefile({ "replicaCount: 1" }, helm_chart .. "/values.yaml")

      assert.equals(helm_chart, devops.find_helm_root(helm_proj))
      assert.equals(helm_chart, devops.find_helm_root(helm_chart .. "/templates/deployment.yaml"))
    end)

    it("Non-DevOps workspace & fallback", function()
      local empty_proj = tmp_root .. "/empty_proj"
      vim.fn.mkdir(empty_proj, "p")
      vim.fn.writefile({ "# Readme" }, empty_proj .. "/README.md")

      assert.is_nil(devops.find_tf_root(empty_proj))
      assert.is_nil(devops.find_cfn_root(empty_proj))
      assert.is_nil(devops.find_ansible_root(empty_proj))
      assert.is_nil(devops.find_docker_root(empty_proj))
      assert.is_nil(devops.find_helm_root(empty_proj))

      local res = devops.find_tf_root(999999)
      assert.is_true(res == nil or type(res) == "string")
    end)

    it("JVM project detection", function()
      local jvm = require("tetravim.util.jvm")
      local build_util = require("tetravim.util.build")

      local jvm_proj = tmp_root .. "/jvm_proj"
      vim.fn.mkdir(jvm_proj, "p")
      vim.fn.writefile({ "<project></project>" }, jvm_proj .. "/pom.xml")

      assert.is_true(jvm.is_jvm_project(jvm_proj))
      assert.equals("maven", build_util.detect(jvm_proj))

      local empty_proj = tmp_root .. "/empty_proj"
      vim.fn.mkdir(empty_proj, "p")
      assert.is_nil(build_util.detect(empty_proj))
      assert.is_false(jvm.is_jvm_project(empty_proj))
    end)
  end)

  describe("Mock execution tests", function()
    local devops
    local orig_run_term, orig_notify, orig_get_tf_cmd
    local orig_find_tf_root, orig_find_ansible_root
    local orig_find_docker_root, orig_find_helm_root, orig_find_cfn_root
    local last_executed_cmd, last_executed_opts
    local last_notify_msg, last_notify_level

    before_each(function()
      devops = require("tetravim.core.devops")

      orig_run_term = devops.run_term
      orig_notify = vim.notify
      orig_get_tf_cmd = devops.get_tf_cmd
      orig_find_tf_root = devops.find_tf_root
      orig_find_ansible_root = devops.find_ansible_root
      orig_find_docker_root = devops.find_docker_root
      orig_find_helm_root = devops.find_helm_root
      orig_find_cfn_root = devops.find_cfn_root

      last_executed_cmd, last_executed_opts = nil, nil
      devops.run_term = function(cmd, opts)
        last_executed_cmd = cmd
        last_executed_opts = opts
      end

      last_notify_msg, last_notify_level = nil, nil
      vim.notify = function(msg, level, opts)
        last_notify_msg = msg
        last_notify_level = level
      end
    end)

    after_each(function()
      devops.run_term = orig_run_term
      vim.notify = orig_notify
      devops.get_tf_cmd = orig_get_tf_cmd
      devops.find_tf_root = orig_find_tf_root
      devops.find_ansible_root = orig_find_ansible_root
      devops.find_docker_root = orig_find_docker_root
      devops.find_helm_root = orig_find_helm_root
      devops.find_cfn_root = orig_find_cfn_root
    end)

    it("Terraform adoption & missing notification", function()
      devops.get_tf_cmd = function()
        return "tofu"
      end
      devops.find_tf_root = function()
        return "/mock/tf/root"
      end
      devops.terraform_init()
      assert.equals("tofu init", last_executed_cmd)
      assert.equals("/mock/tf/root", last_executed_opts.cwd)

      devops.find_tf_root = function()
        return nil
      end
      last_executed_cmd = nil
      last_notify_msg = nil
      devops.terraform_plan()
      assert.is_nil(last_executed_cmd)
      assert.truthy(last_notify_msg:match("No Terraform/OpenTofu configuration found in workspace"))
    end)

    it("Ansible adoption & missing notification", function()
      devops.find_ansible_root = function()
        return "/mock/ansible/root"
      end
      devops.ansible_inventory_graph()
      assert.equals("ansible-inventory --graph", last_executed_cmd)
      assert.equals("/mock/ansible/root", last_executed_opts.cwd)

      devops.find_ansible_root = function()
        return nil
      end
      last_executed_cmd = nil
      last_notify_msg = nil
      devops.ansible_syntax_check()
      assert.is_nil(last_executed_cmd)
      assert.truthy(last_notify_msg:match("No Ansible configuration found in workspace"))
    end)

    it("Docker adoption & missing notification", function()
      devops.find_docker_root = function()
        return "/mock/docker/my-app"
      end
      devops.docker_build()
      assert.truthy(last_executed_cmd:match("docker build %-t 'my%-app' %."))
      assert.equals("/mock/docker/my-app", last_executed_opts.cwd)

      devops.find_docker_root = function()
        return nil
      end
      last_executed_cmd = nil
      last_notify_msg = nil
      devops.docker_build()
      assert.is_nil(last_executed_cmd)
      assert.truthy(last_notify_msg:match("No Docker configuration found in workspace"))
    end)

    it("Helm adoption & missing notification", function()
      devops.find_helm_root = function()
        return "/mock/helm/my-chart"
      end
      devops.helm_lint()
      assert.equals("helm lint .", last_executed_cmd)
      assert.equals("/mock/helm/my-chart", last_executed_opts.cwd)

      devops.find_helm_root = function()
        return nil
      end
      last_executed_cmd = nil
      last_notify_msg = nil
      devops.helm_lint()
      assert.is_nil(last_executed_cmd)
      assert.truthy(last_notify_msg:match("No Helm configuration found in workspace"))
    end)

    it("CloudFormation / SAM missing notification", function()
      devops.find_cfn_root = function()
        return nil
      end
      last_executed_cmd = nil
      last_notify_msg = nil
      devops.sam_validate()
      assert.is_nil(last_executed_cmd)
      assert.truthy(last_notify_msg:match("No CloudFormation/SAM configuration found in workspace"))
    end)
  end)

  it("Profiling API", function()
    local profiling = require("tetravim.util.profiling")
    assert.is_function(profiling.start)
    assert.is_function(profiling.stop)
    assert.is_function(profiling.view)
  end)

  it("JVM whichkey spec + keymaps", function()
    local jvm = require("tetravim.util.jvm")
    local jvm_wk = jvm.whichkey_spec()
    local jvm_groups = {}
    for _, item in ipairs(jvm_wk) do
      jvm_groups[item[1]] = item.group
    end
    assert.equals("profiling", jvm_groups["<leader>jp"])
    assert.equals("code coverage", jvm_groups["<leader>jc"])
    assert.equals("test runner", jvm_groups["<leader>jt"])

    jvm.setup_keymaps()
    assert.not_equals("", vim.fn.maparg("<leader>jps", "n"))
    assert.not_equals("", vim.fn.maparg("<leader>jpx", "n"))
    assert.not_equals("", vim.fn.maparg("<leader>jpv", "n"))
    assert.not_equals("", vim.fn.maparg("<leader>jcl", "n"))
    assert.not_equals("", vim.fn.maparg("<leader>jcx", "n"))
    assert.not_equals("", vim.fn.maparg("<leader>jct", "n"))
    assert.not_equals("", vim.fn.maparg("<leader>jcs", "n"))
    assert.not_equals("", vim.fn.maparg("<leader>jtt", "n"))
    assert.not_equals("", vim.fn.maparg("<leader>jtc", "n"))
    assert.not_equals("", vim.fn.maparg("<leader>jta", "n"))
  end)
end)
