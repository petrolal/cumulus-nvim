#!/usr/bin/env bash
# Quick smoke validation test script for tetravim.nvim

set -e

echo "=== TetraVim Neovim Distribution Smoke Test ==="

echo "[1/7] Verifying Shell Scripts Syntax (bootstrap.sh, scripts/bootstrap.sh, headless-setup.sh, dev-init.sh, validate.sh, validate-test-coverage.sh)..."
if bash -n bootstrap.sh && bash -n scripts/bootstrap.sh && bash -n scripts/headless-setup.sh && bash -n scripts/dev-init.sh && bash -n scripts/validate.sh && bash -n scripts/validate-test-coverage.sh; then
  echo "✔ Shell scripts syntax PASSED."
else
  echo "✖ Shell scripts syntax FAILED."
  exit 1
fi

echo "[1.1/7] Verifying bootstrap dependency coverage (async-profiler, ripgrep, health probe)..."
cov_fail=0
for script in bootstrap.sh scripts/bootstrap.sh; do
  if ! grep -q "async-profiler" "$script"; then
    echo "✖ $script does not provision async-profiler."
    cov_fail=1
  fi
  if ! grep -Eq "ripgrep|[^a-z]rg[^a-z]" "$script"; then
    echo "✖ $script does not provision ripgrep."
    cov_fail=1
  fi
done
if ! grep -q "async-profiler" lua/tetravim/health.lua; then
  echo "✖ lua/tetravim/health.lua has no async-profiler probe."
  cov_fail=1
fi
if [ "$cov_fail" -ne 0 ]; then
  echo "✖ Bootstrap dependency coverage FAILED."
  exit 1
fi
echo "✔ Bootstrap dependency coverage PASSED."

echo "[2/7] Verifying Neovim Loading & Startup..."
nvim -u init.lua --headless -c "lua
local ok, err = pcall(function()
  print('✔ Core init.lua loads without error')
end)
if not ok then io.stderr:write(tostring(err) .. '\n'); vim.cmd('cquit 1') end
" -c "qa!"
echo "✔ Headless core init.lua PASSED."

echo "[3/7] Verifying Core Modules (Options, Keymaps, Autocmds, Health)..."
nvim -u init.lua --headless -c "lua
local ok, err = pcall(function()
  require('tetravim.core.options')
  require('tetravim.core.keymaps')
  require('tetravim.core.autocmds')
  require('tetravim.health')
  print('✔ Core modules loaded successfully')
end)
if not ok then io.stderr:write(tostring(err) .. '\n'); vim.cmd('cquit 1') end
" -c "qa!"
echo "✔ Core modules PASSED."

echo "[4/7] Verifying Theme System (Tetris palette)..."
nvim -u init.lua --headless -c "lua
local ok, err = pcall(function()
  require('tetravim.theme').setup()
  print('✔ Theme system initialized')
end)
if not ok then io.stderr:write(tostring(err) .. '\n'); vim.cmd('cquit 1') end
" -c "qa!"
echo "✔ Theme system PASSED."

echo "[5/7] Verifying LSP, Completion & UI Specs..."
nvim -u init.lua --headless -c "lua
local ok, err = pcall(function()
  assert(pcall(require, 'cmp'), 'cmp not available')
  assert(pcall(require, 'lspconfig'), 'lspconfig not available')
  assert(pcall(require, 'render-markdown'), 'render-markdown not available')
  assert(pcall(require, 'persistence'), 'persistence not available')
  print('✔ Plugins and UI specs verified')
end)
if not ok then io.stderr:write(tostring(err) .. '\n'); vim.cmd('cquit 1') end
" -c "qa!"
echo "✔ Plugins and UI specs PASSED."

