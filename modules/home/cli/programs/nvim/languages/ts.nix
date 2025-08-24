{
  config,
  lib,
  pkgs,
  ...
}: let
  inherit (lib.options) mkEnableOption;
  inherit (lib.modules) mkIf;

  cfg = config.cli.programs.nvim.languages.ts;
in {
  options.cli.programs.nvim.languages.ts = {
    enable = mkEnableOption "typescript";
  };
  config = mkIf cfg.enable {
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
