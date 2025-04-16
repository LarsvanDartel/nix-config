{
  config,
  lib,
  ...
}: let
  cfg = config.modules.development.nvim.languages.html;
in {
  options.modules.development.nvim.languages.html = {
    enable = lib.mkEnableOption "html";
  };
  config = lib.mkIf cfg.enable {
    programs.nvf.settings.vim.languages.html = {
      enable = true;
      treesitter.enable = true;
    };
  };
}
