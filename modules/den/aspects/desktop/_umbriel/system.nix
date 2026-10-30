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

  # Umbriel has no tablet-mode events; libinput needs /dev/input, hence root.
  systemd.services.tablet-mode-osk = {
    description = "Show/hide wvkbd on the tablet-mode switch (Umbriel has no switch events)";
    wantedBy = ["multi-user.target"];
    path = [pkgs.procps];
    script = ''
      ${lib.getExe' pkgs.libinput "libinput"} debug-events | while read -r line; do
        case "$line" in
          *"switch tablet-mode state 1"*) pkill -USR2 -x wvkbd-mobintl || true ;;
          *"switch tablet-mode state 0"*) pkill -USR1 -x wvkbd-mobintl || true ;;
        esac
      done
    '';
    serviceConfig.Restart = "always";
  };
}
