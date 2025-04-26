{config, ...}: {
  services.hyprpaper = {
    enable = true;

    settings = let
      inherit (config.modules.styling.wallpaper) path;
    in {
      preload = ["${path}"];
      wallpaper = [", ${path}"];
    };
  };
}
