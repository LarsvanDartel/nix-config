{
  config,
  lib,
  ...
}: let
  inherit (lib.options) mkEnableOption;
  inherit (lib.modules) mkIf;

  cfg = config.cosmos.cli.programs.nvim.languages.nix;
in {
  options.cosmos.cli.programs.nvim.languages.nix = {
    enable = mkEnableOption "nix" // {default = true;};
  };
  config = mkIf cfg.enable {
    programs.nvf.settings.vim.languages.nix = {
      enable = true;
      format = {
        enable = true;
        type = "alejandra";
      };
      lsp.enable = true;
      treesitter.enable = true;
    };
  };
}
