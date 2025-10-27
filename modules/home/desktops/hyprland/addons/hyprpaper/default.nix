{
  config,
  lib,
  ...
}: let
  inherit (lib.options) mkEnableOption;
  inherit (lib.modules) mkIf;

  cfg = config.cosmos.desktops.hyprland.addons.hyprpaper;
in {
  options.cosmos.desktops.hyprland.addons.hyprpaper = {
    enable = mkEnableOption "hyprpaper";
  };

  config = mkIf cfg.enable {
    services.hyprpaper = {
      enable = true;

      settings = let
        inherit (config.cosmos.desktops.common.styling.wallpaper) path;
      in {
        preload = ["${path}"];
        wallpaper = [", ${path}"];
      };
    };
  };
}
