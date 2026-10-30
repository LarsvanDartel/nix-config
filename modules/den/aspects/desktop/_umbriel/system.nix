# Umbriel system config (compositor, greeter entry, tablet-mode keyboard), as a plain NixOS module factory imported by voyager's `specialisation.umbriel`.
{}: {
  config,
  lib,
  pkgs,
  ...
}: {
  programs.umbriel.enable = true;

  cosmos.profiles.desktop.addons.greetd.sessions = [
    {
      name = "umbriel.desktop";
      path = "${config.programs.umbriel.package}/share/wayland-sessions/umbriel.desktop";
    }
  ];

  environment.systemPackages = [pkgs.wlr-randr];

  # Umbriel has no tablet-mode events, and libinput needs /dev/input, hence
  # root. It only records the state; the session's tablet-mode.path acts on it
  # (home/desktop/_umbriel/home.nix).
  systemd.services.tablet-mode-switch = {
    description = "Record the tablet-mode switch in /run/tablet-mode (Umbriel has no switch events)";
    wantedBy = ["multi-user.target"];
    # libinput reports a switch already on when it starts, never one that is off.
    script = ''
      echo 0 >/run/tablet-mode
      ${lib.getExe' pkgs.libinput "libinput"} debug-events | while read -r line; do
        case "$line" in
          *"switch tablet-mode state 1"*) echo 1 >/run/tablet-mode ;;
          *"switch tablet-mode state 0"*) echo 0 >/run/tablet-mode ;;
        esac
      done
    '';
    serviceConfig.Restart = "always";
  };
}
