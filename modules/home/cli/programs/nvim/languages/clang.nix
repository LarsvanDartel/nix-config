{
  config,
  lib,
  ...
}: let
  inherit (lib.options) mkEnableOption;
  inherit (lib.modules) mkIf;

  cfg = config.cosmos.cli.programs.nvim.languages.clang;
in {
  options.cosmos.cli.programs.nvim.languages.clang = {
    enable = mkEnableOption "clang";
  };
  config = mkIf cfg.enable {
    programs.nvf.settings.vim.languages.clang = {
      enable = true;
      lsp.enable = true;
      treesitter.enable = true;
    };
  };
}
