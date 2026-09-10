-- TetraVim In-Buffer Markdown Engine Integration (Story 32.1)

return {
  {
    "MeanderingProgrammer/render-markdown.nvim",
    dependencies = { "nvim-treesitter/nvim-treesitter", "nvim-tree/nvim-web-devicons" },
    ft = { "markdown", "norg", "rmd", "org" },
    opts = {
      heading = {
        enabled = true,
        sign = true,
        icons = { "󰲡 ", "󰲣 ", "󰲥 ", "󰲧 ", "󰲩 ", "󰲫 " },
      },
      code = {
        enabled = true,
        sign = true,
        style = "full",
      },
      checkbox = {
        enabled = true,
      },
      callout = {
        note = { raw = "[!NOTE]", rendered = "󰋽 Note", highlight = "RenderMarkdownInfo" },
        tip = { raw = "[!TIP]", rendered = "󰌶 Tip", highlight = "RenderMarkdownSuccess" },
        important = { raw = "[!IMPORTANT]", rendered = "󰅾 Important", highlight = "RenderMarkdownHint" },
        warning = { raw = "[!WARNING]", rendered = "󰀪 Warning", highlight = "RenderMarkdownWarn" },
        caution = { raw = "[!CAUTION]", rendered = "󰳦 Caution", highlight = "RenderMarkdownError" },
      },
    },
  },
  {
    "iamcco/markdown-preview.nvim",
    cmd = { "MarkdownPreviewToggle", "MarkdownPreview", "MarkdownPreviewStop" },
    ft = { "markdown" },
    -- `npm install` regenerates app/yarn.lock and writes app/package-lock.json,
    -- leaving the plugin's git working tree dirty. That blocks `:Lazy update`
    -- with "You have local changes ... Please remove them to update." Discard
    -- those generated files after installing so the tree stays clean.
    build = "cd app && npm install --no-package-lock && git checkout -- yarn.lock && rm -f package-lock.json",
    init = function()
      vim.g.mkdp_filetypes = { "markdown" }
    end,
    keys = {
      {
        "<leader>um",
        "<cmd>MarkdownPreviewToggle<cr>",
        desc = "Toggle Markdown Preview (Mermaid)",
        ft = "markdown",
      },
    },
  },
}
