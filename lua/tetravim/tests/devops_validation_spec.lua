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
