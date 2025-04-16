{
  config,
  lib,
  ...
}: let
  cfg = config.modules.development.nvim.languages.tailwind;
in {
  options.modules.development.nvim.languages.tailwind = {
    enable = lib.mkEnableOption "tailwind";
  };
  config = lib.mkIf cfg.enable {
    programs.nvf.settings.vim.languages.tailwind = {
      enable = true;
      lsp.enable = true;
    };
  };
}
