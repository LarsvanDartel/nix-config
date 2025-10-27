{
  config,
  lib,
  ...
}: let
  inherit (lib.options) mkEnableOption;
  inherit (lib.modules) mkIf;

  cfg = config.cosmos.cli.programs.nvim.languages.html;
in {
  options.cosmos.cli.programs.nvim.languages.html = {
    enable = mkEnableOption "html";
  };
  config = mkIf cfg.enable {
    programs.nvf.settings.vim.languages.html = {
      enable = true;
      treesitter.enable = true;
    };
  };
}
