{
  config,
  lib,
  ...
}: let
  cfg = config.modules.development.nvim.languages.nix;
in {
  options.modules.development.nvim.languages.nix = {
    enable = lib.mkEnableOption "nix" // {default = true;};
  };
  config = lib.mkIf cfg.enable {
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
