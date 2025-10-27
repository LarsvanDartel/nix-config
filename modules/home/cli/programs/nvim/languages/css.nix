{
  config,
  lib,
  ...
}: let
  inherit (lib.options) mkEnableOption;
  inherit (lib.modules) mkIf;

  cfg = config.cosmos.cli.programs.nvim.languages.css;
in {
  options.cosmos.cli.programs.nvim.languages.css = {
    enable = mkEnableOption "css";
  };
  config = mkIf cfg.enable {
    programs.nvf.settings.vim.languages.css = {
      enable = true;
      format.enable = true;
      lsp.enable = true;
      treesitter.enable = true;
    };
  };
}
