{
  config,
  lib,
  ...
}: let
  inherit (lib.options) mkEnableOption;
  inherit (lib.modules) mkIf;

  cfg = config.cli.programs.nvim.languages.typst;
in {
  options.cli.programs.nvim.languages.typst = {
    enable = mkEnableOption "typst";
  };

  config = mkIf cfg.enable {
    # Add templates to XDG_DATA_HOME
    # home.file.""

    programs.nvf.settings.vim.languages.typst = {
      enable = true;
      format = {
        enable = true;
        type = "typstyle";
      };
      lsp.enable = true;
      treesitter.enable = true;
      extensions.typst-preview-nvim.enable = true;
    };
  };
}
