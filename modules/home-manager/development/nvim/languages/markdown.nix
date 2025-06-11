{
  config,
  lib,
  ...
}: let
  inherit (lib.options) mkEnableOption;
  inherit (lib.modules) mkIf;

  cfg = config.modules.development.nvim.languages.markdown;
in {
  options.modules.development.nvim.languages.markdown = {
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
