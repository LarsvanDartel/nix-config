{
  config,
  lib,
  ...
}: let
  cfg = config.modules.development.nvim.languages.python;
in {
  options.modules.development.nvim.languages.python = {
    enable = lib.mkEnableOption "python";
  };
  config = lib.mkIf cfg.enable {
    programs.nvf.settings.vim.languages.python = {
      enable = true;
      format.enable = true;
      lsp.enable = true;
      treesitter.enable = true;
    };
  };
}
