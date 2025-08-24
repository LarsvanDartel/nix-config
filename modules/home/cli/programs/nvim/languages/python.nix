{
  config,
  lib,
  ...
}: let
  inherit (lib.options) mkEnableOption;
  inherit (lib.modules) mkIf;

  cfg = config.cli.programs.nvim.languages.python;
in {
  options.cli.programs.nvim.languages.python = {
    enable = mkEnableOption "python";
  };
  config = mkIf cfg.enable {
    programs.nvf.settings.vim.languages.python = {
      enable = true;
      format.enable = true;
      lsp.enable = true;
      treesitter.enable = true;
    };
  };
}
