{
  config,
  lib,
  pkgs,
  ...
}: let
  cfg = config.modules.development.nvim.languages.ts;
in {
  options.modules.development.nvim.languages.ts = {
    enable = lib.mkEnableOption "typescript";
  };
  config = lib.mkIf cfg.enable {
    programs.nvf.settings.vim = {
      languages.ts = {
        enable = true;
        extraDiagnostics.enable = false;
        format.enable = true;
        lsp.enable = true;
        treesitter.enable = true;
      };
      lsp.lspconfig = {
        enable = true;
        sources.eslint = ''
          lspconfig.eslint.setup {
            settings = {
              workingDirectories = { mode = "auto" },
              format = true,
            },
            cmd = { "${pkgs.vscode-langservers-extracted}/bin/vscode-eslint-language-server", "--stdio" },
          }
        '';
      };
    };
  };
}
