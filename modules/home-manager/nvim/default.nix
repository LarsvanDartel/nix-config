{
  config,
  pkgs,
  lib,
  ...
}: let
  cfg = config.modules.nvim;
in {
  options.modules.nvim = {
    enable = lib.mkEnableOption "nvim";
  };

  config = lib.mkIf cfg.enable {
    programs.neovim = {
      enable = true;
      defaultEditor = true;
    };
    stylix.targets.neovim.enable = true;
  };
}
