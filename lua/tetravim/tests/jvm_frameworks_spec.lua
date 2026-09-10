-- JVM framework config LSP wiring -- util/jvm_frameworks path + readiness
-- resolution (Spring Boot / Quarkus / MicroProfile).
--
-- Behavioural assertions that need the plugins actually loaded (quarkus.nvim /
-- microprofile.nvim launch, jdtls bundle extension) are NOT exercised here: the
-- plenary busted subprocess has no third-party plugins on its runtimepath and
-- forcing require("lazy").load() corrupts lazy's internal state (see
-- dap_jvm_spec.lua). Verify those manually per the story's Verification section.

local fw = require("tetravim.util.jvm_frameworks")

local function tmpdir()
  local d = vim.fn.tempname()
  vim.fn.mkdir(d, "p")
  return d
end

local function touch(path)
  vim.fn.mkdir(vim.fn.fnamemodify(path, ":h"), "p")
  local fh = assert(io.open(path, "w"))
  fh:close()
end

describe("tetravim.util.jvm_frameworks", function()
  local saved

  before_each(function()
    saved = vim.env.TETRAVIM_JVM_LSP_DIR
  end)

  after_each(function()
    vim.env.TETRAVIM_JVM_LSP_DIR = saved
  end)

  it("honours the TETRAVIM_JVM_LSP_DIR override", function()
    local d = tmpdir()
    vim.env.TETRAVIM_JVM_LSP_DIR = d
    assert.are.equal(d, fw.dir())
  end)

  it("falls back to stdpath('data')/tetravim/jvm-lsp with no override", function()
    vim.env.TETRAVIM_JVM_LSP_DIR = nil
    assert.are.equal(vim.fn.stdpath("data") .. "/tetravim/jvm-lsp", fw.dir())
  end)

  it("reports not-ready when the jar dir is empty", function()
    vim.env.TETRAVIM_JVM_LSP_DIR = tmpdir()
    assert.is_nil(fw.quarkus_paths())
    assert.is_nil(fw.microprofile_paths())
    assert.is_false(fw.quarkus_ready())
  end)

  it("resolves quarkus_paths once both Qute + Quarkus LS jars are present", function()
    local d = tmpdir()
    vim.env.TETRAVIM_JVM_LSP_DIR = d
    touch(d .. "/quarkus/server/com.redhat.qute.ls-uber.jar")
    assert.is_nil(fw.quarkus_paths()) -- needs quarkus.ls too
    touch(d .. "/quarkus/server/com.redhat.quarkus.ls.jar")

    local qp = fw.quarkus_paths()
    assert.is_table(qp)
    assert.are.equal(d .. "/quarkus/server", qp.ls_path)
    assert.are.equal(d .. "/quarkus/jars", qp.jdt_extensions_path)
    assert.are.equal(d .. "/quarkus/server", qp.microprofile_ext_path)
  end)

  it("resolves microprofile_paths once the lsp4mp uber jar is present", function()
    local d = tmpdir()
    vim.env.TETRAVIM_JVM_LSP_DIR = d
    touch(d .. "/microprofile/server/org.eclipse.lsp4mp.ls-uber.jar")

    local mp = fw.microprofile_paths()
    assert.is_table(mp)
    assert.are.equal(d .. "/microprofile/server", mp.ls_path)
    assert.are.equal(d .. "/microprofile/jars", mp.jdt_extensions_path)
  end)

  it("quarkus_ready needs BOTH the quarkus and microprofile bundles", function()
    local d = tmpdir()
    vim.env.TETRAVIM_JVM_LSP_DIR = d
    touch(d .. "/quarkus/server/com.redhat.qute.ls-uber.jar")
    touch(d .. "/quarkus/server/com.redhat.quarkus.ls.jar")
    assert.is_false(fw.quarkus_ready()) -- microprofile bundle still missing
    touch(d .. "/microprofile/server/org.eclipse.lsp4mp.ls-uber.jar")
    assert.is_true(fw.quarkus_ready())
  end)

  it("exposes the full readiness API surface", function()
    for _, name in ipairs({
      "dir",
      "java_cmd",
      "quarkus_paths",
      "microprofile_paths",
      "quarkus_ready",
      "spring_boot_ls_jar",
      "spring_boot_ready",
      "fetch_jars",
    }) do
      assert.are.equal("function", type(fw[name]), name .. " missing")
    end
  end)

  it("java_cmd returns nil or an executable path, never a broken string", function()
    local cmd = fw.java_cmd()
    if cmd ~= nil then
      assert.are.equal(1, vim.fn.executable(cmd))
    end
  end)
end)

describe("JVM framework plugin specs (static shape)", function()
  local function read(path)
    local fh = assert(io.open(path, "r"))
    local body = fh:read("*a")
    fh:close()
    return body
  end

  it("lsp-spring-boot.lua declares spring-boot.nvim + the properties parser", function()
    local body = read("lua/tetravim/plugins/lsp-spring-boot.lua")
    assert.is_truthy(body:match("JavaHello/spring%-boot%.nvim"))
    assert.is_truthy(body:match("lsp_capabilities"))
    assert.is_truthy(body:match('"properties"'))
  end)

  it("lsp-quarkus.lua declares quarkus.nvim + microprofile.nvim, gated on readiness", function()
    local body = read("lua/tetravim/plugins/lsp-quarkus.lua")
    assert.is_truthy(body:match("JavaHello/quarkus%.nvim"))
    assert.is_truthy(body:match("JavaHello/microprofile%.nvim"))
    assert.is_truthy(body:match("quarkus_paths"))
    assert.is_truthy(body:match("microprofile_paths"))
  end)

  it("ftplugin/java.lua folds framework java_extensions() into the jdtls bundles", function()
    local body = read("ftplugin/java.lua")
    assert.is_truthy(body:match("java_extensions"))
    assert.is_truthy(body:match("spring_boot"))
    assert.is_truthy(body:match("microprofile"))
    assert.is_truthy(body:match("quarkus"))
  end)

  it("tools-mason.lua ensures the Spring Boot language server", function()
    assert.is_truthy(read("lua/tetravim/plugins/tools-mason.lua"):match("vscode%-spring%-boot%-tools"))
  end)

  it("health.lua has the JVM Framework Config LSP section", function()
    assert.is_truthy(read("lua/tetravim/health.lua"):match("JVM Framework Config LSP"))
  end)

  it("lsp-quarkus.lua declares TetraVimFetchJvmLspJars command", function()
    local body = read("lua/tetravim/plugins/lsp-quarkus.lua")
    assert.is_truthy(body:match("TetraVimFetchJvmLspJars"))
  end)

  it("jvm_frameworks exposes fetch_jars native function", function()
    assert.are.equal("function", type(fw.fetch_jars))
  end)
end)
