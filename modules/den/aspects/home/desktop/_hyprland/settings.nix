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
      configType = "lua";

      # OFF, and it has to stay off: the NixOS side runs Hyprland under uwsm
      # (programs.hyprland.withUWSM, see desktop/hyprland.nix), which owns the
      # session target. Home Manager's own integration is fatal on top of that:
      # its exec-once stops and restarts hyprland-session.target, which carries
      # PropagatesStopTo=graphical-session.target — and uwsm's
      # wayland-session@<compositor>.target is BindsTo= that target, so the
      # *stop* half tears the whole session down microseconds after it comes up:
      # greeter -> login -> black -> greeter, exit 0, no error anywhere. uwsm
      # already does everything this option would (env exports, xdg-autostart
      # target), hence no enableXdgAutostart either.
      systemd.enable = false;
      xwayland.enable = true;

      settings = {
        env = [
          {_args = ["NIXOS_OZONE_WL" "1"];}
          {_args = ["WLR_NO_HARDWARE_CURSORS" "1"];}
        ];

        monitor = [
          {
            output = "eDP-1";
            mode = "preferred";
            position = "auto";
            scale = 1;
          }
        ];

        config = {
          input = {
            kb_layout = "us, us";
            kb_variant = "dvp, intl";
            kb_options = "caps:escape, grp:win_space_toggle";

            touchpad = {
              disable_while_typing = false;
              natural_scroll = true;
              scroll_factor = 0.2;
            };

            sensitivity = 0.0;
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

          # No news screen, no donation nag — not cosmetic. On a version change
          # Hyprland spawns `hyprland-update-screen --new-version` as a child
          # of its own unit; that Qt app cannot reach the compositor socket yet
          # and SIGABRTs — a real coredump under
          # wayland-wm@hyprland.desktop.service, timed to the second with the
          # session dying (first fired by the 0.56.2 bump).
          ecosystem = {
            no_update_news = true;
            no_donation_nag = true;
          };

          misc = let
            FULLSCREEN_ONLY = 2;
          in {
            vrr = FULLSCREEN_ONLY;

            animate_manual_resizes = true;
            animate_mouse_windowdragging = true;
            enable_swallow = true;
            swallow_regex = "(foot|footclient|kitty|allacritty|Alacritty|ghostty|Ghostty)";
            focus_on_activate = true;
            disable_autoreload = true;
            disable_splash_rendering = true;
            disable_hyprland_logo = true;
            force_default_wallpaper = 0;
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

      extraConfig = let
        startupCommands =
          [
            "${pkgs.polkit_gnome}/libexec/polkit-gnome-authentication-agent-1"
            "${pkgs.clipse}/bin/clipse -listen"
          ]
          ++ cfg.exec-once-extras;
      in
        lib.optionalString (startupCommands != []) (
          lib.concatStringsSep "\n" (
            [''hl.on("hyprland.start", function()'']
            ++ map (cmd: ''hl.exec_cmd("${cmd}")'') startupCommands
            ++ ["end)"]
          )
          + "\n"
        );
    };
  };
}
