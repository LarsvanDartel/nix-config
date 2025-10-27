{
  config,
  lib,
  pkgs,
  ...
}: let
  inherit (lib.options) mkEnableOption;
  inherit (lib.modules) mkIf;

  cfg = config.cosmos.cli.programs.nvim.languages.python;
in {
  options.cosmos.cli.programs.nvim.languages.python = {
    enable = mkEnableOption "python";
  };
  config = mkIf cfg.enable {
    programs.nvf.settings.vim = {
      languages.python = {
        enable = true;
        format.enable = true;
        lsp.enable = true;
        treesitter.enable = true;
      };
      extraPlugins = with pkgs.vimPlugins; {
        jupytext = {
          package = jupytext-nvim;
          setup = ''
            require('jupytext').setup {
              style = "hydrogen",
              output_extension = "auto",
              force_ft = nil,
              custom_language_formatting = {},
            }
          '';
        };
      };
      extraPackages = with pkgs.python3Packages; [
        jupytext
      ];
    };
  };
}
