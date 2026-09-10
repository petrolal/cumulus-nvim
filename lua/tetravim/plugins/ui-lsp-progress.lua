-- TetraVim LSP / indexing progress UI
--
-- noice's own `lsp.progress` handler is disabled (see ui-noice.lua) because its
-- popup stack is noisy for a JDTLS monorepo that emits hundreds of
-- `$/progress` reports during a cold index. fidget.nvim renders the same
-- `$/progress` stream as a single, self-dismissing bottom-right widget -- the
-- IDEA "indexing / building" status bar parity. Health probe lives in
-- lua/tetravim/health.lua ("IDE-Parity Editor Tools").

return {
  {
    "j-hui/fidget.nvim",
    event = "LspAttach",
    opts = {
      progress = {
        display = {
          done_icon = "",
          progress_icon = { pattern = "dots", period = 1 },
        },
      },
      notification = {
        window = {
          winblend = 0,
          border = "rounded",
        },
      },
    },
  },
}
