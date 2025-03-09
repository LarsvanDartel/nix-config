{
  wayland.windowManager.hyprland.settings = {
    windowrulev2 = [
      "float, class:^(org.gnome.Calculator)$"
      "size 390 490, class:^(org.gnome.Calculator)$"

      "float, title:^(Picture-in-Picture)$"
      "pin, title:^(Picture-in-Picture)$"

      "workspace special silent, title:^((Firefox|Zen) - Sharing Indicator)$"
      "workspace special silent, title:^(.*is sharing (your screen|a window)\.)$"

      "idleinhibit focus, class:^(zen)$, title:^(.*YouTube.*)$"
      "idleinhibit fullscreen, class:^(zen)$"
    ];
  };
}
