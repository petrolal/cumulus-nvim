-- TetraVim Autocompletion / IntelliSense (nvim-cmp + LuaSnip)
--
-- The distro ships the themed `CmpItem*` highlight set (theme/tetris.lua) and
-- advertises cmp's extended completion capabilities to every LSP server via
-- `util/lsp_capabilities`, but nvim-cmp itself was never actually configured --
-- no LSP source, no snippet engine, no keymaps. This wires the full stack:
--
--   nvim_lsp  -> every server configured in lsp-*.lua / cloud-*.lua / jdtls /
--                metals (they all get `cmp_nvim_lsp.default_capabilities()`)
--   luasnip   -> LuaSnip + rafamadriz/friendly-snippets (VSCode-format packs)
--   path      -> filesystem paths
--   buffer    -> words from open buffers (fallback)
--
-- SQL buffers additionally get `vim-dadbod-completion` merged in buffer-locally
-- by tools-dadbod.lua -- that calls `cmp.setup.buffer{}`, which layers on top of
-- the global config defined here, so nothing there needs to change.

return {
  -- Snippet engine + snippet content ---------------------------------------
  {
    "L3MON4D3/LuaSnip",
    version = "v2.*",
    build = (function()
      if vim.fn.has("win32") == 1 or vim.fn.executable("make") == 0 then
        return nil
      end
      return "make install_jsregexp"
    end)(),
    dependencies = {
      {
        "rafamadriz/friendly-snippets",
        config = function()
          -- VSCode-format snippet packs (one per language) -> LuaSnip.
          require("luasnip.loaders.from_vscode").lazy_load()
          -- Project-local snippets: <config>/snippets/<ft>.json, if present.
          require("luasnip.loaders.from_vscode").lazy_load({
            paths = { vim.fn.stdpath("config") .. "/snippets" },
          })
        end,
      },
    },
    opts = {
      history = true,
      delete_check_events = "TextChanged",
      -- Don't keep a snippet session "live" after the cursor leaves it.
      region_check_events = "CursorMoved",
    },
  },

  -- Completion UI + sources ----------------------------------------------
  {
    "hrsh7th/nvim-cmp",
    event = { "InsertEnter", "CmdlineEnter" },
    dependencies = {
      "hrsh7th/cmp-nvim-lsp",
      "hrsh7th/cmp-nvim-lsp-signature-help",
      "hrsh7th/cmp-buffer",
      "hrsh7th/cmp-path",
      "hrsh7th/cmp-cmdline",
      "saadparwaiz1/cmp_luasnip",
      "L3MON4D3/LuaSnip",
    },
    opts = function(_, opts)
      local cmp = require("cmp")
      local compare = require("cmp.config.compare")
      local luasnip = require("luasnip")

      -- Popup menu behaviour: show even for a single match, never
      -- pre-select, keep a compact height.
      vim.opt.completeopt = { "menu", "menuone", "noselect" }
      vim.opt.pumheight = 12

      local function has_words_before()
        local line, col = unpack(vim.api.nvim_win_get_cursor(0))
        return col ~= 0 and vim.api.nvim_buf_get_lines(0, line - 1, line, true)[1]:sub(col, col):match("%s") == nil
      end

      local kind_icons = {
        Text = "󰉿",
        Method = "󰆧",
        Function = "󰊕",
        Constructor = "",
        Field = "󰜢",
        Variable = "󰀫",
        Class = "󰠱",
        Interface = "",
        Module = "",
        Property = "󰜢",
        Unit = "󰑭",
        Value = "󰎠",
        Enum = "",
        Keyword = "󰌋",
        Snippet = "",
        Color = "󰏘",
        File = "󰈙",
        Reference = "󰈇",
        Folder = "󰉋",
        EnumMember = "",
        Constant = "󰏿",
        Struct = "󰙅",
        Event = "",
        Operator = "󰆕",
        TypeParameter = "",
      }

      opts.snippet = {
        expand = function(args)
          luasnip.lsp_expand(args.body)
        end,
      }

      -- `completion.completeopt` is left at cmp's default
      -- ("menu,menuone,noselect"), which already matches `vim.opt.completeopt`
      -- set above -- no need to restate it here.

      opts.window = {
        completion = cmp.config.window.bordered(),
        documentation = cmp.config.window.bordered(),
      }

      opts.formatting = {
        fields = { "kind", "abbr", "menu" },
        format = function(entry, item)
          item.kind = string.format("%s %s", kind_icons[item.kind] or "", item.kind or "")
          item.menu = ({
            nvim_lsp = "[LSP]",
            nvim_lsp_signature_help = "[Sig]",
            luasnip = "[Snip]",
            buffer = "[Buf]",
            path = "[Path]",
            ["vim-dadbod-completion"] = "[DB]",
          })[entry.source.name] or ("[" .. entry.source.name .. "]")
          local max = 50
          if vim.fn.strchars(item.abbr) > max then
            item.abbr = vim.fn.strcharpart(item.abbr, 0, max) .. "…"
          end
          return item
        end,
      }

      opts.mapping = cmp.mapping.preset.insert({
        ["<C-b>"] = cmp.mapping.scroll_docs(-4),
        ["<C-f>"] = cmp.mapping.scroll_docs(4),
        ["<C-Space>"] = cmp.mapping.complete(),
        ["<C-e>"] = cmp.mapping.abort(),
        -- Explicit confirm only -- never steal <CR> when nothing is selected.
        ["<CR>"] = cmp.mapping.confirm({ select = false }),
        ["<Tab>"] = cmp.mapping(function(fallback)
          if cmp.visible() then
            cmp.select_next_item()
          elseif luasnip.locally_jumpable(1) then
            luasnip.jump(1)
          elseif has_words_before() then
            cmp.complete()
          else
            fallback()
          end
        end, { "i", "s" }),
        ["<S-Tab>"] = cmp.mapping(function(fallback)
          if cmp.visible() then
            cmp.select_prev_item()
          elseif luasnip.locally_jumpable(-1) then
            luasnip.jump(-1)
          else
            fallback()
          end
        end, { "i", "s" }),
      })

      opts.sources = cmp.config.sources({
        { name = "nvim_lsp", priority = 1000 },
        -- Shows the current parameter's signature as a virtual "completion"
        -- entry while typing call args -- complements the <C-k> on-demand
        -- signature help wired in util/lsp_attach.lua.
        { name = "nvim_lsp_signature_help", priority = 900 },
        { name = "luasnip", priority = 750 },
        { name = "path", priority = 500 },
      }, {
        { name = "buffer", priority = 250, keyword_length = 3 },
      })

      -- Deterministic ranking: exact prefix match first, then cmp's fuzzy
      -- score, then most-recently-used and same-scope locality (so a symbol
      -- you just picked / one defined nearby floats up), before falling back
      -- to kind / alphabetical. `recently_used` above `score` is what makes
      -- the menu feel like it learns within a session.
      opts.sorting = {
        priority_weight = 2,
        comparators = {
          compare.offset,
          compare.exact,
          compare.score,
          compare.recently_used,
          compare.locality,
          compare.kind,
          compare.sort_text,
          compare.length,
          compare.order,
        },
      }

      -- Guard against a stray "emoji" source contributed by another spec
      -- (kept from the previous stub -- harmless if never present).
      for i = #opts.sources, 1, -1 do
        if opts.sources[i].name == "emoji" then
          table.remove(opts.sources, i)
        end
      end

      opts.experimental = { ghost_text = { hl_group = "CmpGhostText" } }

      return opts
    end,
    config = function(_, opts)
      local cmp = require("cmp")
      cmp.setup(opts)

      -- `:` command-line completion (commands + paths).
      cmp.setup.cmdline(":", {
        mapping = cmp.mapping.preset.cmdline(),
        sources = cmp.config.sources({
          { name = "path" },
        }, {
          { name = "cmdline" },
        }),
      })

      -- `/` and `?` search completion from the current buffer.
      for _, c in ipairs({ "/", "?" }) do
        cmp.setup.cmdline(c, {
          mapping = cmp.mapping.preset.cmdline(),
          sources = { { name = "buffer" } },
        })
      end
    end,
  },
}
