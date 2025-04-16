{
  config,
  lib,
  ...
}: let
  cfg = config.modules.development.nvim.languages.markdown;
in {
  options.modules.development.nvim.languages.markdown = {
    enable = lib.mkEnableOption "markdown";
  };
  config = lib.mkIf cfg.enable {
    programs.nvf.settings.vim.languages.markdown = {
      enable = true;
      extraDiagnostics.enable = true;
      format.enable = true;
      lsp.enable = true;
      treesitter.enable = true;
    };
  };
}
