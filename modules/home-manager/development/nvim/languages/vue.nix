{
  config,
  lib,
  pkgs,
  ...
}: let
  cfg = config.modules.development.nvim.languages.vue;
in {
  options.modules.development.nvim.languages.vue = {
    enable = lib.mkEnableOption "vue";
  };
  config = lib.mkIf cfg.enable {
    modules.development.nvim.languages = {
      css.enable = lib.mkForce true;
      html.enable = lib.mkForce true;
      tailwind.enable = lib.mkForce true;
      ts.enable = lib.mkForce true;
    };
    programs.nvf.settings.vim = {
      treesitter = {
        enable = true;
        grammars = with pkgs.vimPlugins.nvim-treesitter.builtGrammars; [
          vue
          typescript
        ];
      };
      lsp = {
        lspconfig = {
          enable = true;
          sources = {
            volar = ''
              lspconfig.volar.setup {
                init_options = {
                  vue = {
                    hybridMode = true;
                  },
                  typescript = {
                    tsdk = "${pkgs.typescript}/lib/node_modules/typescript/lib",
                  },
                },
                cmd = { "${pkgs.vue-language-server}/bin/vue-language-server", "--stdio" },
              }
            '';
            ts_ls = ''
              lspconfig.ts_ls.setup {
                init_options = {
                  plugins = {
                    {
                      name = "@vue/typescript-plugin",
                      location = "${pkgs.vue-language-server}/lib/node_modules/@vue/language-server",
                      languages = { "vue" },
                    },
                  },
                },
                filetypes = { "typescript", "javascript", "javascriptreact", "typescriptreact", "vue" },
                settings = {
                  typescript = {
                    tsserver = {
                      useSyntaxServer = false,
                    },
                  },
                },
                cmd = { "${pkgs.typescript-language-server}/bin/typescript-language-server", "--stdio" },
              }
            '';
          };
        };
      };
    };
  };
}
