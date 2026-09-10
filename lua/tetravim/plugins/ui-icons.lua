-- TetraVim Icon Provider (mini.icons)
--
-- Lightweight icon provider used by which-key (and other UI plugins).
-- which-key's healthcheck checks for mini.icons.
return {
  {
    "echasnovski/mini.icons",
    version = false,
    lazy = true,
    opts = {},
    init = function()
      -- Expose mini.icons as a mock for nvim-web-devicons so that plugins
      -- which only know about devicons still get proper icons.
      package.preload["nvim-web-devicons"] = function()
        require("mini.icons").mock_nvim_web_devicons()
        return package.loaded["nvim-web-devicons"]
      end
    end,
  },
}
