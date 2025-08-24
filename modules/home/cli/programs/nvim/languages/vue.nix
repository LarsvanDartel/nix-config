{
  config,
  lib,
  pkgs,
  ...
}: let
  inherit (lib.options) mkEnableOption;
  inherit (lib.modules) mkIf mkForce;

  cfg = config.cli.programs.nvim.languages.vue;
in {
  options.cli.programs.nvim.languages.vue = {
    enable = mkEnableOption "vue";
  };
  config = mkIf cfg.enable {
    cli.programs.nvim.languages = {
      css.enable = mkForce true;
      html.enable = mkForce true;
      tailwind.enable = mkForce true;
      ts.enable = mkForce true;
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
