{
  config,
  lib,
  ...
}: let
  cfg = config.modules.development.nvim.languages.css;
in {
  options.modules.development.nvim.languages.css = {
    enable = lib.mkEnableOption "css";
  };
  config = lib.mkIf cfg.enable {
    programs.nvf.settings.vim.languages.css = {
      enable = true;
      format.enable = true;
      lsp.enable = true;
      treesitter.enable = true;
    };
  };
}
