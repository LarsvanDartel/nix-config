{
  config,
  lib,
  ...
}: let
  inherit (lib.options) mkEnableOption;
  inherit (lib.modules) mkIf;

  cfg = config.cosmos.cli.programs.nvim.languages.markdown;
in {
  options.cosmos.cli.programs.nvim.languages.markdown = {
    enable = mkEnableOption "markdown";
    markview = mkEnableOption "markview";
  };

  config = mkIf cfg.enable {
    programs.nvf.settings.vim.languages.markdown = {
      enable = true;
      extraDiagnostics.enable = true;
      format.enable = true;
      lsp.enable = true;
      treesitter.enable = true;
      extensions.markview-nvim.enable = cfg.markview;
    };
  };
}