echo "[5.1/7] Verifying File Explorer (oil.nvim)..."
nvim -u init.lua --headless -c "lua
local ok, err = pcall(function()
  assert(pcall(require, 'oil'), 'oil module not found')
  local maps = vim.api.nvim_get_keymap('n')
  local found = false
  for _, m in ipairs(maps) do
    if (m.lhs == '<Space>e' or m.lhs == ' e' or m.lhs == '<leader>e') then found = true; break end
  end
  assert(found, '<leader>e keymap not found')
  print('✔ oil.nvim and keymaps verified')
end)
if not ok then io.stderr:write(tostring(err) .. '\n'); vim.cmd('cquit 1') end
" -c "qa!"
echo "✔ File Explorer PASSED."

echo "[6/7] Verifying Native DevOps Suite (Terraform, CloudFormation, Ansible, WhichKey, Mason & Scoped Buffers)..."
nvim -u init.lua --headless -c "lua
local ok, err = pcall(function()
  -- The Scala tetravim-engine bridge has been removed entirely.
  assert(not pcall(require, 'tetravim.util.engine'), 'tetravim.util.engine must be removed')

  local notify = require('tetravim.util.notify')
  assert(type(notify.notify) == 'function', 'notify.notify not found')
  assert(type(notify.notify_info) == 'function', 'notify.notify_info not found')
  assert(type(notify.notify_warn) == 'function', 'notify.notify_warn not found')
  assert(type(notify.notify_err) == 'function', 'notify.notify_err not found')
  notify.notify('test notify', vim.log.levels.INFO, 'Test Title')
  notify.notify_info('test info', 'Test Title')
  notify.notify_warn('test warn', 'Test Title')
  notify.notify_err('test err', 'Test Title')

  local term = require('tetravim.util.term')
  assert(type(term.run_term) == 'function', 'term.run_term not found')

  local s = require('tetravim.util.spring')
  local p = require('tetravim.util.spring-picker')
  assert(type(s.build_dap_config) == 'function', 'build_dap_config not found')
  assert(type(s.find_beans) == 'function', 'find_beans not found')
  assert(type(s.find_endpoints) == 'function', 'find_endpoints not found')
  assert(type(p.pick_bean) == 'function', 'pick_bean not found')
  assert(type(p.pick_endpoint) == 'function', 'pick_endpoint not found')

  -- Verify purged stub and wrapper files do not exist
  assert(not pcall(require, 'tetravim.util.rust'), 'rust.lua must be purged')
  assert(not pcall(require, 'tetravim.util.beans'), 'beans.lua must be purged')
  assert(not pcall(require, 'tetravim.util.endpoints'), 'endpoints.lua must be purged')
  assert(not pcall(require, 'tetravim.util.import-optimizer'), 'import-optimizer.lua must be purged')
  assert(not pcall(require, 'tetravim.util.k8s-validator'), 'k8s-validator.lua must be purged')
  assert(not pcall(require, 'tetravim.util.migrations'), 'migrations.lua must be purged')
  assert(not pcall(require, 'tetravim.util.conflicts'), 'conflicts.lua must be purged')
  local cov = require('tetravim.util.coverage')
  assert(type(cov.load) == 'function', 'coverage.load not found')
  assert(type(cov.clear) == 'function', 'coverage.clear not found')
  assert(type(cov.toggle) == 'function', 'coverage.toggle not found')
  assert(type(cov.parse) == 'function', 'coverage.parse not found')
  assert(not pcall(require, 'tetravim.util.log-indexer'), 'log-indexer.lua must be purged')
  local devops = require('tetravim.core.devops')
  assert(type(devops.cfn_validate) == 'function')
  assert(type(devops.sam_local_invoke) == 'function')
  assert(type(devops.ansible_syntax_check) == 'function')
  assert(type(devops.ansible_lint) == 'function')
  assert(type(devops.ansible_dry_run) == 'function')
  assert(type(devops.ansible_run_playbook) == 'function')
  assert(type(devops.ansible_inventory_graph) == 'function')
  assert(type(devops.ansible_doc_lookup) == 'function')
  assert(type(devops.ansible_vault_action) == 'function')

  -- Story 9.3: Universal Keymap Registration & WhichKey Scope Configuration
  assert(type(devops.setup_keymaps) == 'function', 'setup_keymaps not found')
  assert(type(devops.whichkey_spec) == 'function', 'whichkey_spec not found')
  local wk_spec = devops.whichkey_spec()
  local groups = {}
  for _, item in ipairs(wk_spec) do
    groups[item[1]] = item.group
  end
  assert(groups['<leader>o'] == 'devops/infra', '<leader>o missing in devops whichkey_spec')
  assert(groups['<leader>ot'] == 'terraform/opentofu', '<leader>ot missing in devops whichkey_spec')
  assert(groups['<leader>oc'] == 'cloudformation/sam', '<leader>oc missing in devops whichkey_spec')
  assert(groups['<leader>oy'] == 'ansible', '<leader>oy missing in devops whichkey_spec')
  assert(groups['<leader>od'] == 'docker', '<leader>od missing in devops whichkey_spec')
  assert(groups['<leader>ok'] == 'helm/k8s', '<leader>ok missing in devops whichkey_spec')

  -- Check global availability of all 26 DevOps keymaps across any buffer
  -- Story 9.3: Keymaps are now GLOBALLY registered (not buffer-scoped)
  local global_maps = vim.api.nvim_get_keymap('n')
  local expected_subkeys = {
    -- Terraform (<leader>ot)
    'oti', 'otv', 'otp', 'ota', 'otf', 'otl', 'ots', 'oto',
    -- AWS CloudFormation & SAM (<leader>oc)
    'ocv', 'ocl', 'ocV', 'ocb', 'oci', 'ocr', 'ocg',
    -- Ansible (<leader>oy)
    'oys', 'oyl', 'oyc', 'oyr', 'oyi', 'oyd', 'oyv',
    -- Docker (<leader>od)
    'odb', 'odl',
    -- Helm (<leader>ok)
    'okl', 'okt',
  }
  local found_keymaps = 0
  for _, key in ipairs(expected_subkeys) do
    local found = false
    for _, m in ipairs(global_maps) do
      if m.lhs == '<leader>' .. key or m.lhs == '<Space>' .. key or m.lhs == ' ' .. key then
        found = true
        found_keymaps = found_keymaps + 1
        break
      end
    end
    assert(found, 'leader ' .. key .. ' missing from global keymaps')
  end
  assert(found_keymaps >= 26, 'DevOps keymap count mismatch: found ' .. found_keymaps .. ' of 26')

  -- Robust Mason spec lookup
  local mason_plugins = require('tetravim.plugins.tools-mason')
  local ensure_installed = nil
  for _, plugin in ipairs(mason_plugins) do
    if plugin.opts and plugin.opts.ensure_installed then
      ensure_installed = plugin.opts.ensure_installed
      break
    end
  end
  assert(ensure_installed, 'mason ensure_installed not found')
  local ensure_set = {}
  for _, pkg in ipairs(ensure_installed) do
    ensure_set[pkg] = true
  end
  for _, req in ipairs({'terraform-ls', 'tflint', 'cfn-lint', 'ansible-language-server', 'ansible-lint', 'yaml-language-server'}) do
    assert(ensure_set[req], 'Missing Mason package: ' .. req)
  end

  -- SPEC-1.1: Advanced JVM Debugger (nvim-dap integration) -- Scala/Metals
  local lsp_scala_ok, lsp_scala_spec = pcall(require, 'tetravim.plugins.lsp-scala')
  assert(lsp_scala_ok, 'tetravim.plugins.lsp-scala failed to load: ' .. tostring(lsp_scala_spec))
  assert(type(lsp_scala_spec) == 'table' and type(lsp_scala_spec[1]) == 'table', 'lsp-scala must return a valid lazy.nvim spec table')
  assert(lsp_scala_spec[1][1] == 'scalameta/nvim-metals', 'lsp-scala spec must declare scalameta/nvim-metals')
  local dap_devops_ok, dap_devops_spec = pcall(require, 'tetravim.plugins.tools-dap-devops')
  assert(dap_devops_ok, 'tetravim.plugins.tools-dap-devops failed to load: ' .. tostring(dap_devops_spec))
  local dap_keys = dap_devops_spec[1].keys
  local dap_key_lhs = {}
  for _, k in ipairs(dap_keys) do
    dap_key_lhs[k[1]] = true
  end
  for _, req in ipairs({'<leader>dC', '<leader>dL', '<leader>dE', '<leader>dv'}) do
    assert(dap_key_lhs[req], 'Missing DAP keymap: ' .. req)
  end

  -- Robust Conform spec lookup
  local conform_plugins = require('tetravim.plugins.tools-formatting')
  local formatters_by_ft = nil
  for _, plugin in ipairs(conform_plugins) do
    if plugin.opts and plugin.opts.formatters_by_ft then
      formatters_by_ft = plugin.opts.formatters_by_ft
      break
    end
  end
  assert(formatters_by_ft, 'conform formatters_by_ft not found')
  assert(formatters_by_ft.terraform[1] == 'terraform_fmt', 'terraform_fmt not mapped')

  -- Story 9.1: DevOps Root & Workspace Discovery Engine
  assert(type(devops.find_tf_root) == 'function', 'find_tf_root not found')
  assert(type(devops.find_cfn_root) == 'function', 'find_cfn_root not found')
  assert(type(devops.find_ansible_root) == 'function', 'find_ansible_root not found')
  assert(type(devops.find_docker_root) == 'function', 'find_docker_root not found')
  assert(type(devops.find_helm_root) == 'function', 'find_helm_root not found')

  -- Native root discovery is exercised against a real temporary workspace tree.
  local tmp_root = vim.fs.normalize(vim.fn.tempname())
  vim.fn.mkdir(tmp_root, 'p')

  -- 1. Terraform discovery
  local tf_proj = tmp_root .. '/tf_proj'
  local tf_mod = tf_proj .. '/infra/terraform/modules/vpc'
  vim.fn.mkdir(tf_mod, 'p')
  vim.fn.writefile({'resource "vpc" {}'}, tf_mod .. '/vpc.tf')
  vim.fn.writefile({'terraform {}'}, tf_proj .. '/infra/terraform/main.tf')
  local tf_from_file = devops.find_tf_root(tf_mod .. '/vpc.tf')
  assert(tf_from_file == tf_mod, 'Terraform root from child buffer mismatch: ' .. tostring(tf_from_file))
  local tf_from_root = devops.find_tf_root(tf_proj)
  assert(tf_from_root == tf_proj .. '/infra/terraform', 'Terraform root convention scan mismatch: ' .. tostring(tf_from_root))

  -- 2. CloudFormation / SAM discovery
  local cfn_proj = tmp_root .. '/cfn_proj'
  vim.fn.mkdir(cfn_proj .. '/src', 'p')
  vim.fn.writefile({'AWSTemplateFormatVersion: 2010-09-09'}, cfn_proj .. '/template.yaml')
  vim.fn.writefile({'version = 0.1'}, cfn_proj .. '/samconfig.toml')
  local cfn_from_root = devops.find_cfn_root(cfn_proj)
  assert(cfn_from_root == cfn_proj, 'CFN root mismatch: ' .. tostring(cfn_from_root))
  local cfn_from_child = devops.find_cfn_root(cfn_proj .. '/src/app.py')
  assert(cfn_from_child == cfn_proj, 'CFN root from child mismatch: ' .. tostring(cfn_from_child))

  -- 3. Ansible discovery
  local ans_proj = tmp_root .. '/ans_proj'
  local ans_pb = ans_proj .. '/playbooks'
  vim.fn.mkdir(ans_pb, 'p')
  vim.fn.writefile({'[defaults]'}, ans_proj .. '/ansible.cfg')
  vim.fn.writefile({'- hosts: all'}, ans_pb .. '/site.yml')
  local ans_from_root = devops.find_ansible_root(ans_proj)
  assert(ans_from_root == ans_proj, 'Ansible root mismatch: ' .. tostring(ans_from_root))
  local ans_from_pb = devops.find_ansible_root(ans_pb .. '/site.yml')
  assert(ans_from_pb == ans_pb, 'Ansible root from playbook mismatch: ' .. tostring(ans_from_pb))

  -- 4. Docker discovery
  local doc_proj = tmp_root .. '/doc_proj'
  vim.fn.mkdir(doc_proj .. '/src', 'p')
  vim.fn.writefile({'FROM alpine'}, doc_proj .. '/Dockerfile')
  vim.fn.writefile({'services: {}'}, doc_proj .. '/docker-compose.yml')
  local doc_from_root = devops.find_docker_root(doc_proj)
  assert(doc_from_root == doc_proj, 'Docker root mismatch: ' .. tostring(doc_from_root))
  local doc_from_child = devops.find_docker_root(doc_proj .. '/src/main.go')
  assert(doc_from_child == doc_proj, 'Docker root from child mismatch: ' .. tostring(doc_from_child))

  -- 5. Helm discovery
  local helm_proj = tmp_root .. '/helm_proj'
  local helm_chart = helm_proj .. '/charts/web-service'
  vim.fn.mkdir(helm_chart .. '/templates', 'p')
  vim.fn.writefile({'apiVersion: v2', 'name: web-service'}, helm_chart .. '/Chart.yaml')
  vim.fn.writefile({'replicaCount: 1'}, helm_chart .. '/values.yaml')
  local helm_from_root = devops.find_helm_root(helm_proj)
  assert(helm_from_root == helm_chart, 'Helm root from workspace mismatch: ' .. tostring(helm_from_root))
  local helm_from_tpl = devops.find_helm_root(helm_chart .. '/templates/deployment.yaml')
  assert(helm_from_tpl == helm_chart, 'Helm root from template mismatch: ' .. tostring(helm_from_tpl))

  -- 6. Non-DevOps workspace & fallback
  local empty_proj = tmp_root .. '/empty_proj'
  vim.fn.mkdir(empty_proj, 'p')
  vim.fn.writefile({'# Readme'}, empty_proj .. '/README.md')
  assert(devops.find_tf_root(empty_proj) == nil, 'find_tf_root should be nil for empty workspace')
  assert(devops.find_cfn_root(empty_proj) == nil, 'find_cfn_root should be nil for empty workspace')
  assert(devops.find_ansible_root(empty_proj) == nil, 'find_ansible_root should be nil for empty workspace')
  assert(devops.find_docker_root(empty_proj) == nil, 'find_docker_root should be nil for empty workspace')
  assert(devops.find_helm_root(empty_proj) == nil, 'find_helm_root should be nil for empty workspace')
  assert(devops.find_tf_root(999999) == nil or type(devops.find_tf_root(999999)) == 'string', 'find_tf_root invalid buffer must not error')

  -- JVM project detection (native vim.fs marker scan)
  local jvm = require('tetravim.util.jvm')
  local maven_util = require('tetravim.util.maven')
  local gradle_util = require('tetravim.util.gradle')
  assert(type(jvm.is_jvm_project) == 'function', 'jvm.is_jvm_project not found')

  local jvm_proj = tmp_root .. '/jvm_proj'
  vim.fn.mkdir(jvm_proj, 'p')
  vim.fn.writefile({'<project></project>'}, jvm_proj .. '/pom.xml')
  assert(jvm.is_jvm_project(jvm_proj) == true, 'is_jvm_project should return true for maven repo')
  assert(maven_util.find_pom(jvm_proj) == true, 'find_pom should return true for maven repo')
  assert(gradle_util.find_gradle(jvm_proj) == false, 'find_gradle should return false for maven repo')
  assert(jvm.is_jvm_project(empty_proj) == false, 'is_jvm_project should return false for empty repo')

  -- 7. Verify Root Adoption in Runner Execution & Warning Toasts
  local last_executed_cmd, last_executed_opts = nil, nil
  local orig_run_term = devops.run_term
  devops.run_term = function(cmd, opts)
    last_executed_cmd = cmd
    last_executed_opts = opts
  end

  local last_notify_msg, last_notify_level = nil, nil
  local orig_notify = vim.notify
  vim.notify = function(msg, level, opts)
    last_notify_msg = msg
    last_notify_level = level
  end

  -- Test Terraform adoption & missing notification
  local orig_get_tf_cmd = devops.get_tf_cmd
  devops.get_tf_cmd = function() return 'tofu' end
  local orig_find_tf_root = devops.find_tf_root
  devops.find_tf_root = function() return '/mock/tf/root' end
  devops.terraform_init()
  assert(last_executed_cmd == 'tofu init', 'terraform_init command mismatch')
  assert(last_executed_opts and last_executed_opts.cwd == '/mock/tf/root', 'terraform_init cwd not adopted: ' .. vim.inspect(last_executed_opts))

  -- Test Missing TF workspace warning
  devops.find_tf_root = function() return nil end
  last_executed_cmd = nil
  last_notify_msg = nil
  devops.terraform_plan()
  assert(last_executed_cmd == nil, 'terraform_plan should not execute when no root is found')
  assert(last_notify_msg:match('No Terraform/OpenTofu configuration found in workspace'), 'Missing TF warning toast: ' .. tostring(last_notify_msg))

  -- Test Ansible adoption & missing notification
  local orig_find_ansible_root = devops.find_ansible_root
  devops.find_ansible_root = function() return '/mock/ansible/root' end
  devops.ansible_inventory_graph()
  assert(last_executed_cmd == 'ansible-inventory --graph', 'ansible_inventory_graph command mismatch')
  assert(last_executed_opts and last_executed_opts.cwd == '/mock/ansible/root', 'ansible_inventory_graph cwd not adopted: ' .. vim.inspect(last_executed_opts))

  devops.find_ansible_root = function() return nil end
  last_executed_cmd = nil
  last_notify_msg = nil
  devops.ansible_syntax_check()
  assert(last_executed_cmd == nil, 'ansible_syntax_check should not execute when no root is found')
  assert(last_notify_msg:match('No Ansible configuration found in workspace'), 'Missing Ansible warning toast: ' .. tostring(last_notify_msg))

  -- Test Docker adoption & missing notification
  local orig_find_docker_root = devops.find_docker_root
  devops.find_docker_root = function() return '/mock/docker/my-app' end
  devops.docker_build()
  assert(last_executed_cmd:match('docker build %-t \'my%-app\' %.'), 'docker_build command mismatch: ' .. tostring(last_executed_cmd))
  assert(last_executed_opts and last_executed_opts.cwd == '/mock/docker/my-app', 'docker_build cwd not adopted')

  devops.find_docker_root = function() return nil end
  last_executed_cmd = nil
  last_notify_msg = nil
  devops.docker_build()
  assert(last_executed_cmd == nil, 'docker_build should not execute when no root is found')
  assert(last_notify_msg:match('No Docker configuration found in workspace'), 'Missing Docker warning toast: ' .. tostring(last_notify_msg))

  -- Test Helm adoption & missing notification
  local orig_find_helm_root = devops.find_helm_root
  devops.find_helm_root = function() return '/mock/helm/my-chart' end
  devops.helm_lint()
  assert(last_executed_cmd == 'helm lint .', 'helm_lint command mismatch: ' .. tostring(last_executed_cmd))
  assert(last_executed_opts and last_executed_opts.cwd == '/mock/helm/my-chart', 'helm_lint cwd not adopted')

  devops.find_helm_root = function() return nil end
  last_executed_cmd = nil
  last_notify_msg = nil
  devops.helm_lint()
  assert(last_executed_cmd == nil, 'helm_lint should not execute when no root is found')
  assert(last_notify_msg:match('No Helm configuration found in workspace'), 'Missing Helm warning toast: ' .. tostring(last_notify_msg))

  -- Test CloudFormation / SAM missing notification
  local orig_find_cfn_root = devops.find_cfn_root
  devops.find_cfn_root = function() return nil end
  last_executed_cmd = nil
  last_notify_msg = nil
  devops.sam_validate()
  assert(last_executed_cmd == nil, 'sam_validate should not execute when no root is found')
  assert(last_notify_msg:match('No CloudFormation/SAM configuration found in workspace'), 'Missing CFN warning toast: ' .. tostring(last_notify_msg))

  -- Restore mocks
  devops.run_term = orig_run_term
  vim.notify = orig_notify
  devops.get_tf_cmd = orig_get_tf_cmd
  devops.find_tf_root = orig_find_tf_root
  devops.find_ansible_root = orig_find_ansible_root
  devops.find_docker_root = orig_find_docker_root
  devops.find_helm_root = orig_find_helm_root
  devops.find_cfn_root = orig_find_cfn_root

  -- Story 1.2: Continuous Profiling
  local profiling = require('tetravim.util.profiling')
  assert(type(profiling.start) == 'function', 'profiling.start not found')
  assert(type(profiling.stop) == 'function', 'profiling.stop not found')
  assert(type(profiling.view) == 'function', 'profiling.view not found')

  -- Verify jvm profiling keymaps
  local jvm_wk = jvm.whichkey_spec()
  local jvm_groups = {}
  for _, item in ipairs(jvm_wk) do
    jvm_groups[item[1]] = item.group
  end
  assert(jvm_groups['<leader>jp'] == 'profiling', '<leader>jp missing in jvm whichkey_spec')
  assert(jvm_groups['<leader>jc'] == 'code coverage', '<leader>jc missing in jvm whichkey_spec')
  assert(jvm_groups['<leader>jt'] == 'test runner', '<leader>jt missing in jvm whichkey_spec')

  -- Verify actual keymap registration
  jvm.setup_keymaps()
  assert(vim.fn.maparg('<leader>jps', 'n') ~= '', '<leader>jps keymap not registered')
  assert(vim.fn.maparg('<leader>jpx', 'n') ~= '', '<leader>jpx keymap not registered')
  assert(vim.fn.maparg('<leader>jpv', 'n') ~= '', '<leader>jpv keymap not registered')
  assert(vim.fn.maparg('<leader>jcl', 'n') ~= '', '<leader>jcl keymap not registered')
  assert(vim.fn.maparg('<leader>jcx', 'n') ~= '', '<leader>jcx keymap not registered')
  assert(vim.fn.maparg('<leader>jct', 'n') ~= '', '<leader>jct keymap not registered')
  assert(vim.fn.maparg('<leader>jcs', 'n') ~= '', '<leader>jcs keymap not registered')
  assert(vim.fn.maparg('<leader>jtt', 'n') ~= '', '<leader>jtt keymap not registered')
  assert(vim.fn.maparg('<leader>jtc', 'n') ~= '', '<leader>jtc keymap not registered')
  assert(vim.fn.maparg('<leader>jta', 'n') ~= '', '<leader>jta keymap not registered')

  -- Cleanup temporary workspace
  vim.fn.delete(tmp_root, 'rf')

  print('✔ Native DevOps WhichKey, scoped buffers, Mason tooling, Workspace Root Discovery, Global Root Execution with Warning Toasts & JVM Debugger DAP (Scala/Metals) verified')
end)
if not ok then
  io.stderr:write('FAIL: ' .. tostring(err) .. '\n')
  vim.cmd('cquit 1')
end
" -c "qa!"
echo "✔ Native DevOps suite PASSED."

echo "[6.1/7] Verifying Coverage Unit Specs (test_coverage_spec.lua)..."
if nvim --headless -u init.lua \
  -c "lua require('plenary.busted')" \
  -c "PlenaryBustedDirectory lua/tetravim/tests/test_coverage_spec.lua" \
  -c "qa"; then
  echo "✔ Coverage unit specs PASSED."
else
  echo "✖ Coverage unit specs FAILED."
  exit 1
fi

echo "[7/7] Verifying Visual Test Runner & JaCoCo Coverage (SPEC-1.3)..."
if bash scripts/validate-test-coverage.sh; then
  echo "✔ Test runner & coverage suite PASSED."
else
  echo "✖ Test runner & coverage suite FAILED."
  exit 1
fi

echo "=========================================="
echo " ALL VALIDATIONS PASSED SUCCESSFULLY!"
echo "=========================================="

