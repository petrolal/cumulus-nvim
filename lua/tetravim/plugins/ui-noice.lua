-- TetraVim Noice UI Integration (Story 14.2 & Story 24.1)

return {
  {
    "folke/noice.nvim",
    event = "VeryLazy",
    opts = {
      presets = {
        -- Rounded border + padding on the LSP hover / signature popups so
        -- they match `winborder`; route the search box to the bottom and
        -- overly long :messages into a split instead of a wall of popups.
        bottom_search = true,
        long_message_to_split = true,
        lsp_doc_border = true,
      },
      cmdline = {
        enabled = true,
        view = "cmdline_popup",
        opts = {
          position = {
            row = "10%",
            col = "50%",
          },
        },
      },
      lsp = {
        progress = { enabled = false },
        override = {
          ["vim.lsp.util.convert_input_to_markdown_lines"] = true,
          ["vim.lsp.util.set_hl_from_snippet"] = true,
          ["vim.lsp.util.stylize_markdown"] = true,
        },
      },
      messages = {
        enabled = true,
        view = "mini",
      },
      popupmenu = {
        enabled = true,
        backend = "nui",
      },
      notify = {
        enabled = true,
      },
      views = {
        mini = {
          win_options = {
            winblend = 0,
          },
        },
        cmdline_popup = {
          position = {
            row = "10%",
            col = "50%",
          },
          size = {
            width = 60,
            height = "auto",
          },
        },
      },
    },
  },
}
