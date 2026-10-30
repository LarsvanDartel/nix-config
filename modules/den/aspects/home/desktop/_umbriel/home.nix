# Umbriel's home config (config.toml + accelerometer rotation), as a plain home-manager module factory imported by voyager's `specialisation.umbriel`.
{}: {pkgs, ...}: let
  noctalia = cmd: "spawn:noctalia msg ${cmd}";
  locked = action: {
    inherit action;
    allow_when_locked = true;
  };

  # Validate edits with `umbriel config validate -c <file>`; keys: `umbriel config schema`.
  settings = {
    general.mod_key = "Super";

    input = {
      keyboard = {
        layout = "us,us";
        variant = "dvp,intl";
        options = "caps:escape,grp:win_space_toggle";
        repeat_delay = 300;
        repeat_rate = 20;
      };
      touchpad = {
        tap = true;
        natural_scroll = true;
        scroll_factor = 0.2;
        accel_profile = "flat";
      };
      touch.map_to_output = "eDP-1";
      tablet.map_to_output = "eDP-1";
    };

    # As Noctalia's Umbriel compositor-settings page.
    appearance = {
      prefer_no_csd = true;
      border_width = 2;
      corner_radius = 10;
      blur = {
        enabled = true;
        optimized = true;
        passes = 2;
        radius = 3;
        noise = 0.02;
        brightness = 0.9;
        contrast = 0.9;
        saturation = 1.1;
      };
    };

    window_rule = [
      {
        blur = true;
        blur_optimized = true;
      }
      {
        match.app_id = "^dev.noctalia.Noctalia$";
        default_floating = true;
        default_floating_size_px = {
          width = 1020;
          height = 900;
        };
      }
    ];

    layer_rule = [
      {
        match.namespace = "^noctalia-(bar-[^\"]+|notification|dock|panel|attached-panel|osd)$";
        blur = true;
        blur_ignore_alpha = 0.6;
        blur_optimized = false;
      }
    ];

    # Same combos as niri's binds (desktop/_niri/system.nix); keep in step by hand.
    keybinds = {
      "Mod+Shift+Return" = "spawn:foot";
      "Mod+Tab" = noctalia "panel-toggle launcher";
      "Mod+Escape" = noctalia "panel-toggle session";
      "Mod+Shift+Escape" = noctalia "session lock";
      "Mod+V" = noctalia "panel-toggle clipboard";
      # keyd's Mod-tap keysym (desktop.input.modTap.keysym).
      "F19" = noctalia "panel-toggle control-center";

      "Mod+Shift+C" = "window-close";
      "Mod+H" = "window-focus-left";
      "Mod+J" = "window-focus-down";
      "Mod+K" = "window-focus-up";
      "Mod+L" = "window-focus-right";
      "Mod+O" = "overview-toggle";
      "Alt+Tab" = "overview-toggle";
      "Mod+Shift+Q" = "session-quit";

      "Mod+Page_Down" = "workspace-next";
      "Mod+Page_Up" = "workspace-previous";

      "XF86MonBrightnessUp" = locked "spawn:brightnessctl set +5%";
      "XF86MonBrightnessDown" = locked "spawn:brightnessctl set 5%-";
      "XF86AudioRaiseVolume" = locked "spawn:pamixer -i 5";
      "XF86AudioLowerVolume" = locked "spawn:pamixer -d 5";
      "XF86AudioMute" = locked "spawn:pamixer --toggle-mute";
      "XF86AudioMicMute" = locked "spawn:pamixer --default-source --toggle-mute";
    };
  };
in {
  # No general.autostart: noctalia's unit starts with graphical-session.target, which umbriel-session.target binds.
  xdg.configFile."umbriel/config.toml".source = (pkgs.formats.toml {}).generate "umbriel-config.toml" settings;

  systemd.user.services.umbriel-autorotate = {
    Unit = {
      Description = "Rotate eDP-1 from the accelerometer (Umbriel has no iio tool)";
      PartOf = ["umbriel-session.target"];
      After = ["umbriel-session.target"];
    };
    Service = {
      ExecStart = toString (pkgs.writeShellScript "umbriel-autorotate" ''
        # Same orientation→transform mapping as iio-niri.
        ${pkgs.iio-sensor-proxy}/bin/monitor-sensor --accel | while read -r line; do
          case "$line" in
            *"orientation: normal"*|*"orientation changed: normal"*) t=normal ;;
            *"orientation: left-up"*|*"orientation changed: left-up"*) t=90 ;;
            *"orientation: bottom-up"*|*"orientation changed: bottom-up"*) t=180 ;;
            *"orientation: right-up"*|*"orientation changed: right-up"*) t=270 ;;
            *) continue ;;
          esac
          ${pkgs.wlr-randr}/bin/wlr-randr --output eDP-1 --transform "$t"
        done
      '');
      Restart = "on-failure";
    };
    Install.WantedBy = ["umbriel-session.target"];
  };
}
