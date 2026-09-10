-- TetraVim Telescope & Ripgrep Integration (Story 16.1, 16.2 & Story 22.1)

local ui = require("tetravim.util.ui")

return {
  {
    "nvim-telescope/telescope.nvim",
    dependencies = {
      "nvim-lua/plenary.nvim",
      {
        "nvim-telescope/telescope-fzf-native.nvim",
        build = "make",
        config = function()
          pcall(function()
            require("telescope").load_extension("fzf")
          end)
        end,
      },
      "nvim-telescope/telescope-ui-select.nvim",
    },
    cmd = { "Telescope", "TelescopeMavenModules", "TelescopeGradleModules" },
    opts = function(_, opts)
      opts.defaults = opts.defaults or {}
      opts.defaults.layout_strategy = "horizontal"
      opts.defaults.layout_config = vim.tbl_deep_extend("force", opts.defaults.layout_config or {}, {
        prompt_position = "top",
      })
      opts.defaults.sorting_strategy = "ascending"
      opts.defaults.winblend = 0
      opts.defaults.vimgrep_arguments = {
        "rg",
        "--color=never",
        "--no-heading",
        "--with-filename",
        "--line-number",
        "--column",
        "--smart-case",
        "--hidden",
        "--glob",
        "!**/.git/*",
      }
      opts.extensions = vim.tbl_deep_extend("force", opts.extensions or {}, {
        ["ui-select"] = {
          require("telescope.themes").get_dropdown({}),
        },
      })
      return opts
    end,
    config = function(_, opts)
      local telescope = require("telescope")
      telescope.setup(opts)
      pcall(telescope.load_extension, "fzf")
      pcall(telescope.load_extension, "ui-select")

      --- Discover build-file-bearing directories under `root` as modules.
      ---@param root string
      ---@param markers string[]
      ---@return { name: string, path: string }[]
      local function discover_modules(root, markers)
        local seen, modules = {}, {}
        for _, marker in ipairs(markers) do
          for _, file in ipairs(vim.fs.find(marker, { type = "file", limit = math.huge, path = root })) do
            local dir = vim.fs.dirname(file)
            if not seen[dir] then
              seen[dir] = true
              modules[#modules + 1] = { name = vim.fs.basename(dir), path = dir }
            end
          end
        end
        table.sort(modules, function(a, b)
          return a.path < b.path
        end)
        return modules
      end

      vim.api.nvim_create_user_command("TelescopeMavenModules", function()
        local modules = discover_modules(vim.fn.getcwd(), { "pom.xml" })
        if #modules == 0 then
          ui.notify_warn("No Maven modules found")
          return
        end

        vim.ui.select(modules, {
          prompt = "Select Maven Module:",
          format_item = function(item)
            return string.format("%s (%s)", item.name, item.path)
          end,
        }, function(choice)
          if choice then
            local build_file = choice.path
            if vim.fn.isdirectory(build_file) == 1 then
              local pom = build_file .. "/pom.xml"
              if vim.fn.filereadable(pom) == 1 then
                build_file = pom
              end
            end
            if vim.fn.filereadable(build_file) == 1 then
              vim.cmd("edit " .. vim.fn.fnameescape(build_file))
            else
              ui.notify_warn("Build file not found for module: " .. choice.name)
            end
          end
        end)
      end, { desc = "List and open Maven sub-modules" })

      vim.api.nvim_create_user_command("TelescopeGradleModules", function()
        local modules = discover_modules(vim.fn.getcwd(), { "build.gradle", "build.gradle.kts" })
        if #modules == 0 then
          ui.notify_warn("No Gradle modules found")
          return
        end

        vim.ui.select(modules, {
          prompt = "Select Gradle Module:",
          format_item = function(item)
            return string.format("%s (%s)", item.name, item.path)
          end,
        }, function(choice)
          if choice then
            local build_file = choice.path
            if vim.fn.isdirectory(build_file) == 1 then
              local gradle = build_file .. "/build.gradle"
              local gradle_kts = build_file .. "/build.gradle.kts"
              if vim.fn.filereadable(gradle) == 1 then
                build_file = gradle
              elseif vim.fn.filereadable(gradle_kts) == 1 then
                build_file = gradle_kts
              end
            end
            if vim.fn.filereadable(build_file) == 1 then
              vim.cmd("edit " .. vim.fn.fnameescape(build_file))
            else
              ui.notify_warn("Build file not found for module: " .. choice.name)
            end
          end
        end)
      end, { desc = "List and open Gradle sub-modules" })
    end,
  },
}
