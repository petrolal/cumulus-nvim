-- TetraVim UI Theme & Statusline Integration Specs (Story 2.2, 8.2, 8.3)
--
-- Lualine and Bufferline accent colours are derived from the active
-- TetraVim "Tetris" highlight groups (see tetravim.util.theme_colors) and
-- cached on VimEnter.

local theme_colors = require("tetravim.util.theme_colors")

local function get_lualine_opts()
  local lualine_theme = {
    normal = {
      a = { fg = theme_colors.cache.bg, bg = theme_colors.cache.primary_color, bold = true },
      b = { fg = theme_colors.cache.fg, bg = theme_colors.cache.bg_cursorline },
      c = { fg = theme_colors.cache.fg_dim, bg = theme_colors.cache.statusline_bg },
    },
    insert = {
      a = { fg = theme_colors.cache.bg, bg = theme_colors.cache.secondary, bold = true },
      b = { fg = theme_colors.cache.fg, bg = theme_colors.cache.bg_cursorline },
      c = { fg = theme_colors.cache.fg_dim, bg = theme_colors.cache.statusline_bg },
    },
    visual = {
      a = { fg = theme_colors.cache.bg, bg = theme_colors.cache.purple, bold = true },
      b = { fg = theme_colors.cache.fg, bg = theme_colors.cache.bg_cursorline },
      c = { fg = theme_colors.cache.fg_dim, bg = theme_colors.cache.statusline_bg },
    },
    replace = {
      a = { fg = theme_colors.cache.bg, bg = theme_colors.cache.error, bold = true },
      b = { fg = theme_colors.cache.fg, bg = theme_colors.cache.bg_cursorline },
      c = { fg = theme_colors.cache.fg_dim, bg = theme_colors.cache.statusline_bg },
    },
    inactive = {
      a = { fg = theme_colors.cache.fg_dim, bg = theme_colors.cache.statusline_bg },
      b = { fg = theme_colors.cache.fg_dim, bg = theme_colors.cache.statusline_bg },
      c = { fg = theme_colors.cache.fg_dim, bg = theme_colors.cache.statusline_bg },
    },
  }

  local lsp_component = {
    function()
      local clients = vim.lsp.get_clients({ bufnr = 0 })
      if #clients == 0 then
        return "󰅛 No LSP"
      end
      local names = {}
      for _, client in ipairs(clients) do
        if client.name then
          table.insert(names, client.name)
        end
      end
      return "󰅍 " .. table.concat(names, ", ")
    end,
    color = { fg = theme_colors.cache.primary_color, gui = "bold" },
  }

  return {
    options = {
      theme = lualine_theme,
      globalstatus = true,
      component_separators = { left = "│", right = "│" },
      section_separators = { left = "", right = "" },
    },
    sections = {
      lualine_a = {
        {
          "mode",
          fmt = function(str)
            local icons = {
              NORMAL = "󰋜 ",
              INSERT = "󰏫 ",
              VISUAL = "󰈟 ",
              V_LINE = "󰈟 ",
              V_BLOCK = "󰈟 ",
              REPLACE = "󰑐 ",
              COMMAND = "󰌾 ",
            }
            return (icons[str] or "") .. str
          end,
        },
      },
      lualine_b = { "branch", "diff", "diagnostics" },
      lualine_c = { { "filename", path = 1 } },
      lualine_x = { lsp_component, "encoding", "fileformat", "filetype" },
      lualine_y = { "progress" },
      lualine_z = { "location" },
    },
  }
end

local function get_bufferline_opts()
  local diag_icons = { error = "󰅚 ", warning = "󰀪 ", info = "󰋽 ", hint = "󰌶 " }

  return {
    options = {
      mode = "buffers",
      numbers = "ordinal",
      diagnostics = "nvim_lsp",
      diagnostics_indicator = function(_, _, diag)
        local parts = {}
        for key, sym in pairs(diag_icons) do
          if diag[key] then
            parts[#parts + 1] = sym .. diag[key]
          end
        end
        return table.concat(parts, " ")
      end,
      show_buffer_close_icons = true,
      show_close_icon = false,
      indicator = {
        icon = "▎",
        style = "icon",
      },
      -- Slanted tabs with a soft fade between them -- the same powerline
      -- geometry the lualine section separators use.
      separator_style = "slant",
      offsets = {
        {
          filetype = "oil",
          text = "  Explorer",
          highlight = "Directory",
          text_align = "left",
          separator = true,
        },
        {
          filetype = "snacks_layout_box",
          text = "  Explorer",
          highlight = "Directory",
          text_align = "left",
          separator = true,
        },
      },
    },
    highlights = {
      buffer_selected = {
        fg = theme_colors.cache.primary_color,
        bold = true,
      },
      indicator_selected = {
        fg = theme_colors.cache.primary_color,
        bg = theme_colors.cache.primary_color,
      },
    },
  }
end

return {
  -- Prime the lualine / bufferline colour cache from the active Tetris
  -- highlights once the colourscheme has been applied.
  {
    "tetravim/theme-init",
    virtual = true,
    lazy = false,
    priority = 1000,
    config = function()
      local group = vim.api.nvim_create_augroup("tetravim_theme_init", { clear = true })

      vim.api.nvim_create_autocmd("VimEnter", {
        group = group,
        callback = function()
          theme_colors.refresh_cache()
        end,
      })
    end,
  },

  -- Lualine statusline with Mode Badges, Active LSP status pill & dynamic theme colors (Story 8.2)
  {
    "nvim-lualine/lualine.nvim",
    event = "VeryLazy",
    opts = get_lualine_opts,
  },

  -- Bufferline with Devicons, Buffer Numbers & dynamic theme-colored indicators (Story 8.3)
  {
    "akinsho/bufferline.nvim",
    event = "VeryLazy",
    opts = get_bufferline_opts,
  },
}
