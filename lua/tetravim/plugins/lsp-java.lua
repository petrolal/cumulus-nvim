return {
  {
    "nvim-treesitter/nvim-treesitter",
    opts = function(_, opts)
      if type(opts.ensure_installed) == "table" then
        vim.list_extend(opts.ensure_installed, { "java" })
      end
    end,
  },

  {
    -- jdtls decompiler bundle -- IntelliJ IDEA bundled decompiler parity.
    -- With this jar in the jdtls `bundles` list (globbed in ftplugin/java.lua)
    -- plus `java.contentProvider.preferred = "fernflower"` in the settings
    -- below, go-to-definition on a library `.class` that ships no sources
    -- opens a Fernflower-decompiled buffer instead of a "no source" error.
    -- Pure jars, no build step -- lazy just needs it cloned to disk.
    "dgileadi/vscode-java-decompiler",
    lazy = true,
  },

  {
    "mfussenegger/nvim-jdtls",
    ft = { "java" },
    config = function(_, opts)
      -- JDTLS lifecycle managed via ftplugin/java.lua
    end,
    opts = function(_, opts)
      opts = opts or {}
      local lombok_path = vim.fn.expand("~/.local/share/nvim/mason/share/jdtls/lombok.jar")
      if vim.fn.filereadable(lombok_path) == 0 then
        lombok_path = vim.fn.expand("~/.local/share/nvim/mason/packages/jdtls/lombok.jar")
      end

      if vim.fn.filereadable(lombok_path) == 1 then
        local orig_full_cmd = opts.full_cmd
        opts.full_cmd = function(options)
          local cmd = orig_full_cmd and orig_full_cmd(options) or { "jdtls" }
          local has_lombok = false
          for _, arg in ipairs(cmd) do
            if type(arg) == "string" and arg:find("lombok.jar") then
              has_lombok = true
              break
            end
          end
          if not has_lombok then
            table.insert(cmd, "--jvm-arg=-javaagent:" .. lombok_path)
          end
          return cmd
        end
      end

      local orig_root_dir = opts.root_dir
      opts.root_dir = function(fname)
        local root = orig_root_dir and orig_root_dir(fname)
        if root and root ~= "" then
          return root
        end
        local ok, jdtls = pcall(require, "jdtls")
        if ok and jdtls.setup and jdtls.setup.find_root then
          root =
            jdtls.setup.find_root({ ".git", "mvnw", "gradlew", "pom.xml", "build.gradle", "build.gradle.kts" }, fname)
          if root and root ~= "" then
            return root
          end
        end
        return (fname and fname ~= "" and vim.fs.dirname(fname)) or vim.fn.getcwd()
      end

      local jvm = require("tetravim.util.jvm")
      local java21_path = jvm.find_java21_home()
      local runtimes = {}
      if java21_path then
        table.insert(runtimes, {
          name = "JavaSE-21",
          path = java21_path,
          default = true,
        })
      end

      opts.settings = vim.tbl_deep_extend("force", opts.settings or {}, {
        java = {
          configuration = {
            runtimes = runtimes,
          },
          -- Signature help with the parameter's Javadoc inline in the popup,
          -- not just the parameter list.
          signatureHelp = { enabled = true, description = { enabled = true } },
          contentProvider = { preferred = "fernflower" },
          -- Auto-attach library sources so hover / go-to-definition land in
          -- real Javadoc instead of a Fernflower decompile whenever a
          -- `-sources.jar` is actually published.
          eclipse = { downloadSources = true },
          maven = { downloadSources = true },
          gradle = { downloadSources = true },
          -- "N references" / "N implementations" lenses above every member,
          -- the way IDEA shows usage counts.
          referencesCodeLens = { enabled = true },
          implementationsCodeLens = { enabled = true },
          -- Inline parameter-name hints at every call site (jdtls only emits
          -- them for literal args unless set to "all").
          inlayHints = { parameterNames = { enabled = "all" } },
          completion = {
            favoriteStaticMembers = {
              "org.hamcrest.MatcherAssert.assertThat",
              "org.hamcrest.Matchers.*",
              "org.hamcrest.CoreMatchers.*",
              "org.junit.jupiter.api.Assertions.*",
              "java.util.Objects.requireNonNull",
              "java.util.Objects.requireNonNullElse",
              "org.mockito.Mockito.*",
            },
            filteredTypes = {
              "com.sun.*",
              "io.micrometer.shaded.*",
              "java.awt.*",
              "jdk.*",
              "sun.*",
            },
          },
          sources = {
            organizeImports = {
              starThreshold = 9999,
              staticStarThreshold = 9999,
            },
          },
          codeGeneration = {
            toString = {
              template = "${object.className}{${member.name()}=${member.value}, ${otherMembers}}",
            },
            useBlocks = true,
          },
        },
      })
      return opts
    end,
  },
}
