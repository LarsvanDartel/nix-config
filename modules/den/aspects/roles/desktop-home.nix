# roles.desktop-home — the desktop home environment for the primary user on
# desktop hosts (was the homeManager `desktop` aggregate).
{den, ...}: {
  den.aspects.roles.desktop-home = {
    includes = with den.aspects.home; [
      styling
      wallpapers
      hyprland
      foot
      firefox
      mpv
      spotify
      discord
      signal
      kde-connect
      bluetuith
      pulsemixer
      calculator
    ];

    # profile value: nvim in wayland mode on desktop.
    homeManager = {...}: {
      cosmos.cli.programs.nvim.wayland = true;
    };
  };
}
