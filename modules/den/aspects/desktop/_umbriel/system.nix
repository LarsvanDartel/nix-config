# desktop.umbriel — NixOS body of the umbriel aspect: compositor, greeter entry, tablet-mode switch.
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

  # Umbriel has no tablet-mode events and libinput needs /dev/input, hence root.
  # It only records the state; tablet-mode.path in home/desktop/_umbriel/home.nix acts on it.
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
