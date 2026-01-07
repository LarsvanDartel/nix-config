{
  wayland.windowManager.hyprland.settings = {
    layerrule = [
      "blur on, ignore_alpha 0, match:namespace notifications"
      "blur on, ignore_alpha 0, dim_around on, match:namespace rofi"
    ];

    windowrule = [
      "match:class clipse, float on, size 650 650"

      "match:class discord, workspace 8 silent"
      "match:class signal, workspace 8 silent"

      "match:title (Spotify Player), workspace 9 silent"

      "match:class xwaylandvideobridge, workspace special silent"
      "match:title ((Firefox|Zen) - Sharing Indicator), workspace special silent"
      "match:title (.*is sharing (your screen|a window)\.), workspace special silent"

      "match:class .*, idle_inhibit fullscreen"
    ];
  };
}
