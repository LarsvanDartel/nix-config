# nvim completion — nvim-cmp with luasnip, friendly-snippets and lspkind.
{
  opts.completeopt = [
    "menu"
    "menuone"
    "noselect"
  ];

  plugins = {
    luasnip.enable = true;
    friendly-snippets.enable = true;

    lspkind = {
      enable = true;

      settings.cmp = {
        enable = true;
        menu = {
          nvim_lsp = "[LSP]";
          path = "[path]";
          luasnip = "[snip]";
          buffer = "[buffer]";
          cmdline = "[cmd]";
        };
      };
    };

    cmp = {
      enable = true;

      settings = {
        snippet.expand = "function(args) require('luasnip').lsp_expand(args.body) end";

        window = {
          completion.__raw = "cmp.config.window.bordered()";
          documentation.__raw = "cmp.config.window.bordered()";
        };

        mapping = {
          "<C-d>" = "cmp.mapping.scroll_docs(-4)";
          "<C-f>" = "cmp.mapping.scroll_docs(4)";
          "<C-Space>" = "cmp.mapping.complete()";
          "<C-e>" = "cmp.mapping.close()";
          "<C-y>" = "cmp.mapping.confirm({ select = true })";
          "<CR>" = "cmp.mapping.confirm({ select = false })";
          "<Tab>" = ''
            cmp.mapping(function(fallback)
              local luasnip = require('luasnip')
              if cmp.visible() then
                cmp.select_next_item()
              elseif luasnip.expand_or_locally_jumpable() then
                luasnip.expand_or_jump()
              else
                fallback()
              end
            end, { 'i', 's' })
          '';
          "<S-Tab>" = ''
            cmp.mapping(function(fallback)
              local luasnip = require('luasnip')
              if cmp.visible() then
                cmp.select_prev_item()
              elseif luasnip.locally_jumpable(-1) then
                luasnip.jump(-1)
              else
                fallback()
              end
            end, { 'i', 's' })
          '';
        };

        sources = [
          {name = "path";}
          {name = "nvim_lsp";}
          {name = "luasnip";}
          {
            name = "buffer";
            option.get_bufnrs.__raw = "vim.api.nvim_list_bufs";
          }
        ];
      };

      cmdline = let
        search = {
          mapping.__raw = "cmp.mapping.preset.cmdline()";
          sources = [{name = "buffer";}];
        };
      in {
        "/" = search;
        "?" = search;
        ":" = {
          mapping.__raw = "cmp.mapping.preset.cmdline()";
          sources = [
            {name = "path";}
            {name = "cmdline";}
          ];
        };
      };
    };
  };
}
