# roles.desktop-home — the desktop home environment for the primary user on
# desktop hosts.
{den, ...}: {
  den.aspects.roles.desktop-home = {
    includes = with den.aspects.home; [
      styling
      wallpapers
      hyprland
      foot
      # Not in home-base: the 101 MB index doesn't fit on pioneer.
      comma
      zen
      mpv
      spotify
      # Pinned to a Discord URL deleted on their next build: only a store
      # that already has it (voyager) can build this closure.
      discord
      signal
      kde-connect
      bluetuith
      pulsemixer
      calculator
    ];

    homeManager = {...}: {
      cosmos.cli.programs.nvim.wayland = true;
    };
  };
}
