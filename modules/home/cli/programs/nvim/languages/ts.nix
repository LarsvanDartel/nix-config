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
        extraDiagnostics.enable = true;
        format.enable = false;
        lsp.enable = true;
        treesitter.enable = true;
      };
      lsp.servers = {
        eslint = {
          settings = {
            workingDirectories = {
              mode = "auto";
            };
            format = true;
            nodePath = "";
            experimental = {
              useFlatConfig = false;
            };
            problems = {};
            rulesCustomizations = {};
          };
          cmd = ["${pkgs.vscode-langservers-extracted}/bin/vscode-eslint-language-server" "--stdio"];
        };
      };
    };
  };
}
