{
  wayland.windowManager.hyprland.settings = {
    layerrule = [
      "blur, notifications"
      "blur, rofi"
      "dimaround, rofi"
    ];

    windowrulev2 = [
      "float, class:^(org.gnome.Calculator|Rofi)$"
      "size 390 490, class:^(org.gnome.Calculator)$"

      "float, title:^(Picture-in-Picture)$"
      "pin, title:^(Picture-in-Picture)$"

      "workspace 5 silent, title:^(Spotify Player)$"

      "workspace special silent, title:^((Firefox|Zen) - Sharing Indicator)$"
      "workspace special silent, title:^(.*is sharing (your screen|a window)\.)$"

      "idleinhibit focus, class:^(zen)$, title:^(.*YouTube.*)$"
      "idleinhibit fullscreen, class:.*"
    ];
  };
}
