{
  wayland.windowManager.hyprland.settings = {
    layer_rule = [
      {
        _args = [
          {
            match = {namespace = "notifications";};
            blur = true;
            ignore_alpha = 0;
          }
        ];
      }
      {
        _args = [
          {
            match = {namespace = "rofi";};
            blur = true;
            ignore_alpha = 0;
            dim_around = true;
          }
        ];
      }
    ];

    window_rule = [
      {
        _args = [
          {
            match = {class = "clipse";};
            float = true;
            size = "650 650";
          }
        ];
      }

      {
        _args = [
          {
            match = {class = "discord";};
            workspace = "8 silent";
          }
        ];
      }
      {
        _args = [
          {
            match = {class = "signal";};
            workspace = "8 silent";
          }
        ];
      }

      {
        _args = [
          {
            match = {title = "(Spotify Player)";};
            workspace = "9 silent";
          }
        ];
      }

      {
        _args = [
          {
            match = {class = "xwaylandvideobridge";};
            workspace = "special silent";
          }
        ];
      }
      {
        _args = [
          {
            match = {title = "((Firefox|Zen) - Sharing Indicator)";};
            workspace = "special silent";
          }
        ];
      }
      {
        _args = [
          {
            match = {title = "(.*is sharing (your screen|a window)\\.)";};
            workspace = "special silent";
          }
        ];
      }

      {
        _args = [
          {
            match = {class = ".*";};
            idle_inhibit = "fullscreen";
          }
        ];
      }
    ];
  };
}
