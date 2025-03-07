{
  pkgs,
  config,
  lib,
  ...
}: let
  cfg = config.nvim;
in {
  options.nvim = {
    enable = lib.mkEnableOption "Enable nvim";
  };

  config = lib.mkIf cfg.enable {
    programs.neovim = {
      enable = true;
      defaultEditor = true;
    };
    stylix.targets.neovim.enable = true;
  };
}
