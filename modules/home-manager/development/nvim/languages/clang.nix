{
  config,
  lib,
  ...
}: let
  cfg = config.modules.development.nvim.languages.clang;
in {
  options.modules.development.nvim.languages.clang = {
    enable = lib.mkEnableOption "clang";
  };
  config = lib.mkIf cfg.enable {
    programs.nvf.settings.vim.languages.clang = {
      enable = true;
      lsp.enable = true;
      treesitter.enable = true;
    };
  };
}
