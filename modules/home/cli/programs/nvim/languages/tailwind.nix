{
  config,
  lib,
  ...
}: let
  inherit (lib.options) mkEnableOption;
  inherit (lib.modules) mkIf;

  cfg = config.cli.programs.nvim.languages.tailwind;
in {
  options.cli.programs.nvim.languages.tailwind = {
    enable = mkEnableOption "tailwind";
  };
  config = mkIf cfg.enable {
    programs.nvf.settings.vim.languages.tailwind = {
      enable = true;
      lsp.enable = true;
    };
  };
}
