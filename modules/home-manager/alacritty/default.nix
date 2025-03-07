{
  config,
  lib,
  pkgs,
  ...
}:
with lib; let
  cfg = config.alacritty;
in {
  options.alacritty = {
    enable = mkEnableOption "Enable Alacritty";
  };

  config = mkIf cfg.enable {
    programs.alacritty = {
      enable = true;
    };
  };
}
