{
  config,
  lib,
  pkgs,
  ...
}: let
  cfg = config.modules.alacritty;
in {
  options.modules.alacritty = {
    enable = lib.mkEnableOption "alacritty";
  };

  config = lib.mkIf cfg.enable {
    programs.alacritty = {
      enable = true;
    };
  };
}
