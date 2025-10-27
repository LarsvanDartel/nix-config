{
  config,
  lib,
  ...
}: let
  inherit (lib.modules) mkIf;

  cfg = config.cosmos.desktops.hyprland;
in {
  config = mkIf cfg.enable {
    wayland.windowManager.hyprland.settings = {
      layerrule = [
        "blur, notifications"
        "ignorezero, notifications"
        "blur, rofi"
        "ignorezero, rofi"
        "dimaround, rofi"
      ];

      windowrulev2 = [
        "float, class:^(org.gnome.Calculator)$"
        "size 390 490, class:^(org.gnome.Calculator)$"

        "float, title:^(Picture-in-Picture)$"
        "pin, title:^(Picture-in-Picture)$"

        "float, class:(clipse)"
        "size 622 652, class:(clipse)"

        "workspace 8 silent, class:^(discord)$"
        "workspace 8 silent, class:^(signal)$"

        "workspace 9 silent, title:^(Spotify Player)$"

        "workspace special silent, class:^(xwaylandvideobridge)$"
        "workspace special silent, title:^((Firefox|Zen) - Sharing Indicator)$"
        "workspace special silent, title:^(.*is sharing (your screen|a window)\.)$"

        "idleinhibit focus, class:^(zen)$, title:^(.*YouTube.*)$"
        "idleinhibit fullscreen, class:.*"
      ];
    };
  };
}
