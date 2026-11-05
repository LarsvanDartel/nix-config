# core.yubikey — pcscd/udev + u2f PAM, and YubiKey lock/unlock of the session and keyring.
{...}: {
  den.aspects.core.yubikey.nixos = {
    config,
    lib,
    pkgs,
    ...
  }: let
    # `runuser -l` resets the environment and udev has none to begin with; lift
    # the session's display, runtime dir and bus from a user process with a
    # Wayland display open (noctalia's IPC socket is named after WAYLAND_DISPLAY).
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

    # Relative to $HOME, in the dir home.keyring persists; gnome-keyring only
    # reads *.keyring files there.
    secret = ".local/share/keyrings/yubikey-unlock.age";
    recipients = ".local/share/keyrings/yubikey-unlock.recipients";

    keyringCtl = pkgs.writers.writePython3Bin "keyring-ctl" {libraries = [pkgs.python3Packages.jeepney];} (
      builtins.readFile ./_yubikey/keyring-ctl.py
    );

    # age finds the plugin on PATH.
    ageTools = [pkgs.age pkgs.age-plugin-fido2-hmac];

    keyringUnlock = pkgs.writeShellApplication {
      name = "yubikey-keyring-unlock";
      runtimeInputs = [keyringCtl pkgs.coreutils] ++ ageTools;
      text = ''
        keyring-ctl is-locked || exit 0
        present=
        for dev in /sys/bus/usb/devices/*; do
          if [ "$(cat "$dev/idVendor" 2>/dev/null)" = 1050 ]; then present=1; fi
        done
        [ -n "$present" ] || exit 0
        [ -f "$HOME/${secret}" ] || exit 0
        # Decrypting needs an enrolled YubiKey and a touch.
        password=$(age -d -j fido2-hmac "$HOME/${secret}")
        printf '%s' "$password" | keyring-ctl unlock
      '';
    };

    sessionUnlock = pkgs.writeShellApplication {
      name = "yubikey-session-unlock";
      runtimeInputs = [config.systemd.package pkgs.coreutils keyringCtl keyringUnlock] ++ ageTools;
      text = ''
        session=$(loginctl show-user "$(id -u)" -p Display --value 2>/dev/null) || exit 0
        # No live graphical session (greeter, logout): touching the YubiKey is
        # the greeter's, and the keyring would start outside any session.
        [ -n "$session" ] || exit 0
        [ "$(loginctl show-session "$session" -p State --value)" != closing ] || exit 0
        # Session already open: only the keyring may still be locked.
        if [ "$(loginctl show-session "$session" -p LockedHint --value)" != yes ]; then
          exec yubikey-keyring-unlock
        fi
        if [ ! -f "$HOME/${secret}" ]; then
          echo "$HOME/${secret} missing; run yubikey-keyring-enroll" >&2
          exit 1
        fi
        # The decryption is the presence check: an enrolled YubiKey and a touch.
        password=$(age -d -j fido2-hmac "$HOME/${secret}")
        if keyring-ctl is-locked; then
          printf '%s' "$password" | keyring-ctl unlock || echo "keyring stayed locked" >&2
        fi
        # noctalia unlocks on logind's Unlock signal and keeps LockedHint current.
        loginctl unlock-session "$session"
      '';
    };

    keyringEnroll = pkgs.writeShellApplication {
      name = "yubikey-keyring-enroll";
      runtimeInputs = [keyringCtl pkgs.coreutils pkgs.gnugrep pkgs.util-linux] ++ ageTools;
      text = ''
        work=$(mktemp -d)
        trap 'rm -rf "$work"' EXIT
        echo "Enrolling the inserted YubiKey. Answer 'no' to requiring a PIN for decryption and 'no' to a separate identity." >&2
        age-plugin-fido2-hmac -g >"$work/generated"
        recipient=$(grep -o 'age1fido2-hmac1[a-z0-9]*' "$work/generated")
        { if [ -f "$HOME/${recipients}" ]; then cat "$HOME/${recipients}"; fi; echo "$recipient"; } >"$work/recipients"
        read -rsp "Password of the default keyring: " password
        echo >&2
        printf '%s' "$password" | age -R "$work/recipients" -o "$work/secret"
        keyring-ctl lock
        echo "Touch the YubiKey again to check the enrolment." >&2
        # setsid drops the TTY like the unattended unlock does, so a PIN-bound credential fails here.
        if ! setsid -w age -d -j fido2-hmac "$work/secret" | keyring-ctl unlock; then
          echo "Check failed; nothing saved. The keyring stays locked until its password is entered." >&2
          exit 1
        fi
        install -m 600 "$work/recipients" "$HOME/${recipients}"
        install -m 600 "$work/secret" "$HOME/${secret}"
        echo "Enrolled. Run again with the other YubiKey inserted to add it." >&2
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

        # Removal runs lockCommand through a unit: the script waits, and udev kills
        # slow RUN programs. Insertion starts yubikey-unlock in the user's manager
        # (SYSTEMD_USER_WANTS) for the session bus and the seat user's hidraw ACL;
        # `add` only, as `change` events (e.g. on logout) would start it too.
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
        description = "Unlock the session and keyring once an enrolled YubiKey is touched";
        unitConfig.ConditionUser = config.cosmos.user.name;
        serviceConfig = {
          Type = "oneshot";
          ExecStart = lib.getExe sessionUnlock;
        };
      };

      # The greeter's touch only proves presence (pam_u2f), so the keyring takes
      # a second one. Before noctalia, which asks for a secret at startup and
      # would otherwise open gnome-keyring's password dialog. No key, no
      # enrolment or an open keyring skip at once; a missed touch costs 15 s.
      systemd.user.services.yubikey-login-unlock = lib.mkIf locking {
        description = "Unlock the keyring with a YubiKey touch at login";
        unitConfig.ConditionUser = config.cosmos.user.name;
        wantedBy = ["graphical-session.target"];
        partOf = ["graphical-session.target"];
        after = ["graphical-session.target"];
        before = ["noctalia.service"];
        serviceConfig = {
          Type = "oneshot";
          # `-`: a missed touch leaves the keyring to the dialog, not a failed unit.
          ExecStart = "-${pkgs.coreutils}/bin/timeout 15 ${lib.getExe keyringUnlock}";
        };
      };

      # A notification while any FIDO request waits for a touch (sudo, ssh,
      # WebAuthn, the keyring unlock), closed once touched. None at login or on
      # the lock screen: noctalia is not up yet, or the lock covers it.
      programs.yubikey-touch-detector.enable = locking;

      # noctalia's session hooks and manual enrolment call these by name.
      environment.systemPackages = lib.mkIf locking [keyringCtl keyringUnlock keyringEnroll];

      security.pam.services = {
        swaylock.u2fAuth = true;
        login.u2fAuth = true;
        sudo.u2fAuth = true;
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
