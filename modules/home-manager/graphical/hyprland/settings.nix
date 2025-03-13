{config, ...}: {
  wayland.windowManager.hyprland.settings = {
    env = [
      "NIXOS_OZONE_WL,1"
      "WLR_NO_HARDWARE_CURSORS,1"
    ];

    exec-once = config.modules.graphical.startupCommands;

    input = {
      kb_layout = "us";
      kb_variant = "dvp";
      kb_options = "caps:escape";

      touchpad = {
        natural_scroll = "yes";
        disable_while_typing = "yes";
        scroll_factor = 0.2;
      };

      sensitivity = 0.2;
      follow_mouse = 2;
      accel_profile = "flat";

      repeat_rate = 20;
      repeat_delay = 300;
    };

    monitor = [
      "eDP-1,preferred,auto,1"
    ];

    workspace = [
      "1,monitor:eDP-1,default:true"
      "2,monitor:eDP-1"
      "3,monitor:eDP-1"
      "4,monitor:eDP-1"
      "5,monitor:eDP-1"
    ];

    general = {
      gaps_in = 5;
      gaps_out = 10;
      border_size = 3;

      layout = "master";
      allow_tearing = false;
    };

    decoration = {
      rounding = 10;
      rounding_power = 4;
      blur = {
        enabled = true;
        brightness = 1.0;
        contrast = 1.0;
        noise = 0.01;

        vibrancy = 0.2;
        vibrancy_darkness = 0.5;

        passes = 4;
        size = 7;

        popups = true;
        popups_ignorealpha = 0.2;
      };

      shadow.enabled = false;
    };

    animations = {
      enabled = true;
      bezier = "easeOutQuart, 0.25, 1, 0.25, 1";
      animation = [
        "windows, 1, 5, easeOutQuart"
        "windowsOut, 1, 5, default, popin 60%"
        "fade, 1, 5, easeOutQuart"
        "workspaces, 1, 5, easeOutQuart"
      ];
    };

    misc = {
      disable_autoreload = true;
      force_default_wallpaper = 0;
      animate_mouse_windowdragging = false;
      vrr = 1;
    };
  };
}
