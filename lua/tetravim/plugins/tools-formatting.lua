-- TetraVim Document Formatting Specs (Story 3.1, FR3, Story 40.1, 40.2, 40.3)

return {
  {
    "stevearc/conform.nvim",
    event = { "BufReadPre", "BufNewFile" },
    opts = {
      formatters_by_ft = {
        terraform = { "terraform_fmt" },
        tf = { "terraform_fmt" },
        hcl = { "terraform_fmt" },
        ["terraform-vars"] = { "terraform_fmt" },
        kotlin = { "ktlint" },
        java = { "google-java-format" },
        groovy = { "npm-groovy-lint" },
        scala = { "scalafmt" },
        sbt = { "scalafmt" },
        html = { "prettier", "superhtml", stop_after_first = true },
        css = { "prettier", stop_after_first = true },
        scss = { "prettier", stop_after_first = true },
        less = { "prettier", stop_after_first = true },
        javascript = { "prettier", stop_after_first = true },
        typescript = { "prettier", stop_after_first = true },
        javascriptreact = { "prettier", stop_after_first = true },
        typescriptreact = { "prettier", stop_after_first = true },
        proto = { "buf" },
        toml = { "taplo" },
        -- IntelliJ IDEA Ultimate parity (see docs/ide-parity.md)
        python = { "ruff_organize_imports", "ruff_format" },
        vue = { "prettier", stop_after_first = true },
        svelte = { "prettier", stop_after_first = true },
        astro = { "prettier", stop_after_first = true },
        json = { "prettier", stop_after_first = true },
        jsonc = { "prettier", stop_after_first = true },
        markdown = { "prettier", stop_after_first = true },
        graphql = { "prettier", stop_after_first = true },
        htmldjango = { "djlint" },
        ["jinja.html"] = { "djlint" },
        lua = { "stylua" },
        sh = { "shfmt" },
        bash = { "shfmt" },
        yaml = { "prettier", "yamlfmt", stop_after_first = true },
        ["yaml.ansible"] = {},
        ["yaml.cfn"] = {},
        ["yaml.sam"] = {},
        ansible = {},
        cloudformation = {},
        sam = {},
      },
      format_on_save = function(bufnr)
        if not require("tetravim.util.edit.format").enabled(bufnr) then
          return
        end
        return {
          timeout_ms = 3000,
          async = false,
          quiet = false,
          lsp_fallback = true,
        }
      end,
    },
  },
}
