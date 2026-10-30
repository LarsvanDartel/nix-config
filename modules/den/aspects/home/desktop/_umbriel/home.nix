# Umbriel's home config (config.toml + accelerometer rotation), as a plain home-manager module factory imported by voyager's `specialisation.umbriel`.
{}: {
  lib,
  pkgs,
  ...
}: let
  noctalia = cmd: "spawn:noctalia msg ${cmd}";
  locked = action: {
    inherit action;
    allow_when_locked = true;
  };

  # niri's workspaceKeys (desktop/_niri/system.nix): the unshifted keysyms of
  # the us(dvp) digit row, plus the digits for us(intl). Like niri, Umbriel
  # matches Mod+Shift+<key> on them (its own example binds Mod+Shift+1).
  workspaceKeys = [
    "ampersand"
    "bracketleft"
    "braceleft"
    "braceright"
    "parenleft"
    "equal"
    "asterisk"
    "parenright"
    "plus"
  ];

  # Positions: the named workspaces 1..9 (`workspace` below) persist and sort
  # before dynamic ones. Actions take no `--name` in bind form.
  workspaceBinds = lib.listToAttrs (
    lib.flatten (
      lib.imap1 (i: key: let
        ws = toString i;
      in
        map (k: [
          {
            name = "Mod+${k}";
            value = "workspace-switch:${ws}";
          }
          {
            name = "Mod+Shift+${k}";
            value = "column-move-to-workspace:${ws}";
          }
        ]) [key ws])
      workspaceKeys
    )
  );

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

    # As niri's layout: new columns at half width, Mod+R cycling 1/3, 1/2, 2/3.
    layout = {
      extent_presets = [0.333 0.5 0.667];
      scrolling.default_extent_fraction = 0.5;
      # niri's default-column-display "tabbed": Mod+W is how a column gets split.
      tabs.default_display = "tabbed";
    };

    # Named workspaces persist, like niri's nine.
    workspace = map (i: {name = toString i;}) (lib.range 1 9);

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
      tab_bar.hide_when_single = true;
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
      {
        match.app_id = "^calculator$";
        default_floating = true;
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
    # Not ported: Mod+Ctrl+F (no windowed fullscreen), Mod+Shift+S and
    # Alt+Print (no window screenshot), Mod+P (niri-displays is niri-only).
    keybinds =
      {
        "Mod+Shift+Return" = "spawn:foot";
        "Alt+Shift+Return" = "spawn:calculator";
        "Mod+Tab" = noctalia "panel-toggle launcher";
        "Mod+B" = noctalia "panel-toggle launcher '/rbw '";
        "Mod+Escape" = noctalia "panel-toggle session";
        "Mod+Shift+Escape" = noctalia "session lock";
        "Mod+V" = noctalia "panel-toggle clipboard";
        # keyd's Mod-tap keysym (desktop.input.modTap.keysym).
        "F19" = noctalia "panel-toggle control-center";
        "Mod+Shift+P" = noctalia "plugin alexander/screen-toolkit:service all colorPicker";
        "Mod+Shift+B" = noctalia "panel-toggle damian-ds7/battery-threshold:panel";
        # niri's Mod+Slash plugin parses niri's config; Umbriel has its own.
        "Mod+Slash" = "cheatsheet-toggle";
        "Mod+Shift+Slash" = "cheatsheet-toggle";

        "Mod+S" = noctalia "screenshot-region";
        "Print" = noctalia "screenshot-region";
        "Ctrl+Print" = noctalia "screenshot-fullscreen";

        "Mod+C" = "screencast-set-window";
        "Mod+Ctrl+C" = "screencast-set-output";
        "Mod+Ctrl+Shift+C" = "screencast-clear";

        "Mod+Shift+C" = "window-close";
        "Mod+T" = "window-toggle-floating";
        "Mod+F" = "window-toggle-fullscreen";
        "Mod+M" = "window-toggle-maximize-to-edges";
        "Mod+Shift+M" = "window-toggle-maximize";

        "Mod+H" = "window-focus-left";
        "Mod+J" = "window-focus-down";
        "Mod+K" = "window-focus-up";
        "Mod+L" = "window-focus-right";
        "Mod+Shift+H" = "column-move-left";
        "Mod+Shift+J" = "window-move-down";
        "Mod+Shift+K" = "window-move-up";
        "Mod+Shift+L" = "column-move-right";
        "Mod+Ctrl+H" = "window-modify-primary-extent:-0.1";
        "Mod+Ctrl+L" = "window-modify-primary-extent:0.1";
        "Mod+Ctrl+K" = "window-modify-secondary-extent:-0.1";
        "Mod+Ctrl+J" = "window-modify-secondary-extent:0.1";
        "Mod+R" = "window-cycle-primary-extent";

        "Mod+Comma" = "window-consume-or-expel-left";
        "Mod+Period" = "window-consume-or-expel-right";
        "Mod+W" = "column-toggle-tabbed";

        "Mod+O" = "overview-toggle";
        "Alt+Tab" = "overview-toggle";
        "Mod+Page_Down" = "workspace-next";
        "Mod+Page_Up" = "workspace-previous";
        "Mod+Shift+Q" = "session-quit";

        "XF86MonBrightnessUp" = locked "spawn:brightnessctl set +5%";
        "XF86MonBrightnessDown" = locked "spawn:brightnessctl set 5%-";
        "XF86AudioRaiseVolume" = locked "spawn:pamixer -i 5";
        "XF86AudioLowerVolume" = locked "spawn:pamixer -d 5";
        "XF86AudioMute" = locked "spawn:pamixer --toggle-mute";
        "XF86AudioMicMute" = locked "spawn:pamixer --default-source --toggle-mute";
        "XF86AudioNext" = locked "spawn:playerctl next";
        "XF86AudioPrev" = locked "spawn:playerctl previous";
        "XF86AudioPlay" = locked "spawn:playerctl play-pause";
        "XF86AudioStop" = locked "spawn:playerctl stop";
      }
      // workspaceBinds;
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
