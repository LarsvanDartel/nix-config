# Umbriel's home config (config.toml, accelerometer rotation, touch gestures, tablet-mode keyboard and dock), as a plain home-manager module factory imported by voyager's `specialisation.umbriel`.
{}: {
  config,
  lib,
  osConfig,
  pkgs,
  ...
}: let
  noctalia = cmd: "spawn:noctalia msg ${cmd}";
  locked = action: {
    inherit action;
    allow_when_locked = true;
  };
  umbriel = "${osConfig.programs.umbriel.package}/bin/umbriel";
  noctaliaMsg = "${config.programs.noctalia.package}/bin/noctalia msg";

  # The gestures of desktop/tablet.nix (format and ordering rules there), with
  # Umbriel's actions; keep in step by hand. Touching the open overview closes
  # it on touch-down, so the bottom swipe only opens: a toggle firing on
  # release would reopen it.
  gestures = [
    "1,DU,B,*,R,${umbriel} msg overview-open"
    "1,LR,L,*,R,${umbriel} msg window-focus-left"
    "1,RL,R,*,R,${umbriel} msg window-focus-right"
    "1,UD,T,*,R,${noctaliaMsg} panel-toggle control-center"
    # 34 is SIGRTMIN (glibc), wvkbd's visibility toggle; procps rejects the name.
    "2,DU,B,*,R,${pkgs.procps}/bin/pkill --signal 34 -x wvkbd-mobintl"
    "3,UD,T,*,R,${umbriel} msg window-close"
    "3,DU,*,*,R,${umbriel} msg workspace-next"
    "3,UD,*,*,R,${umbriel} msg workspace-previous"
    "3,RL,*,*,R,${umbriel} msg window-focus-right"
    "3,LR,*,*,R,${umbriel} msg window-focus-left"
    "4,DU,*,*,R,${umbriel} msg overview-open"
    "4,UD,*,*,R,${umbriel} msg overview-close"
  ];

  lisgd-umbriel = pkgs.writeShellApplication {
    name = "lisgd-umbriel";
    runtimeInputs = [pkgs.lisgd pkgs.jq];
    text = ''
      # lisgd reads the output transform only at startup, so restart it whenever
      # eDP-1's transform or mode changes ("" while it is off).
      pid=""
      current="none"
      while read -r state; do
        [[ $state != "$current" ]] || continue
        current=$state
        if [[ -n $pid ]]; then
          kill "$pid" 2>/dev/null || true
          wait "$pid" 2>/dev/null || true
          pid=""
        fi
        [[ -n $state ]] || continue
        read -r transform width height <<<"$state"
        # Umbriel's 90/270 turn counter-clockwise, lisgd's -o clockwise.
        case $transform in
          90) o=3 ;;
          180) o=2 ;;
          270) o=1 ;;
          *) o=0 ;;
        esac
        # -w/-h are the panel's native mode; lisgd scales raw touch coordinates to them.
        lisgd -d /dev/input/touchscreen -o "$o" -w "$width" -h "$height" ${lib.concatMapStringsSep " " (g: "-g ${lib.escapeShellArg g}") gestures} &
        pid=$!
      done < <(${umbriel} subscribe outputs | jq --unbuffered -r '
        [.data[] | select(.name == "eDP-1" and .enabled)
          | "\(.transform) \(.modes[] | select(.current) | "\(.width) \(.height)")"]
        | first // ""')
      [[ -z $pid ]] || kill "$pid"
      exit 1
    '';
  };

  # Applies /run/tablet-mode (written by desktop/_umbriel/system.nix): wvkbd
  # shows on SIGUSR2 and hides on SIGUSR1, and the noctalia dock follows it,
  # as niri's switch-events do.
  tablet-mode = pkgs.writeShellApplication {
    name = "tablet-mode";
    runtimeInputs = [pkgs.procps];
    text = ''
      if [[ $(cat /run/tablet-mode 2>/dev/null) == 1 ]]; then
        signal=USR2 dock=dock-show
      else
        signal=USR1 dock=dock-hide
      fi
      # A session started folded runs this before noctalia listens.
      for _ in $(seq 20); do
        if ${noctaliaMsg} "$dock"; then
          pkill "-$signal" -x wvkbd-mobintl || true
          exit 0
        fi
        sleep 0.5
      done
      exit 1
    '';
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

  # Positions on the focused output: the named workspaces 1..9 (`workspace`
  # below) persist and sort before dynamic ones. Actions take no `--name` in
  # bind form.
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
      scrolling = {
        default_extent_fraction = 0.5;
        # Columns that don't fill the screen start at the left edge, as in niri.
        center_underfull_strip = false;
      };
      # niri's default-column-display "tabbed": Mod+W is how a column gets split.
      tabs.default_display = "tabbed";
    };

    # Every output gets its own persistent 1..9 (no `output` key).
    workspace = map (i: {name = toString i;}) (lib.range 1 9);

    # As Noctalia's Umbriel compositor-settings page, except corners and
    # shadows, which follow niri's: square tiles, and only floating windows
    # rounded (6 px) with a shadow (window_rule below).
    appearance = {
      prefer_no_csd = true;
      border_width = 2;
      corner_radius = 0;
      shadow = {
        enabled = false;
        offset_x = 0;
        offset_y = 4;
        softness = 20;
      };
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
        match.is_floating = true;
        corner_radius = 6;
        shadow = true;
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
        # Monitors: Mod+Alt is "the screen in that direction".
        "Mod+Alt+H" = "output-focus-left";
        "Mod+Alt+J" = "output-focus-down";
        "Mod+Alt+K" = "output-focus-up";
        "Mod+Alt+L" = "output-focus-right";
        "Mod+Alt+Shift+H" = "column-move-to-output-left";
        "Mod+Alt+Shift+J" = "column-move-to-output-down";
        "Mod+Alt+Shift+K" = "column-move-to-output-up";
        "Mod+Alt+Shift+L" = "column-move-to-output-right";
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

  systemd.user.services = {
    umbriel-autorotate = {
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

    # desktop/tablet.nix's `lisgd` is bound to niri.service, so stays off here.
    lisgd-umbriel = {
      Unit = {
        Description = "lisgd touchscreen gestures for Umbriel";
        PartOf = ["umbriel-session.target"];
        After = ["umbriel-session.target"];
        ConditionPathExists = "/dev/input/touchscreen";
      };
      Service = {
        ExecStart = "${lisgd-umbriel}/bin/lisgd-umbriel";
        Restart = "on-failure";
      };
      Install.WantedBy = ["umbriel-session.target"];
    };

    # Also run at login, for a session started folded.
    tablet-mode = {
      Unit = {
        Description = "Show or hide wvkbd and the noctalia dock per /run/tablet-mode";
        PartOf = ["umbriel-session.target"];
        After = ["umbriel-session.target" "noctalia.service" "wvkbd.service"];
      };
      Service = {
        Type = "oneshot";
        ExecStart = "${tablet-mode}/bin/tablet-mode";
      };
      Install.WantedBy = ["umbriel-session.target"];
    };
  };

  systemd.user.paths.tablet-mode = {
    Unit = {
      Description = "Watch /run/tablet-mode";
      PartOf = ["umbriel-session.target"];
      After = ["umbriel-session.target"];
    };
    Path.PathChanged = "/run/tablet-mode";
    Install.WantedBy = ["umbriel-session.target"];
  };
}
