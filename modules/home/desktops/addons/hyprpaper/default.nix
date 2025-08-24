{
  config,
  lib,
  ...
}: let
  inherit (lib.options) mkEnableOption;
  inherit (lib.modules) mkIf;

  cfg = config.desktops.addons.hyprpaper;
in {
  options.desktops.addons.hyprpaper = {
    enable = mkEnableOption "hyprpaper";
  };

  config = mkIf cfg.enable {
    services.hyprpaper = {
      enable = true;

      settings = let
        inherit (config.styling.wallpaper) path;
      in {
        preload = ["${path}"];
        wallpaper = [", ${path}"];
      };
    };
  };
}
