# desktop.tablet — convertible support: accelerometer auto-rotation (iio-niri), wvkbd kept running hidden for niri's tablet-mode switch events, touchscreen edge-swipe gestures (lisgd) driving niri, and the noctalia dock settings for tablet mode.
{...}: {
  den.aspects.desktop.tablet = {
    nixos = {pkgs, ...}: {
      hardware.sensor.iio.enable = true;
      services.iio-niri = {
        enable = true;
        extraArgs = ["--monitor" "eDP-1"];
      };

      # lisgd reads the touchscreen itself. uaccess grants only the active seat
      # user, and must be tagged before 73-seat-late.rules: extraRules lands in
      # 99-local.rules, too late.
      services.udev.packages = [
        (pkgs.writeTextDir "lib/udev/rules.d/70-touchscreen.rules" ''
          SUBSYSTEM=="input", KERNEL=="event*", ENV{ID_INPUT_TOUCHSCREEN}=="1", TAG+="uaccess", SYMLINK+="input/touchscreen"
        '')
      ];
    };

    provides.to-users.homeManager = {
      config,
      lib,
      osConfig,
      pkgs,
      ...
    }: let
      niri = "${osConfig.programs.niri.package}/bin/niri";
      action = a: "${niri} msg action ${a}";
      noctalia = cmd: "${config.programs.noctalia.package}/bin/noctalia msg ${cmd}";

      # nfingers,swipe,edge,distance,actmode,command. Edges are in screen
      # orientation (lisgd -o). One-finger swipes count only from an edge, so
      # scrolling in apps doesn't trigger them.
      gestures = [
        "1,DU,B,*,R,${action "toggle-overview"}"
        "1,LR,L,*,R,${action "focus-column-left"}"
        "1,RL,R,*,R,${action "focus-column-right"}"
        "1,UD,T,*,R,${noctalia "panel-toggle control-center"}"
        "3,UD,*,*,R,${action "close-window"}"
        # 34 is SIGRTMIN (glibc), wvkbd's visibility toggle; procps rejects the name.
        "2,DU,B,*,R,${pkgs.procps}/bin/pkill --signal 34 -x wvkbd-mobintl"
      ];
      gestureArgs = lib.concatMapStringsSep " " (g: "-g ${lib.escapeShellArg g}") gestures;

      lisgd-niri = pkgs.writeShellApplication {
        name = "lisgd-niri";
        runtimeInputs = [pkgs.lisgd pkgs.jq pkgs.iio-sensor-proxy];
        text = ''
          # lisgd reads the output transform only at startup, so restart it on rotation.
          state() {
            ${niri} msg -j outputs | jq -r '.["eDP-1"] | select(.logical) |
              "\(.logical.transform) \(.modes[.current_mode].width) \(.modes[.current_mode].height)"'
          }

          pid=""
          start() {
            if [[ -n $pid ]]; then
              kill "$pid" 2>/dev/null || true
              wait "$pid" 2>/dev/null || true
              pid=""
            fi
            [[ -n $1 ]] || return 0
            read -r transform width height <<<"$1"
            # niri's 90/270 turn counter-clockwise, lisgd's -o clockwise.
            case $transform in
              90) o=3 ;;
              180) o=2 ;;
              270) o=1 ;;
              *) o=0 ;;
            esac
            # -w/-h are the panel's native mode; lisgd scales raw touch coordinates to them.
            lisgd -d /dev/input/touchscreen -o "$o" -w "$width" -h "$height" ${gestureArgs} &
            pid=$!
          }

          current=$(state)
          start "$current"

          while read -r line; do
            [[ $line == *"orientation changed"* ]] || continue
            # iio-niri applies the transform on the same signal; wait for it to land.
            for _ in 1 2 3 4 5 6 7 8 9 10; do
              sleep 0.2
              new=$(state)
              [[ $new != "$current" ]] && break
            done
            if [[ $new != "$current" ]]; then
              current=$new
              start "$current"
            fi
          done < <(monitor-sensor --accel)
          [[ -z $pid ]] || wait "$pid"
        '';
      };
    in {
      systemd.user.services = {
        wvkbd = {
          Unit = {
            Description = "wvkbd on-screen keyboard (shown in tablet mode)";
            PartOf = ["graphical-session.target"];
            After = ["graphical-session.target"];
          };
          Service = {
            ExecStart = "${pkgs.wvkbd}/bin/wvkbd-mobintl --hidden -L 300";
            Restart = "on-failure";
          };
          Install.WantedBy = ["graphical-session.target"];
        };

        # The gestures are niri actions, so this runs only in niri sessions.
        lisgd = {
          Unit = {
            Description = "lisgd touchscreen edge-swipe gestures for niri";
            PartOf = ["niri.service"];
            After = ["niri.service"];
            ConditionPathExists = "/dev/input/touchscreen";
          };
          Service = {
            ExecStart = "${lisgd-niri}/bin/lisgd-niri";
            Restart = "on-failure";
          };
          Install.WantedBy = ["niri.service"];
        };
      };

      # Off until niri's tablet-mode switch events run `noctalia msg dock-show`.
      programs.noctalia.settings.dock = {
        launcher_position = "start";
        pinned = ["zen-twilight" "foot" "thunderbird"];
        # Touch has no hover to magnify on.
        magnification = false;
      };
    };
  };
}
