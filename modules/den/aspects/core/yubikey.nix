# core.yubikey — pcscd/udev + u2f PAM (was flake.modules.nixos.common in
# modules/nixos/security/yubikey.nix).
{...}: {
  den.aspects.core.yubikey.nixos = {
    config,
    lib,
    pkgs,
    ...
  }: let
    # `runuser -l` resets the environment, and a udev worker has none of
    # XDG_RUNTIME_DIR / WAYLAND_DISPLAY / DBUS_SESSION_BUS_ADDRESS to begin
    # with — noctalia's IPC needs all three (verified: it crashed on an
    # unset runtime dir, then failed to find "any running instance" once the
    # runtime dir alone was supplied). Lifted from whichever of the user's own
    # processes actually has a Wayland display open, rather than hardcoding a
    # compositor binary name, so this works under either specialisation. A
    # script file also sidesteps nested-quoting hazards in the udev RUN+=
    # line, which a `-c "…"` string embedding another command runs straight
    # into.
    lockScript = pkgs.writeShellScript "yubikey-lock" ''
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
  in {
    options.cosmos.profiles.desktop.lockCommand = lib.mkOption {
      type = lib.types.str;
      default = "";
      description = ''
        Command that locks the current graphical session, run as the primary
        user. Voyager's compositor is a boot-time specialisation switch
        (hyprland vs. niri/noctalia — see hosts/voyager.nix), and each locks
        differently (`hyprlock` vs. noctalia's own IPC), so whichever
        compositor aspect is actually active sets this rather than yubikey
        hardcoding one. Empty means "nothing knows how to lock this session".
      '';
    };

    config = {
      services = {
        pcscd.enable = true;
        udev.packages = with pkgs; [yubikey-personalization];
        dbus.packages = [pkgs.gcr];

        # lock session on yubikey removal.
        #
        # `loginctl lock-sessions` only emits logind's Session.Lock() signal —
        # it does nothing unless something is listening for it, and neither
        # hyprlock nor noctalia hook that signal; both only lock in response to
        # being run directly (see cosmos.profiles.desktop.lockCommand above and
        # lockScript above), so that's what has to run here instead.
        udev.extraRules = lib.mkIf (config.cosmos.profiles.desktop.lockCommand != "") ''
          ACTION=="remove",\
           ENV{ID_BUS}=="usb",\
           ENV{ID_MODEL_ID}=="0407",\
           ENV{ID_VENDOR_ID}=="1050",\
           ENV{ID_VENDOR}=="Yubico",\
           RUN+="${lockScript}"
        '';
      };

      security.pam.services = {
        swaylock.u2fAuth = true;
        hyprlock.u2fAuth = true;
        login.u2fAuth = true;
        sudo.u2fAuth = true;
      };

      # A pam_u2f mapping is a key handle + public key, not a credential — the
      # private key never leaves the YubiKey, so this is safe to commit in the
      # open rather than through sops. Regenerate with:
      #   nix-shell -p pam_u2f --run pamu2fcfg
      # (touch the key when it prompts) and paste the resulting line(s) here,
      # one per line for multiple keys registered to the same user.
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
