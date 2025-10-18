{
  config,
  lib,
  pkgs,
  ...
}: let
  inherit (lib.options) mkEnableOption;
  inherit (lib.modules) mkIf mkForce;
  inherit (lib.meta) getExe;

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
      lsp.servers = {
        vtsls = {
          filetypes = ["typescript" "javascript" "javascriptreact" "typescriptreact" "vue"];
          settings = {
            vtsls = {
              tsserver = {
                globalPlugins = [
                  {
                    name = "@vue/typescript-plugin";
                    location = "${pkgs.vue-language-server}/lib/language-tools/packages/language-server/node_modules/@vue/typescript-plugin";
                    languages = ["vue"];
                    configNamespace = "typescript";
                  }
                ];
              };
            };
          };
          cmd = [(getExe pkgs.vtsls) "--stdio"];
        };
      };
    };
  };
}
