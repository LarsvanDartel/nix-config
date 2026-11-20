# core.yubikey — pcscd/udev + u2f PAM, and YubiKey lock/unlock of the session.
{...}: {
  den.aspects.core.yubikey.nixos = {
    config,
    lib,
    pkgs,
    ...
  }: let
    # udev and `runuser -l` give no environment: lift display, runtime dir and bus from a user process
    # with WAYLAND_DISPLAY set (noctalia's IPC socket is named after it).
    lockScript = pkgs.writeShellScript "yubikey-lock" ''
      # Swapping a Framework expansion card drops the key for about a second;
      # lock only if no YubiKey has come back.
      sleep 3
      for dev in /sys/bus/usb/devices/*; do
        [ "$(${pkgs.coreutils}/bin/cat "$dev/idVendor" 2>/dev/null)" = 1050 ] && exit 0
      done

      user=${config.cosmos.user.name}
      uid=$(${pkgs.coreutils}/bin/id -u "$user")

      for envfile in /proc/[0-9]*/environ; do
        pid=''${envfile#/proc/}
        pid=''${pid%/environ}
        owner=$(${pkgs.coreutils}/bin/stat -c %u "/proc/$pid" 2>/dev/null) || continue
        [ "$owner" = "$uid" ] || continue
        if ${pkgs.gnugrep}/bin/grep -qz '^WAYLAND_DISPLAY=' "$envfile" 2>/dev/null; then
          while IFS='=' read -r -d "" name value; do
            case "$name" in
              XDG_RUNTIME_DIR | WAYLAND_DISPLAY | DBUS_SESSION_BUS_ADDRESS)
                export "$name=$value"
                ;;
            esac
          done <"$envfile"
          break
        fi
      done

      exec ${pkgs.util-linux}/bin/runuser \
        -w XDG_RUNTIME_DIR,WAYLAND_DISPLAY,DBUS_SESSION_BUS_ADDRESS \
        -l "$user" -c "${config.cosmos.profiles.desktop.lockCommand}"
    '';

    locking = config.cosmos.profiles.desktop.lockCommand != "";

    sessionUnlock = pkgs.writeShellApplication {
      name = "yubikey-session-unlock";
      runtimeInputs = [config.systemd.package pkgs.coreutils pkgs.pamtester];
      text = ''
        session=$(loginctl show-user "$(id -u)" -p Display --value 2>/dev/null) || exit 0
        # No live graphical session (greeter, logout): touching the YubiKey is the greeter's.
        [ -n "$session" ] || exit 0
        [ "$(loginctl show-session "$session" -p State --value)" != closing ] || exit 0
        [ "$(loginctl show-session "$session" -p LockedHint --value)" = yes ] || exit 0
        # pam_u2f is the presence check: a key in /etc/u2f_mappings and a touch.
        pamtester yubikey-unlock "$(id -un)" authenticate
        # noctalia unlocks on logind's Unlock signal and keeps LockedHint current.
        loginctl unlock-session "$session"
      '';
    };
  in {
    options.cosmos.profiles.desktop.lockCommand = lib.mkOption {
      type = lib.types.str;
      default = "";
      description = ''
        Command that locks the current graphical session, run as the primary
        user. Each compositor locks differently (noctalia's own IPC under
        niri), so the active compositor aspect sets this rather than yubikey
        hardcoding one. Empty means "nothing knows how to lock this session".
      '';
    };

    config = {
      services = {
        pcscd.enable = true;
        udev.packages = with pkgs; [yubikey-personalization];
        dbus.packages = [pkgs.gcr_4];

        # Removal goes through a unit because udev kills slow RUN programs. Insertion uses SYSTEMD_USER_WANTS
        # (for the seat user's hidraw ACL) and matches only `add`: `change` events (e.g. logout) would start it too.
        udev.extraRules = lib.mkIf locking ''
          ACTION=="remove",\
           ENV{ID_BUS}=="usb",\
           ENV{ID_MODEL_ID}=="0407",\
           ENV{ID_VENDOR_ID}=="1050",\
           ENV{ID_VENDOR}=="Yubico",\
           RUN+="${config.systemd.package}/bin/systemctl start --no-block yubikey-lock.service"
          ACTION=="add",\
           SUBSYSTEM=="hidraw",\
           ENV{ID_FIDO_TOKEN}=="1",\
           ENV{ID_VENDOR_ID}=="1050",\
           TAG+="systemd",\
           ENV{SYSTEMD_USER_WANTS}+="yubikey-unlock.service"
        '';
      };

      systemd.services.yubikey-lock = lib.mkIf locking {
        description = "Lock the session once the YubiKey is gone";
        serviceConfig = {
          Type = "oneshot";
          ExecStart = lockScript;
        };
      };

      systemd.user.services.yubikey-unlock = lib.mkIf locking {
        description = "Unlock the session once an enrolled YubiKey is touched";
        unitConfig.ConditionUser = config.cosmos.user.name;
        serviceConfig = {
          Type = "oneshot";
          ExecStart = lib.getExe sessionUnlock;
        };
      };

      # No touch notification at login or on the lock screen: noctalia is not up yet, or the lock covers it.
      programs.yubikey-touch-detector.enable = locking;

      security.pam.services = {
        swaylock.u2fAuth = true;
        login.u2fAuth = true;
        sudo.u2fAuth = true;
        # u2f alone: a missed touch must fail, not fall through to a password.
        yubikey-unlock = lib.mkIf locking {
          u2fAuth = true;
          unixAuth = false;
        };
      };

      # A pam_u2f mapping is public, safe to commit. Regenerate per key with:
      #   nix-shell -p pam_u2f --run pamu2fcfg
      security.pam.u2f.settings = {
        authfile = "/etc/u2f_mappings";
        cue = true;
      };
      environment.etc."u2f_mappings".text = ''
        lvdar:+0Nq9mLtzuuybj50ahAcSdMvQZv7UTh0hSPfe/Cv8/A9ijm416iV4dAojz0eSleHRhSHJNLhS0mlEXcwQyUBVQ==,e9+b7YvzT8HCv8SxwZrg3n0Qpc1h/i86PvwITyrYetPy8lA9reWaZUO6oyOhR7s42ZlkxfKHe1sNXDOfVWNE5w==,es256,+presence
      '';
    };
  };
}
