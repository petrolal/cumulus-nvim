-- TetraVim Healthcheck -- Async LSP & resilience, headless & telemetry, colourscheme, wizards, IDE-parity servers & tools, keymap hygiene
-- Carved out of the former monolithic lua/tetravim/health.lua
-- (Story 27.2 / Story 35.1 / Story 6.1). Orchestrated by health/init.lua;
-- sections run in the original order so :checkhealth output is unchanged.

local M = {}

function M.check()
  vim.health.start("TetraVim Asynchronous LSP & Resilience")

  local resilience_ok, resilience = pcall(require, "tetravim.util.lsp.resilience")
  if resilience_ok and type(resilience.health) == "function" then
    resilience.health()
  else
    vim.health.error("tetravim.util.lsp.resilience: failed to load (" .. tostring(resilience) .. ")")
  end

  -- JetBrains kotlin-lsp shares a single on-disk RocksDB workspace index and
  -- fails every request when a second intellij-server races it for the lock --
  -- lsp-kotlin.lua refuses to start a second instance (TETRAVIM_KOTLIN_LSP_FORCE
  -- overrides). Surface which state we're in.
  if
    vim.fn.executable("intellij-server") == 1
    or vim.fn.filereadable(vim.fn.stdpath("data") .. "/mason/bin/intellij-server") == 1
  then
    local another = vim.fn.executable("pgrep") == 1
      and (function()
        vim.fn.system({ "pgrep", "-f", "intellij-server" })
        return vim.v.shell_error == 0
      end)()
    if vim.env.TETRAVIM_KOTLIN_LSP_FORCE == "1" then
      vim.health.warn(
        "Kotlin LSP: TETRAVIM_KOTLIN_LSP_FORCE=1 -- lock-contention guard disabled (concurrent index locks may crash the server)"
      )
    elseif another then
      vim.health.warn(
        "Kotlin LSP: an intellij-server is already running -- a second one is suppressed to avoid a workspace-index lock crash (:LspStart kotlin_lsp after the other session exits)"
      )
    else
      vim.health.ok("Kotlin LSP: intellij-server present, no competing instance -- workspace index is free")
    end
  end

  vim.health.start("TetraVim Headless Setup & Telemetry")

  local setup_ok, setup_mod = pcall(require, "tetravim.core.setup")
  if setup_ok and type(setup_mod.run) == "function" then
    vim.health.ok("tetravim.core.setup: native provisioning pipeline available (:TetraVimSetup)")
  else
    vim.health.warn("tetravim.core.setup: failed to load")
  end

  local json_ok, core_health = pcall(require, "tetravim.core.health_json")
  if json_ok and type(core_health.json) == "function" then
    local decoded_ok = pcall(function()
      return vim.json.decode(core_health.json())
    end)
    if decoded_ok then
      vim.health.ok(
        ":CheckHealthJson emits valid machine-readable JSON (neovim_version, lsp_clients, plugin_count, ...)"
      )
    else
      vim.health.error("tetravim.core.health_json.json() did not return decodable JSON")
    end
  else
    vim.health.error("tetravim.core.health_json: failed to load or missing json()")
  end

  if vim.g.tetravim_telemetry_enabled then
    vim.health.info(
      "Telemetry is ENABLED -- notifications are appended to "
        .. vim.fn.stdpath("config")
        .. "/telemetry.log (toggle with :TetraVimTelemetryDisable)"
    )
  else
    vim.health.info("Telemetry is disabled (opt in with :TetraVimTelemetryEnable to export notifications as JSON)")
  end

  vim.health.start("TetraVim Colour Scheme")

  local theme_ok, tetris = pcall(require, "tetravim.theme.tetris")
  if not theme_ok then
    vim.health.error("tetravim.theme.tetris: failed to load (" .. tostring(tetris) .. ")")
  else
    local pal = tetris.palette or {}
    -- The canonical palette uses tinted (readable) versions for code text.
    -- Pure spec hexes live in cyan_pure / purple_pure (chrome / ANSI accents).
    if pal.bg == "#111216" and pal.cyan == "#4EC9D9" and pal.purple == "#C792EA" then
      vim.health.ok("Tetris palette module loaded (canonical hex values present)")
    else
      vim.health.warn("Tetris palette module loaded but hex values are not the canonical TetraVim set")
    end

    if vim.g.colors_name == "tetravim" then
      vim.health.ok("Active colourscheme: 'tetravim'")
    else
      vim.health.warn(
        "colors_name is '"
          .. tostring(vim.g.colors_name)
          .. "' (expected 'tetravim') -- run ':colorscheme tetravim' or check core/options.lua"
      )
    end
  end

  vim.health.start("TetraVim Project Generator Wizard")

  if vim.fn.executable("curl") == 1 then
    vim.health.ok("curl: installed and executable (Spring Initializr download)")
  else
    vim.health.warn("curl: NOT found on $PATH (required for Spring Initializr project generator)")
  end

  if vim.fn.executable("unzip") == 1 then
    vim.health.ok("unzip: installed and executable (Spring Initializr project unpack)")
  else
    vim.health.warn("unzip: NOT found on $PATH (required for Spring Initializr project generator)")
  end

  if vim.fn.executable("mvn") == 1 then
    vim.health.ok("mvn: installed and executable (Maven project scaffolding & build)")
  else
    vim.health.info("mvn: NOT found on $PATH (optional -- needed for Maven Archetype generator)")
  end

  if vim.fn.executable("gradle") == 1 then
    vim.health.ok("gradle: installed and executable (Gradle init project scaffolding)")
  else
    vim.health.info("gradle: NOT found on $PATH (optional -- needed for Gradle init generator)")
  end

  vim.health.start("TetraVim New File from Template (IDEA-style New)")

  do
    local ok, ft = pcall(require, "tetravim.util.edit.filetemplate")
    if not ok then
      vim.health.error("tetravim.util.edit.filetemplate: failed to load (" .. tostring(ft) .. ")")
    else
      vim.health.ok(
        ("built-in templates: %d registered (Java / Kotlin / Scala / Groovy / Web / DevOps / ...)"):format(
          ft.builtin_count()
        )
      )
      local udir = ft.user_dir()
      if vim.fn.isdirectory(udir) == 1 then
        local n = vim.tbl_count(ft.load_user_templates())
        vim.health.ok(("user templates: %d found in %s"):format(n, udir))
      else
        vim.health.info(
          "user templates: none -- drop files into " .. udir .. " to add your own (one file per template)"
        )
      end
      vim.health.info("keys: <leader>fn / <leader>n / :TetraVimNewFile")
      if vim.g.tetravim_new_file_prompt == false then
        vim.health.info("new-file skeleton prompt: disabled (vim.g.tetravim_new_file_prompt = false)")
      else
        vim.health.ok("new-file skeleton prompt: on -- opening a new empty file of a known type offers a template")
      end
    end
  end

  vim.health.start("TetraVim IDE-Parity Language Servers (Python / SQL / Web / Templates)")

  -- Executable names as exposed on $PATH once Mason installs each package
  -- (mason.nvim prepends ~/.local/share/nvim/mason/bin). mason-tool-installer
  -- fetches all of these on VimEnter, so a miss here is normal on a cold
  -- checkout -- hence info, not warn. See docs/ide-parity.md for the full map.
  local parity_servers = {
    { bin = "basedpyright-langserver", desc = "Python type checker LSP (IDEA 'Python')" },
    { bin = "ruff", desc = "Python lint + format LSP (IDEA 'Python')" },
    { bin = "sql-language-server", desc = "SQL language server (IDEA Database tools)" },
    { bin = "vue-language-server", desc = "Vue / Volar LSP (IDEA 'Vue.js')" },
    { bin = "svelteserver", desc = "Svelte LSP (IDEA 'Svelte')" },
    { bin = "astro-ls", desc = "Astro LSP (IDEA 'Astro')" },
    { bin = "ngserver", desc = "Angular LSP (IDEA 'Angular')" },
    { bin = "prisma-language-server", desc = "Prisma ORM LSP (IDEA 'Prisma ORM')" },
    { bin = "marksman", desc = "Markdown LSP -- links / headings (IDEA 'Markdown')" },
    { bin = "vscode-eslint-language-server", desc = "ESLint LSP -- diagnostics + fix-all" },
    { bin = "tailwindcss-language-server", desc = "Tailwind CSS LSP -- class completion" },
    { bin = "emmet-language-server", desc = "Emmet LSP -- abbreviation expansion" },
    { bin = "djlint", desc = "Jinja2 / Django template format + lint" },
    { bin = "ltex-ls", desc = "Natural-language grammar / style LSP (IDEA 'Grazie')" },
    { bin = "deno", desc = "Deno LSP (runtime-provided; not a Mason package)" },
  }
  for _, s in ipairs(parity_servers) do
    if vim.fn.executable(s.bin) == 1 then
      vim.health.ok(string.format("%s: installed and executable (%s)", s.bin, s.desc))
    else
      vim.health.info(string.format("%s: NOT found on $PATH (%s). Suggestion: :MasonToolsInstall", s.bin, s.desc))
    end
  end

  vim.health.start("TetraVim IDE-Parity Editor Tools (Run / TODO / Structure / History)")

  -- Pure-Lua/Vimscript plugins fetched by lazy.nvim -- no external binary, so
  -- the probe is just "did the module load". A miss means `:Lazy sync` has
  -- not run yet. See docs/ide-parity.md ("Editor / IDE tool windows").
  local editor_plugins = {
    { mod = "overseer", desc = "Generic task runner (IDEA 'Run Anything' / Run Configurations) -- <leader>r" },
    { mod = "todo-comments", desc = "TODO / FIXME scanner + list (IDEA 'TODO' tool window) -- ]t / <leader>xt" },
    { mod = "outline", desc = "Docked symbol tree (IDEA 'Structure') -- <leader>cs" },
    { mod = "grug-far", desc = "Project-wide find & replace (IDEA 'Replace in Path') -- <leader>sr" },
    { mod = "marks", desc = "Gutter marks + bookmarks (IDEA 'Bookmarks') -- m* / <leader>m" },
    { mod = "package-info", desc = "package.json version lens (IDEA npm inlays) -- <leader>cp* in package.json" },
    {
      mod = "neogen",
      desc = "Javadoc / KDoc / docstring stub generator (IDEA 'Generate... > Javadoc') -- <leader>cg / <leader>cG",
    },
    { mod = "fidget", desc = "LSP / indexing progress widget (IDEA 'indexing' status bar)" },
    { mod = "trouble", desc = "Diagnostics / quickfix panel (IDEA 'Problems' tool window) -- <leader>xx" },
    { mod = "neogit", desc = "Full Git tool window (IDEA 'Git' / 'Commit') -- <leader>gn" },
  }
  for _, p in ipairs(editor_plugins) do
    if pcall(require, p.mod) then
      vim.health.ok(string.format("%s: loaded (%s)", p.mod, p.desc))
    else
      vim.health.info(string.format("%s: not loaded (%s). Suggestion: :Lazy sync", p.mod, p.desc))
    end
  end

  -- undotree (persistent undo timeline / IDEA 'Local History')
  local ok_undotree = pcall(require, "undotree")
  if
    ok_undotree
    or vim.fn.exists(":UndotreeToggle") == 2
    or vim.fn.isdirectory(vim.fn.stdpath("data") .. "/lazy/undotree") == 1
  then
    vim.health.ok("undotree: available (persistent undo timeline / IDEA 'Local History') -- <leader>uu")
  else
    vim.health.info("undotree: not loaded (IDEA 'Local History'). Suggestion: :Lazy sync")
  end

  -- jdtls decompiler bundle -- IDEA bundled decompiler parity. Ships as jars
  -- under the dgileadi/vscode-java-decompiler lazy plugin; ftplugin/java.lua
  -- globs them into the jdtls bundle list.
  local decompiler_root = vim.fn.stdpath("data") .. "/lazy/vscode-java-decompiler/server"
  local decompiler_jars = vim.fn.isdirectory(decompiler_root) == 1
      and vim.fn.glob(decompiler_root .. "/*.jar", true, true)
    or {}
  if type(decompiler_jars) == "table" and #decompiler_jars > 0 then
    vim.health.ok(
      string.format(
        "vscode-java-decompiler: %d bundle jar(s) -> jdtls (decompile source-less .class)",
        #decompiler_jars
      )
    )
  else
    vim.health.info("vscode-java-decompiler: no bundle jars found. Suggestion: :Lazy sync")
  end

  -- Keymap hygiene. TetraVim feeds which-key from four registration channels
  -- (core/keymaps, core/lang-keymaps, core/devops, util/jvm) plus plugin
  -- `keys=` specs. Nothing stops two of them claiming the same <leader>
  -- sequence, and Neovim silently keeps only the last binding -- so a drift
  -- like that is invisible until you press the key and get the wrong action.
  -- Flag the one shape that IS observable at runtime: a lhs that is both a
  -- complete mapping and a strict prefix of another mapping (e.g. a bare
  -- <leader>G that is also the <leader>G* group prefix). That stalls for
  -- 'timeoutlen' on every press and confuses which-key's group rendering.
  vim.health.start("TetraVim Keymap Hygiene (leader-prefix collisions)")
  local leader = vim.g.mapleader
  if type(leader) ~= "string" or leader == "" then
    leader = "\\"
  end
  local shadow_lines = {}
  for _, mode in ipairs({ "n", "x", "o" }) do
    local leader_lhs = {}
    for _, m in ipairs(vim.api.nvim_get_keymap(mode)) do
      local lhs = m.lhs or ""
      if lhs:sub(1, #leader) == leader and #lhs > #leader then
        leader_lhs[#leader_lhs + 1] = { lhs = lhs, desc = m.desc or m.rhs or "" }
      end
    end
    local reported = {}
    for _, a in ipairs(leader_lhs) do
      if not reported[a.lhs] then
        for _, b in ipairs(leader_lhs) do
          if a.lhs ~= b.lhs and b.lhs:sub(1, #a.lhs) == a.lhs then
            reported[a.lhs] = true
            shadow_lines[#shadow_lines + 1] = string.format(
              "[%s] %s is a full mapping (%s) and also the prefix of %s",
              mode,
              vim.fn.keytrans(a.lhs),
              a.desc ~= "" and a.desc or "no desc",
              vim.fn.keytrans(b.lhs)
            )
            break
          end
        end
      end
    end
  end
  if #shadow_lines == 0 then
    vim.health.ok("No <leader> mapping is also a prefix of another mapping")
  else
    for _, line in ipairs(shadow_lines) do
      vim.health.warn(line .. " -- pressing it stalls for 'timeoutlen'; move the action to a leaf key")
    end
  end
end

return M
