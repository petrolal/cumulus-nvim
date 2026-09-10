-- TetraVim Healthcheck -- Git conflict resolution, code reviews, test runner, linting, SonarLint, CVE, template engines, profiler
-- Carved out of the former monolithic lua/tetravim/health.lua
-- (Story 27.2 / Story 35.1 / Story 6.1). Orchestrated by health/init.lua;
-- sections run in the original order so :checkhealth output is unchanged.

local M = {}

function M.check()
  vim.health.start("TetraVim Advanced Git Conflict Resolution")

  if vim.fn.executable("git") == 1 then
    local git_ok, git_res = pcall(function()
      return vim.system({ "git", "--version" }, { text = true, timeout = 2000 }):wait()
    end)

    local stdout
    if git_ok and type(git_res) == "table" and git_res.code == 0 then
      stdout = git_res.stdout or ""
    end
    local major, minor = (stdout or ""):match("(%d+)%.(%d+)")
    major, minor = tonumber(major), tonumber(minor)

    if not major then
      vim.health.warn(
        "git: installed, but `git --version` did not return a recognizable version -- ensure it is git >= 2.30"
      )
    elseif major > 2 or (major == 2 and minor >= 30) then
      vim.health.ok(string.format("git: installed (v%d.%d; >= 2.30 advised)", major, minor))
    else
      vim.health.warn(
        string.format("git: v%d.%d found -- git >= 2.30 is advised for the merge-conflict workflow", major, minor)
      )
    end
  else
    vim.health.error(
      "git: NOT found on $PATH -- the <leader>gc conflict/compare commands are unavailable. Suggestion: install git"
    )
  end

  -- Distinguish "diffview.nvim is not installed at all" (an error the user
  -- fixes with :Lazy install) from "installed but not yet lazy-loaded" (a
  -- benign warn -- pressing <leader>gco loads it).
  local lz_ok, lz_cfg = pcall(require, "lazy.core.config")
  local diffview_plugin = lz_ok and lz_cfg.plugins and lz_cfg.plugins["diffview.nvim"] or nil
  if not diffview_plugin then
    vim.health.error(
      "diffview.nvim: not installed -- run :Lazy install (spec lives in lua/tetravim/plugins/tools-diffview.lua)"
    )
  elseif not package.loaded["diffview"] then
    vim.health.warn(
      "diffview.nvim: installed but not yet lazy-loaded -- press <leader>gco / run :DiffviewOpen to load it"
    )
  else
    vim.health.ok("diffview.nvim: loaded (3-way merge tool & file-history engine available)")
  end

  -- diffview.nvim's hard dependency -- without it diffview cannot load at all.
  if pcall(require, "plenary") then
    vim.health.ok("plenary.nvim: resolvable (diffview.nvim's hard dependency)")
  else
    vim.health.warn("plenary.nvim: not resolvable -- diffview's hard dependency; run :Lazy sync")
  end

  vim.health.start("TetraVim Code Reviews (GitHub/GitLab)")
  if vim.fn.executable("gh") == 1 then
    vim.health.ok("gh: installed and executable (GitHub PR review support available)")
  else
    vim.health.info("gh: NOT found on $PATH (GitHub PR review support unavailable). Suggestion: install gh")
  end
  if vim.fn.executable("glab") == 1 then
    vim.health.ok("glab: installed and executable (GitLab PR review support available)")
  else
    vim.health.info("glab: NOT found on $PATH (GitLab PR review support unavailable). Suggestion: install glab")
  end

  vim.health.start("TetraVim Visual Test Runner -- neotest-java")

  if pcall(require, "neotest-java") then
    vim.health.ok("neotest-java: resolvable (JVM test tree discovery available)")
  else
    vim.health.info("neotest-java: not resolvable -- open a java buffer to lazy-load it, or run :Lazy sync")
  end

  local njava_ok, njava = pcall(require, "tetravim.util.neotest_java")
  if njava_ok then
    if njava.is_installed() then
      vim.health.ok(
        string.format("JUnit Platform Console Standalone %s: present (%s)", njava.version, njava.jar_path())
      )
    elseif vim.fn.executable("curl") == 1 then
      vim.health.info(
        "JUnit Platform Console Standalone jar: not downloaded yet -- fetched automatically on first test run "
          .. "(or run :NeotestJava setup)"
      )
    else
      vim.health.warn(
        "JUnit Platform Console Standalone jar: missing and curl is unavailable -- install curl or download it manually"
      )
    end
  else
    vim.health.error("tetravim.util.neotest_java: failed to load (" .. tostring(njava) .. ")")
  end

  if njava_ok then
    if njava.has_java_sources(vim.fn.getcwd()) then
      vim.health.ok("Current project: has .java sources -- neotest-java adapter is active here")
    else
      vim.health.info(
        "Current project: no .java sources found -- neotest-java stays inactive here (it is Java-only; "
          .. "Kotlin/Groovy route through tetravim.util.jvm_test, Scala through neotest-scala)"
      )
    end
  end

  if pcall(require, "neotest-scala") then
    vim.health.ok("neotest-scala: resolvable (Scala test tree discovery available)")
  else
    vim.health.info("neotest-scala: not resolvable -- open a scala buffer to lazy-load it, or run :Lazy sync")
  end

  -- Kotlin / Groovy have no neotest adapter here; tetravim.util.jvm_test runs
  -- their tests straight through the build wrapper and parses the JUnit XML.
  local jvmtest_ok = pcall(require, "tetravim.util.jvm_test")
  if jvmtest_ok then
    local cwd = vim.fn.getcwd()
    local has_gradle = vim.fn.executable("gradle") == 1 or vim.fn.filereadable(cwd .. "/gradlew") == 1
    local has_maven = vim.fn.executable("mvn") == 1 or vim.fn.filereadable(cwd .. "/mvnw") == 1
    if has_gradle or has_maven then
      vim.health.ok("tetravim.util.jvm_test: build wrapper reachable (Kotlin/Groovy test running available)")
    else
      vim.health.info(
        "tetravim.util.jvm_test: loaded, but no gradle/mvn on $PATH and no wrapper in cwd -- "
          .. "Kotlin/Groovy test running needs one"
      )
    end
  else
    vim.health.error("tetravim.util.jvm_test: failed to load")
  end

  vim.health.start("TetraVim JVM & Diagnostic Linting -- nvim-lint")

  if pcall(require, "lint") then
    vim.health.ok("nvim-lint: loaded (auto-lint on BufWritePost/BufEnter; toggle with <leader>ul / <leader>uL)")
  else
    vim.health.info("nvim-lint: not loaded yet -- open a lintable buffer to lazy-load it, or run :Lazy sync")
  end

  for _, l in ipairs({
    { bin = "checkstyle", ft = "Java", install = ":MasonInstall checkstyle" },
    { bin = "ktlint", ft = "Kotlin", install = ":MasonInstall ktlint" },
    { bin = "npm-groovy-lint", ft = "Groovy", install = ":MasonInstall npm-groovy-lint or npm i -g npm-groovy-lint" },
  }) do
    if vim.fn.executable(l.bin) == 1 then
      vim.health.ok(("%s: installed and executable (%s linting on save)"):format(l.bin, l.ft))
    else
      vim.health.info(("%s: NOT found on $PATH (%s linting disabled). Suggestion: %s"):format(l.bin, l.ft, l.install))
    end
  end

  -- Scala: Metals already provides semantic diagnostics; scalastyle is the
  -- optional style linter (not in Mason -- install via coursier) and needs a
  -- rules file, scalafmt is the formatter used by conform + <leader>xlF.
  local tvlint_ok, tvlint = pcall(require, "tetravim.util.lint")
  if vim.fn.executable("scalastyle") == 1 then
    local cfg = tvlint_ok and tvlint.scalastyle_config() or nil
    if cfg then
      vim.health.ok("scalastyle: installed + config found (" .. vim.fn.fnamemodify(cfg, ":~:.") .. ")")
    else
      vim.health.info(
        "scalastyle: installed but no scalastyle-config.xml up-tree -- add one to enable Scala style linting"
      )
    end
  else
    vim.health.info(
      "scalastyle: NOT found on $PATH (optional Scala style linter). Suggestion: coursier install scalastyle"
    )
  end
  if vim.fn.executable("scalafmt") == 1 then
    vim.health.ok("scalafmt: installed and executable (Scala formatting via conform + <leader>xlF)")
  else
    vim.health.info(
      "scalafmt: NOT found on $PATH (Scala falls back to Metals LSP formatting). Suggestion: coursier install scalafmt"
    )
  end

  -- Buffer autofix <leader>xlf / project-wide <leader>xlp (check) / <leader>xlF (fix)
  if tvlint_ok and type(tvlint.project_plan) == "function" then
    local can_check = #tvlint.project_plan("check")
    local can_fix = #tvlint.project_plan("fix")
    vim.health.ok(
      ("Project lint: <leader>xlp can run %d checker(s), <leader>xlF can run %d fixer(s) in this repo"):format(
        can_check,
        can_fix
      )
    )
    if type(tvlint.buffer_fix_argv) == "table" then
      local fts = vim.tbl_keys(tvlint.buffer_fix_argv)
      table.sort(fts)
      vim.health.ok(
        ("Buffer autofix: <leader>xlf rewrites the current file for filetype(s) %s"):format(table.concat(fts, ", "))
      )
    end
  end

  vim.health.start("TetraVim Code Quality & Security -- SonarLint")

  local sonar = require("tetravim.util.sonar")
  if sonar.has_language_server() then
    vim.health.ok("sonarlint-language-server: installed and executable (Java/Kotlin/Scala SonarQube-rule diagnostics)")
    local jars = sonar.analyzer_paths()
    if #jars > 0 then
      vim.health.ok(string.format("SonarLint analyzers: %d bundled jar(s) found under the Mason package", #jars))
    else
      vim.health.info(
        "SonarLint analyzers: none bundled with the Mason package -- standalone analysis relies on connected mode "
          .. "or the language server's own defaults"
      )
    end
  else
    vim.health.info(
      "sonarlint-language-server: NOT found on $PATH (SonarQube-rule diagnostics unavailable). "
        .. "Suggestion: :MasonInstall sonarlint-language-server"
    )
  end

  if pcall(require, "sonarlint") then
    vim.health.ok("sonarlint.nvim: resolvable (SonarLint LS bridge available)")
  else
    vim.health.info(
      "sonarlint.nvim: not resolvable -- open a java/kotlin/scala buffer to lazy-load it, or run :Lazy sync"
    )
  end

  local sonar_props = sonar.find_project_settings()
  if sonar_props and sonar_props["sonar.projectKey"] then
    vim.health.ok(
      "sonar-project.properties: found (quality profile bound to '" .. sonar_props["sonar.projectKey"] .. "')"
    )
  else
    vim.health.info("sonar-project.properties: not found in the current directory (SonarLint default rules apply)")
  end

  -- Whole-codebase analysis (<leader>xsp / :TetraVimSonarScan).
  local backend = sonar.choose_backend(sonar_props, sonar.has_scanner())
  if sonar.has_scanner() then
    vim.health.ok("sonar-scanner: installed and executable (connected-mode project scan available)")
  else
    vim.health.info(
      "sonar-scanner: NOT found on $PATH -- <leader>xsp falls back to a server-free SonarLint sweep. "
        .. "Suggestion: npm install -g sonarqube-scanner, or a release from "
        .. "https://docs.sonarsource.com/sonarqube-server/analyzing-source-code/scanners/sonarscanner/"
    )
  end
  local n_sources = #sonar.collect_sources()
  vim.health.ok(
    ("Project scan: <leader>xsp will use the '%s' backend here (%d Java/Kotlin/Scala source(s) in this repo)"):format(
      backend,
      n_sources
    )
  )

  vim.health.info("Scala SonarLint rules require SonarQube connected mode -- no standalone Scala analyzer is bundled")

  vim.health.start("TetraVim Code Quality & Security -- CVE Scanning")

  if vim.fn.executable("osv-scanner") == 1 then
    vim.health.ok(
      "osv-scanner: installed and executable (<leader>xvb build-file + <leader>xvp whole-project CVE scan available)"
    )
  else
    vim.health.info(
      "osv-scanner: NOT found on $PATH (the <leader>xvb / <leader>xvp dependency CVE scans are unavailable). "
        .. "Suggestion: brew install osv-scanner / go install github.com/google/osv-scanner/cmd/osv-scanner@latest"
    )
  end

  vim.health.start("TetraVim Template Engines (FreeMarker / Velocity / JSP)")

  -- No OSS language server or Tree-sitter grammar exists for any of these three;
  -- TetraVim covers them with filetype detection, a bundled/hand-rolled syntax
  -- layer, ftplugin conventions and emmet. See docs/ide-parity.md
  -- ("Template engines").
  for _, t in ipairs({
    { file = "x.ftl", want = "freemarker" },
    { file = "x.ftlh", want = "freemarker" },
    { file = "x.vm", want = "velocity" },
    { file = "x.jsp", want = "jsp" },
    { file = "x.jspf", want = "jsp" },
  }) do
    local got = vim.filetype.match({ filename = t.file })
    if got == t.want then
      vim.health.ok(("filetype: %s -> %s"):format(t.file, got))
    else
      vim.health.warn(
        ("filetype: %s -> %s (expected %s) -- lang-templates.lua not loaded?"):format(t.file, tostring(got), t.want)
      )
    end
  end

  for _, name in ipairs({ "freemarker", "velocity" }) do
    if #vim.api.nvim_get_runtime_file("syntax/" .. name .. ".vim", false) > 0 then
      vim.health.ok(("syntax/%s.vim: on runtimepath (HTML-embedded directive highlighting)"):format(name))
    else
      vim.health.warn(("syntax/%s.vim: NOT on runtimepath -- .%s files fall back to plain text"):format(name, name))
    end
  end
  if #vim.api.nvim_get_runtime_file("syntax/jsp.vim", false) > 0 then
    vim.health.ok("syntax/jsp.vim: available (Neovim bundled -- HTML + embedded Java)")
  else
    vim.health.info("syntax/jsp.vim: not found (unexpected -- ships with Neovim)")
  end

  for _, name in ipairs({ "freemarker", "velocity", "jsp" }) do
    if #vim.api.nvim_get_runtime_file("ftplugin/" .. name .. ".lua", false) > 0 then
      vim.health.ok(("ftplugin/%s.lua: directive-aware commentstring + matchit block pairs"):format(name))
    else
      vim.health.warn(("ftplugin/%s.lua: missing -- no directive-aware comments for .%s"):format(name, name))
    end
  end

  vim.health.info(
    "No language server / Tree-sitter parser for FreeMarker / Velocity / JSP -- none exists in the "
      .. "OSS ecosystem. Coverage is syntax + comments + matchit + emmet by design."
  )

  vim.health.start("TetraVim JVM Continuous Profiling -- async-profiler")

  local profiler_ok, profiling = pcall(require, "tetravim.util.profiling")
  local profiler_found = profiler_ok and profiling.profiler_cmd()
  if profiler_found then
    vim.health.ok(
      ("%s: installed and executable (<leader>jps start / <leader>jpx stop / <leader>jpv view available)"):format(
        profiler_found
      )
    )
  else
    vim.health.info(
      "async-profiler: NOT found on $PATH (looked for 'asprof', 'profiler.sh', 'async-profiler'). "
        .. "The <leader>jp profiling keymaps error until it is installed. "
        .. "Suggestion: run `bash bootstrap.sh`, or grab a release from "
        .. "https://github.com/async-profiler/async-profiler/releases"
    )
  end

  if profiler_ok and type(profiling.capture) == "function" then
    if vim.fn.executable("jps") == 1 then
      vim.health.ok("jps: available -- <leader>jpp picks a running JVM and renders an interactive flamegraph call tree")
    else
      vim.health.info("jps: NOT found on $PATH (ships with the JDK) -- <leader>jpp falls back to a manual PID prompt")
    end
  end

  if vim.fn.has("mac") == 0 and vim.fn.filereadable("/proc/sys/kernel/perf_event_paranoid") == 1 then
    local paranoid = tonumber((vim.fn.readfile("/proc/sys/kernel/perf_event_paranoid")[1] or ""):match("%-?%d+"))
    if paranoid and paranoid <= 1 then
      vim.health.ok(("kernel.perf_event_paranoid=%d (async-profiler can sample a running JVM)"):format(paranoid))
    elseif paranoid then
      vim.health.warn(
        ("kernel.perf_event_paranoid=%d -- async-profiler needs <= 1 to sample the JVM. "):format(paranoid)
          .. "Run: sudo sysctl kernel.perf_event_paranoid=1 kernel.kptr_restrict=0"
      )
    end
  end
end

return M
