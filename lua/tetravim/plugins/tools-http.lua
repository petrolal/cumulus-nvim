-- TetraVim HTTP Client & REST API Explorer (Postman/IntelliJ HTTP Client
-- Parity) -- SPEC-3.2
--
-- kulala.nvim is the sole .http execution/response engine (never a
-- hand-written HTTP request executor, per the spec's "Never" boundary).
-- This file only wires the plugin up; the custom pieces this story adds
-- (OpenAPI-spec-to-.http generation, jq response filtering) live in
-- tetravim.util.openapi / tetravim.util.http and are driven from the
-- <leader>ah keymap group in core/keymaps.lua -- mirroring how
-- tools-dadbod.lua owns only the plugin spec while <leader>ad's actual
-- keymaps live in keymaps.lua.

return {
  {
    "mistweaverco/kulala.nvim",
    -- kulala.nvim shells out to `curl` as its actual request backend (it
    -- builds a curl invocation from each .http block), so `curl` must be on
    -- $PATH for <leader>ahr to work -- see the :checkhealth entry in
    -- lua/tetravim/health.lua.
    -- Lazy-load on .http buffers only -- never on the wider set kulala's
    -- own README suggests (http/rest/javascript/lua), since this story's
    -- scope is the .http workflow, not kulala's JS/TS scripting surface.
    ft = { "http" },
    opts = {
      treesitter = {
        enable = false,
      },
      ui = {
        -- Force a persistent split, never a floating window, per this
        -- epic's established response-display UX pattern. "split" is a
        -- documented kulala.nvim option (kulala/config/defaults.lua's
        -- ui.display_mode, one of "split"|"float"), so no custom
        -- workaround is needed here.
        display_mode = "split",
        split_direction = "right",
      },
    },
    config = function(_, opts)
      require("kulala").setup(opts)
    end,
  },
}
