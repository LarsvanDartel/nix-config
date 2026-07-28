# home.hyprland.hyprpaper — wallpaper daemon.
{...}: {
  den.aspects.home.hyprland.hyprpaper.homeManager = {config, ...}: {
    services.hyprpaper = {
      enable = true;
      settings = let
        inherit (config.cosmos.desktops.common.styling.wallpaper) path;
      in {
        preload = ["${path}"];
        wallpaper = [
          {
            monitor = "";
            path = "${path}";
          }
        ];
      };
    };
  };
}
