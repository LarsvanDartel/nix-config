{
  config,
  lib,
  pkgs,
  ...
}: let
  inherit (lib.modules) mkIf;

  cfg = config.cosmos.desktops.hyprland;
in {
  config = mkIf cfg.enable {
    wayland.windowManager.hyprland = {
      enable = true;

      systemd.enable = true;
      systemd.enableXdgAutostart = true;
      xwayland.enable = true;

      settings = {
        env = [
          "NIXOS_OZONE_WL,1"
          "WLR_NO_HARDWARE_CURSORS,1"
        ];

        exec-once =
          [
            "${pkgs.polkit_gnome}/libexec/polkit-gnome-authentication-agent-1"
            "${pkgs.clipse}/bin/clipse -listen"
          ]
          ++ cfg.exec-once-extras;

        monitor = ["eDP-1,preferred,auto,1"];

        input = {
          kb_layout = "us, us";
          kb_variant = "dvp, intl";
          kb_options = "caps:escape, grp:win_space_toggle";

          touchpad = {
            natural_scroll = "yes";
            scroll_factor = 0.2;
          };

          sensitivity = 0.2;
          follow_mouse = 2;
          accel_profile = "flat";

          repeat_rate = 20;
          repeat_delay = 300;
        };

        general = {
          gaps_in = 3;
          gaps_out = 5;
          gaps_workspaces = 0;
          border_size = 3;
          resize_on_border = true;
          layout = "dwindle";
        };

        dwindle = {
          force_split = 2;
        };

        decoration = {
          rounding = 5;
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

        misc = let
          FULLSCREEN_ONLY = 2;
        in {
          vfr = true;
          vrr = FULLSCREEN_ONLY;

          animate_manual_resizes = true;
          animate_mouse_windowdragging = true;
          enable_swallow = true;
          swallow_regex = "(foot|footclient|kitty|allacritty|Alacritty|ghostty|Ghostty)";
          focus_on_activate = true;
          # disable_scale_checks = true;
          disable_autoreload = true;
          disable_splash_rendering = true;
          disable_hyprland_logo = true;
          force_default_wallpaper = 0;
          # new_window_takes_over_fullscreen = 2;
          allow_session_lock_restore = true;
          initial_workspace_tracking = true;
        };

        xwayland = {
          force_zero_scaling = false;
        };

        cursor = {
          sync_gsettings_theme = true;
          no_hardware_cursors = true;
        };
      };
    };
  };
}
